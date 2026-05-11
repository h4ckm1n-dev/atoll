import AppKit
import Darwin
import Foundation
import IOKit

struct MediaPlaybackSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var currentTime: Double
    var duration: Double
    var playbackRate: Double
    var isShuffled: Bool
    var repeatMode: MediaPlaybackRepeatMode
    var updatedAt: Date
    var artwork: NSImage?

    static let empty = MediaPlaybackSnapshot(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        currentTime: 0,
        duration: 0,
        playbackRate: 0,
        isShuffled: false,
        repeatMode: .off,
        updatedAt: .distantPast,
        artwork: nil
    )

    init(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        playbackRate: Double,
        isShuffled: Bool,
        repeatMode: MediaPlaybackRepeatMode,
        updatedAt: Date,
        artwork: NSImage?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.updatedAt = updatedAt
        self.artwork = artwork
    }

    fileprivate init(payload: MediaPlaybackPayload, includeArtwork: Bool) {
        title = payload.title
        artist = payload.artist
        album = payload.album
        isPlaying = payload.isPlaying
        currentTime = payload.currentTime
        duration = payload.duration
        playbackRate = payload.playbackRate
        isShuffled = payload.isShuffled
        repeatMode = payload.repeatMode
        updatedAt = payload.updatedAt
        if includeArtwork, let artworkData = payload.artworkData {
            artwork = NSImage(data: artworkData)
        } else {
            artwork = nil
        }
    }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTimeline: Bool {
        duration > 0
    }

    func estimatedPlaybackPosition(at date: Date = Date()) -> Double {
        guard hasTimeline else { return 0 }
        guard isPlaying else { return min(max(currentTime, 0), duration) }
        let elapsed = date.timeIntervalSince(updatedAt)
        let progressed = currentTime + elapsed * max(playbackRate, 0)
        return min(max(progressed, 0), duration)
    }

    func describesSameTrack(as other: MediaPlaybackSnapshot) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherTitle = other.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle == otherTitle else {
            return false
        }

        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherArtist = other.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedArtist == otherArtist
    }

    var subtitle: String {
        [artist, album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}

enum MediaPlaybackRepeatMode: Int, Equatable, Sendable {
    case off = 1
    case one = 2
    case all = 3

    var next: MediaPlaybackRepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

private struct MediaPlaybackPayload: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var currentTime: Double
    var duration: Double
    var playbackRate: Double
    var isShuffled: Bool
    var repeatMode: MediaPlaybackRepeatMode
    var updatedAt: Date
    var artworkData: Data?

    static let empty = MediaPlaybackPayload(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        currentTime: 0,
        duration: 0,
        playbackRate: 0,
        isShuffled: false,
        repeatMode: .off,
        updatedAt: .distantPast,
        artworkData: nil
    )

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func mergingFallback(_ fallback: MediaPlaybackPayload) -> MediaPlaybackPayload {
        MediaPlaybackPayload(
            title: title.isEmpty ? fallback.title : title,
            artist: artist.isEmpty ? fallback.artist : artist,
            album: album.isEmpty ? fallback.album : album,
            isPlaying: isPlaying || fallback.isPlaying,
            currentTime: currentTime > 0 ? currentTime : fallback.currentTime,
            duration: duration > 0 ? duration : fallback.duration,
            playbackRate: playbackRate > 0 ? playbackRate : fallback.playbackRate,
            isShuffled: isShuffled || fallback.isShuffled,
            repeatMode: repeatMode != .off ? repeatMode : fallback.repeatMode,
            updatedAt: updatedAt == .distantPast ? fallback.updatedAt : updatedAt,
            artworkData: artworkData ?? fallback.artworkData
        )
    }
}

private enum MediaRemoteCommand: Int {
    case playPause = 2
    case next = 4
    case previous = 5
}

private typealias MediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Void
private typealias MediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
private typealias MediaRemoteSetModeFunction = @convention(c) (Int) -> Void

@MainActor
@Observable
final class MediaPlaybackController {
    @ObservationIgnored
    private lazy var client = MediaRemoteNowPlayingClient()
    @ObservationIgnored
    private lazy var adapterStreamClient = MediaRemoteAdapterStreamClient()
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var refreshGeneration = 0
    private var artworkEnabled = false

    private(set) var snapshot: MediaPlaybackSnapshot = .empty

    var isAvailable: Bool {
        client.isAvailable
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh(generation: generation)
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            }
        }
        syncAdapterStream()
    }

    func stop() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        adapterStreamClient.stop()
        snapshot = .empty
    }

    func setArtworkEnabled(_ enabled: Bool) {
        guard artworkEnabled != enabled else { return }
        artworkEnabled = enabled
        if !enabled, snapshot.artwork != nil {
            snapshot.artwork = nil
        }
        syncAdapterStream()
        guard refreshTask != nil else { return }
        refresh(generation: refreshGeneration, force: true)
    }

    func refresh() {
        refresh(generation: refreshGeneration)
    }

    private func refresh(generation: Int, force: Bool = false) {
        guard refreshTask != nil else { return }
        guard force || !isRefreshing else { return }
        guard client.isAvailable else {
            snapshot = .empty
            return
        }

        isRefreshing = true
        let includeArtwork = artworkEnabled
        client.fetchPayload(includeArtwork: includeArtwork) { [weak self] payload in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.refreshTask != nil,
                      self.refreshGeneration == generation else { return }
                var nextSnapshot = MediaPlaybackSnapshot(
                    payload: payload,
                    includeArtwork: includeArtwork && self.artworkEnabled
                )
                if !nextSnapshot.hasContent, self.snapshot.hasContent {
                    nextSnapshot = self.snapshot
                    if !includeArtwork || !self.artworkEnabled {
                        nextSnapshot.artwork = nil
                    }
                } else if includeArtwork,
                          self.artworkEnabled,
                          nextSnapshot.artwork == nil,
                          let existingArtwork = self.snapshot.artwork,
                          nextSnapshot.describesSameTrack(as: self.snapshot) {
                    nextSnapshot.artwork = existingArtwork
                }
                if nextSnapshot != self.snapshot {
                    self.snapshot = nextSnapshot
                }
            }
        }
    }

    func togglePlayPause() {
        if !client.sendCommand(.playPause) {
            MediaKeySender.post(.playPause)
        }
        scheduleQuickRefresh()
    }

    func nextTrack() {
        if !client.sendCommand(.next) {
            MediaKeySender.post(.next)
        }
        scheduleQuickRefresh()
    }

    func previousTrack() {
        if !client.sendCommand(.previous) {
            MediaKeySender.post(.previous)
        }
        scheduleQuickRefresh()
    }

    func skip(seconds: Double) {
        let target = snapshot.estimatedPlaybackPosition() + seconds
        seek(to: target)
    }

    func seek(to seconds: Double) {
        guard snapshot.duration > 0 else { return }
        let clamped = min(max(seconds, 0), snapshot.duration)
        if !client.seek(to: clamped) {
            client.seekWithAdapter(to: clamped)
        }
        snapshot.currentTime = clamped
        snapshot.updatedAt = Date()
        scheduleQuickRefresh()
    }

    func toggleShuffle() {
        let nextValue = !snapshot.isShuffled
        if !client.setShuffle(enabled: nextValue) {
            client.setShuffleWithAdapter(enabled: nextValue)
        }
        snapshot.isShuffled = nextValue
        scheduleQuickRefresh()
    }

    func toggleRepeat() {
        let nextMode = snapshot.repeatMode.next
        if !client.setRepeatMode(nextMode) {
            client.setRepeatWithAdapter(nextMode)
        }
        snapshot.repeatMode = nextMode
        scheduleQuickRefresh()
    }

    private func scheduleQuickRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.refresh(generation: self?.refreshGeneration ?? 0, force: true)
        }
    }

    private func syncAdapterStream() {
        guard refreshTask != nil else {
            adapterStreamClient.stop()
            return
        }

        adapterStreamClient.start { [weak self] payload in
            Task { @MainActor [weak self] in
                self?.applyAdapterPayload(payload)
            }
        }
    }

    private func applyAdapterPayload(_ payload: MediaPlaybackPayload) {
        guard refreshTask != nil else { return }
        var nextSnapshot = MediaPlaybackSnapshot(payload: payload, includeArtwork: artworkEnabled)
        if nextSnapshot.artwork == nil,
           let existingArtwork = snapshot.artwork,
           nextSnapshot.describesSameTrack(as: snapshot) {
            nextSnapshot.artwork = existingArtwork
        }
        guard nextSnapshot.hasContent || nextSnapshot.artwork != nil else { return }
        if nextSnapshot != snapshot {
            snapshot = nextSnapshot
        }
    }
}

