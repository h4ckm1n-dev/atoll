import AppKit
import Darwin
import Foundation
import IOKit

struct MediaPlaybackSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var artwork: NSImage?

    static let empty = MediaPlaybackSnapshot(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        artwork: nil
    )

    init(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        artwork: NSImage?
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.artwork = artwork
    }

    fileprivate init(payload: MediaPlaybackPayload, includeArtwork: Bool) {
        title = payload.title
        artist = payload.artist
        album = payload.album
        isPlaying = payload.isPlaying
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

    var subtitle: String {
        [artist, album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}

private struct MediaPlaybackPayload: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var artworkData: Data?

    static let empty = MediaPlaybackPayload(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        artworkData: nil
    )
}

private enum MediaRemoteCommand: Int {
    case playPause = 2
    case next = 4
    case previous = 5
}

private typealias MediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Void

@MainActor
@Observable
final class MediaPlaybackController {
    @ObservationIgnored
    private lazy var client = MediaRemoteNowPlayingClient()
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
    }

    func stop() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        snapshot = .empty
    }

    func setArtworkEnabled(_ enabled: Bool) {
        guard artworkEnabled != enabled else { return }
        artworkEnabled = enabled
        if !enabled, snapshot.artwork != nil {
            snapshot.artwork = nil
        }
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
                let nextSnapshot = MediaPlaybackSnapshot(
                    payload: payload,
                    includeArtwork: includeArtwork && self.artworkEnabled
                )
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

    private func scheduleQuickRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.refresh(generation: self?.refreshGeneration ?? 0, force: true)
        }
    }
}

private final class MediaRemoteNowPlayingClient: @unchecked Sendable {
    typealias NowPlayingInfoCompletion = @convention(block) (CFDictionary?) -> Void
    typealias IsPlayingCompletion = @convention(block) (Bool) -> Void
    typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, NowPlayingInfoCompletion) -> Void
    typealias GetIsPlaying = @convention(c) (DispatchQueue, IsPlayingCompletion) -> Void

    private let queue = DispatchQueue(label: "app.atoll.media-remote", qos: .utility)
    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetNowPlayingInfo?
    private let getIsPlaying: GetIsPlaying?
    private let commandSender: MediaRemoteCommandSender?

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

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") }) {
            getIsPlaying = unsafeBitCast(symbol, to: GetIsPlaying.self)
        } else {
            getIsPlaying = nil
        }

        if let symbol = handle.flatMap({ dlsym($0, "MRMediaRemoteSendCommand") }) {
            let function = unsafeBitCast(symbol, to: MediaRemoteSendCommandFunction.self)
            commandSender = MediaRemoteCommandSender(function)
        } else {
            commandSender = nil
        }
    }

    func sendCommand(_ command: MediaRemoteCommand) -> Bool {
        guard let commandSender else { return false }
        queue.async {
            commandSender.send(command)
        }
        return true
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
        let getIsPlaying = getIsPlaying
        let state = MediaRemoteFetchState(completion: completion)

        queue.asyncAfter(deadline: .now() + timeout) {
            state.finish(.empty)
        }

        let nowPlayingCompletion: NowPlayingInfoCompletion = { info in
            guard !state.finished else { return }
            let partial = Self.payload(from: info, isPlaying: false, includeArtwork: includeArtwork)
            guard let getIsPlaying else {
                state.finish(partial)
                return
            }

            let isPlayingCompletion: IsPlayingCompletion = { isPlaying in
                var payload = partial
                payload.isPlaying = isPlaying
                state.finish(payload)
            }
            let isPlayingBlock = MediaRemoteBlockBox(isPlayingCompletion)
            state.retain(isPlayingBlock)
            getIsPlaying(queue, isPlayingBlock.block)
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
        isPlaying: Bool,
        includeArtwork: Bool
    ) -> MediaPlaybackPayload {
        guard let info = info as? [String: Any] else {
            return .empty
        }

        return MediaPlaybackPayload(
            title: string(info, "kMRMediaRemoteNowPlayingInfoTitle"),
            artist: string(info, "kMRMediaRemoteNowPlayingInfoArtist"),
            album: string(info, "kMRMediaRemoteNowPlayingInfoAlbum"),
            isPlaying: isPlaying,
            artworkData: includeArtwork ? artworkData(info) : nil
        )
    }

    private static func string(_ info: [String: Any], _ key: String) -> String {
        info[key] as? String ?? ""
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