private final class MediaRemoteNowPlayingClient: @unchecked Sendable {
    typealias NowPlayingInfoCompletion = @convention(block) (CFDictionary?) -> Void
    typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, NowPlayingInfoCompletion) -> Void

    private let queue = DispatchQueue(label: "app.atoll.media-remote", qos: .utility)
    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetNowPlayingInfo?
    private let commandSender: MediaRemoteCommandSender?
    private let setElapsedTime: MediaRemoteSetElapsedTimeFunction?
    private let setShuffleMode: MediaRemoteSetModeFunction?
    private let setRepeatMode: MediaRemoteSetModeFunction?
    private let adapterClient = MediaRemoteAdapterClient()

    var isAvailable: Bool {
        getNowPlayingInfo != nil || commandSender != nil
    }

    init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(frameworkPath, RTLD_LAZY)

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteGetNowPlayingInfo") }) {
            getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
        } else {
            getNowPlayingInfo = nil
        }

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteSendCommand") }) {
            let function = unsafeBitCast(symbol, to: MediaRemoteSendCommandFunction.self)
            commandSender = MediaRemoteCommandSender(function)
        } else {
            commandSender = nil
        }

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteSetElapsedTime") }) {
            setElapsedTime = unsafeBitCast(symbol, to: MediaRemoteSetElapsedTimeFunction.self)
        } else {
            setElapsedTime = nil
        }

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteSetShuffleMode") }) {
            setShuffleMode = unsafeBitCast(symbol, to: MediaRemoteSetModeFunction.self)
        } else {
            setShuffleMode = nil
        }

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteSetRepeatMode") }) {
            setRepeatMode = unsafeBitCast(symbol, to: MediaRemoteSetModeFunction.self)
        } else {
            setRepeatMode = nil
        }
    }

    func sendCommand(_ command: MediaRemoteCommand) -> Bool {
        guard let commandSender else { return false }
        queue.async {
            commandSender.send(command)
        }
        return true
    }

    func seek(to seconds: Double) -> Bool {
        guard let setElapsedTime else { return false }
        queue.async {
            setElapsedTime(seconds)
        }
        return true
    }

    func seekWithAdapter(to seconds: Double) {
        adapterClient.seek(to: seconds)
    }

    func setShuffle(enabled: Bool) -> Bool {
        guard let setShuffleMode else { return false }
        let mode = enabled ? 3 : 1
        queue.async {
            setShuffleMode(mode)
        }
        return true
    }

    func setShuffleWithAdapter(enabled: Bool) {
        adapterClient.setShuffle(enabled: enabled)
    }

    func setRepeatMode(_ repeatMode: MediaPlaybackRepeatMode) -> Bool {
        guard let setRepeatMode else { return false }
        queue.async {
            setRepeatMode(repeatMode.rawValue)
        }
        return true
    }

    func setRepeatWithAdapter(_ repeatMode: MediaPlaybackRepeatMode) {
        adapterClient.setRepeatMode(repeatMode)
    }

    func fetchPayload(
        includeArtwork: Bool,
        timeout: TimeInterval = 1,
        completion: @escaping (MediaPlaybackPayload) -> Void
    ) {
        guard let getNowPlayingInfo else {
            completion(.empty)
            return
        }

        let queue = queue
        let state = MediaRemoteFetchState(completion: completion)

        queue.asyncAfter(deadline: .now() + timeout) {
            state.finish(.empty)
        }

        let nowPlayingCompletion: NowPlayingInfoCompletion = { info in
            guard !state.finished else { return }
            let payload = Self.payload(from: info, includeArtwork: includeArtwork)
            guard includeArtwork,
                  payload.artworkData == nil else {
                state.finish(payload)
                return
            }

            self.adapterClient.fetchPayload { adapterPayload in
                guard let adapterPayload else {
                    state.finish(payload)
                    return
                }
                state.finish(payload.mergingFallback(adapterPayload))
            }
        }
        let nowPlayingBlock = MediaRemoteBlockBox(nowPlayingCompletion)
        state.retain(nowPlayingBlock)

        queue.async {
            guard !state.finished else { return }
            getNowPlayingInfo(queue, nowPlayingBlock.block)
        }
    }

    private static func payload(
        from info: CFDictionary?,
        includeArtwork: Bool
    ) -> MediaPlaybackPayload {
        guard let info = info as? [String: Any] else {
            return .empty
        }

        return MediaPlaybackPayload(
            title: string(info, "kMRMediaRemoteNowPlayingInfoTitle"),
            artist: string(info, "kMRMediaRemoteNowPlayingInfoArtist"),
            album: string(info, "kMRMediaRemoteNowPlayingInfoAlbum"),
            isPlaying: isPlaying(info),
            currentTime: double(info, "kMRMediaRemoteNowPlayingInfoElapsedTime") ?? 0,
            duration: double(info, "kMRMediaRemoteNowPlayingInfoDuration") ?? 0,
            playbackRate: double(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? 0,
            isShuffled: (int(info, "kMRMediaRemoteNowPlayingInfoShuffleMode") ?? 1) != 1,
            repeatMode: MediaPlaybackRepeatMode(
                rawValue: int(info, "kMRMediaRemoteNowPlayingInfoRepeatMode") ?? MediaPlaybackRepeatMode.off.rawValue
            ) ?? .off,
            updatedAt: date(info, "kMRMediaRemoteNowPlayingInfoTimestamp") ?? Date(),
            artworkData: includeArtwork ? artworkData(info) : nil
        )
    }

    private static func string(_ info: [String: Any], _ key: String) -> String {
        info[key] as? String ?? ""
    }

    private static func isPlaying(_ info: [String: Any]) -> Bool {
        guard let playbackRate = double(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate") else {
            return false
        }
        return playbackRate > 0.01
    }

    private static func double(_ info: [String: Any], _ key: String) -> Double? {
        if let value = info[key] as? Double {
            return value
        }
        if let value = info[key] as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private static func int(_ info: [String: Any], _ key: String) -> Int? {
        if let value = info[key] as? Int {
            return value
        }
        if let value = info[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func date(_ info: [String: Any], _ key: String) -> Date? {
        if let date = info[key] as? Date {
            return date
        }
        if let number = info[key] as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: number.doubleValue)
        }
        return nil
    }

    private static func artworkData(_ info: [String: Any]) -> Data? {
        for key in ["kMRMediaRemoteNowPlayingInfoArtworkData", "artworkData"] {
            if let data = artworkData(info, key) {
                return data
            }
        }
        return nil
    }

    private static func artworkData(_ info: [String: Any], _ key: String) -> Data? {
        if let data = info[key] as? Data {
            return data
        }
        if let data = info[key] as? NSData {
            return data as Data
        }
        if let base64 = info[key] as? String {
            return Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let image = info[key] as? NSImage {
            return image.tiffRepresentation
        }
        return nil
    }
}

private final class MediaRemoteAdapterClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.atoll.media-remote-adapter", qos: .utility)

    func fetchPayload(completion: @escaping @Sendable (MediaPlaybackPayload?) -> Void) {
        queue.async {
            completion(Self.readPayload())
        }
    }

    func seek(to seconds: Double) {
        let micros = Int64(min(max(seconds, 0), Double(Int64.max) / 1_000_000) * 1_000_000)
        runCommand("seek", "\(micros)")
    }

    func setShuffle(enabled: Bool) {
        runCommand("shuffle", enabled ? "3" : "1")
    }

    func setRepeatMode(_ repeatMode: MediaPlaybackRepeatMode) {
        runCommand("repeat", "\(repeatMode.rawValue)")
    }

    private func runCommand(_ name: String, _ value: String) {
        queue.async {
            _ = Self.runAdapter(arguments: [name, value], timeout: 0.8)
        }
    }

    private static func readPayload(timeout: TimeInterval = 1.2) -> MediaPlaybackPayload? {
        guard let data = runAdapter(arguments: ["get"], timeout: timeout) else { return nil }
        guard data.isEmpty == false,
              let response = try? JSONDecoder().decode(MediaRemoteAdapterPayload.self, from: data) else {
            return nil
        }

        return response.resolvedPayload(mergingInto: .empty, isDiff: false)
    }

    private static func runAdapter(arguments: [String], timeout: TimeInterval) -> Data? {
        guard let scriptURL = MediaRemoteAdapterLocator.scriptURL(),
              let frameworkURL = MediaRemoteAdapterLocator.frameworkURL() else {
            return nil
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }

        return outputPipe.fileHandleForReading.readDataToEndOfFile()
    }
}

private final class MediaRemoteAdapterStreamClient: @unchecked Sendable {
    private let stateLock = NSLock()
    private let readQueue = DispatchQueue(label: "app.atoll.media-remote-adapter.stream", qos: .utility)
    private var process: Process?

    func start(onUpdate: @escaping @Sendable (MediaPlaybackPayload) -> Void) {
        stateLock.lock()
        if process != nil {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let scriptURL = MediaRemoteAdapterLocator.scriptURL(),
              let frameworkURL = MediaRemoteAdapterLocator.frameworkURL() else {
            return
        }

        let nextProcess = Process()
        let outputPipe = Pipe()
        nextProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        nextProcess.arguments = [scriptURL.path, frameworkURL.path, "stream", "--debounce=200"]
        nextProcess.standardOutput = outputPipe
        nextProcess.standardError = Pipe()

        do {
            try nextProcess.run()
        } catch {
            return
        }

        stateLock.lock()
        if process == nil {
            process = nextProcess
            stateLock.unlock()
        } else {
            stateLock.unlock()
            nextProcess.terminate()
            return
        }

        let handle = outputPipe.fileHandleForReading
        readQueue.async { [weak self] in
            self?.readStream(process: nextProcess, handle: handle, onUpdate: onUpdate)
        }
    }

    func stop() {
        stateLock.lock()
        let currentProcess = process
        process = nil
        stateLock.unlock()

        if currentProcess?.isRunning == true {
            currentProcess?.terminate()
        }
    }

    private func readStream(
        process: Process,
        handle: FileHandle,
        onUpdate: @escaping @Sendable (MediaPlaybackPayload) -> Void
    ) {
        var buffer = Data()
        var currentPayload = MediaPlaybackPayload.empty
        let newline = Data([0x0A])

        while process.isRunning {
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }

            buffer.append(chunk)
            while let range = buffer.range(of: newline) {
                let lineData = buffer[..<range.lowerBound]
                buffer.removeSubrange(..<range.upperBound)
                if let payload = Self.decodeStreamLine(lineData, currentPayload: &currentPayload) {
                    onUpdate(payload)
                }
            }
        }

        if !buffer.isEmpty,
           let payload = Self.decodeStreamLine(buffer, currentPayload: &currentPayload) {
            onUpdate(payload)
        }

        stateLock.lock()
        if self.process === process {
            self.process = nil
        }
        stateLock.unlock()
    }

    private static func decodeStreamLine(
        _ data: Data.SubSequence,
        currentPayload: inout MediaPlaybackPayload
    ) -> MediaPlaybackPayload? {
        let lineData = Data(data)
        guard lineData.isEmpty == false,
              String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) != "null" else {
            return nil
        }

        let decoder = JSONDecoder()
        if let update = try? decoder.decode(MediaRemoteAdapterStreamUpdate.self, from: lineData) {
            currentPayload = update.payload.resolvedPayload(
                mergingInto: currentPayload,
                isDiff: update.diff ?? false
            )
            return currentPayload
        }

        if let payload = try? decoder.decode(MediaRemoteAdapterPayload.self, from: lineData) {
            currentPayload = payload.resolvedPayload(mergingInto: .empty, isDiff: false)
            return currentPayload
        }

        return nil
    }
}

private enum MediaRemoteAdapterLocator {
    static func scriptURL() -> URL? {
        Bundle.appResources.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl",
            subdirectory: "MediaRemoteAdapter"
        ) ?? Bundle.appResources.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl"
        )
    }

    static func frameworkURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("ThirdParty/MediaRemoteAdapter/MediaRemoteAdapter.framework"),
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }
}

private struct MediaRemoteAdapterStreamUpdate: Decodable {
    var payload: MediaRemoteAdapterPayload
    var diff: Bool?
}

private struct MediaRemoteAdapterPayload: Decodable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsedTime: Double?
    var elapsedTimeNow: Double?
    var timestamp: String?
    var playing: Bool?
    var playbackRate: Double?
    var shuffleMode: Int?
    var repeatMode: Int?
    var artworkData: String?

    func resolvedPayload(
        mergingInto base: MediaPlaybackPayload,
        isDiff: Bool
    ) -> MediaPlaybackPayload {
        let fallback = isDiff ? base : .empty
        let resolvedPlaybackRate = playbackRate ?? fallback.playbackRate
        let resolvedTimestamp = parsedTimestamp ?? Date()
        return MediaPlaybackPayload(
            title: title ?? fallback.title,
            artist: artist ?? fallback.artist,
            album: album ?? fallback.album,
            isPlaying: playing ?? playbackRate.map { $0 > 0.01 } ?? fallback.isPlaying,
            currentTime: elapsedTimeNow ?? elapsedTime ?? fallback.currentTime,
            duration: duration ?? fallback.duration,
            playbackRate: resolvedPlaybackRate,
            isShuffled: shuffleMode.map { $0 != 1 } ?? fallback.isShuffled,
            repeatMode: repeatMode.flatMap(MediaPlaybackRepeatMode.init(rawValue:)) ?? fallback.repeatMode,
            updatedAt: elapsedTimeNow != nil ? Date() : (timestamp == nil && isDiff ? fallback.updatedAt : resolvedTimestamp),
            artworkData: decodedArtworkData ?? fallback.artworkData
        )
    }

    private var decodedArtworkData: Data? {
        artworkData.flatMap {
            Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var parsedTimestamp: Date? {
        guard let timestamp else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}

private final class MediaRemoteCommandSender: @unchecked Sendable {
    private let function: MediaRemoteSendCommandFunction

    init(_ function: @escaping MediaRemoteSendCommandFunction) {
        self.function = function
    }

    func send(_ command: MediaRemoteCommand) {
        function(command.rawValue, nil)
    }
}

private final class MediaRemoteBlockBox<Block>: @unchecked Sendable {
    let block: Block

    init(_ block: Block) {
        self.block = block
    }
}

private final class MediaRemoteFetchState: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var retainedBlocks: [Any] = []
    private let completion: (MediaPlaybackPayload) -> Void

    var finished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished
    }

    init(completion: @escaping (MediaPlaybackPayload) -> Void) {
        self.completion = completion
    }

    func retain(_ block: Any) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        retainedBlocks.append(block)
    }

    func finish(_ payload: MediaPlaybackPayload) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        retainedBlocks.removeAll()
        lock.unlock()
        completion(payload)
    }
}

private enum MediaKeySender {
    enum Key {
        case playPause
        case next
        case previous

        var nxKeyType: Int32 {
            switch self {
            case .playPause: NX_KEYTYPE_PLAY
            case .next: NX_KEYTYPE_FAST
            case .previous: NX_KEYTYPE_REWIND
            }
        }
    }

    static func post(_ key: Key) {
        post(key.nxKeyType, isDown: true)
        post(key.nxKeyType, isDown: false)
    }

    private static func post(_ keyCode: Int32, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = (keyCode << 16) | (Int32(keyState) << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(data1),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
