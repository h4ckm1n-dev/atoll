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

@MainActor
@Observable
final class MediaPlaybackController {
    private let client = MediaRemoteNowPlayingClient()
    private var refreshTask: Task<Void, Never>?

    private(set) var snapshot: MediaPlaybackSnapshot = .empty

    var isAvailable: Bool {
        client.isAvailable
    }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        snapshot = .empty
    }

    func refresh() {
        client.fetchSnapshot { [weak self] snapshot in
            self?.snapshot = snapshot
        }
    }

    func togglePlayPause() {
        MediaKeySender.post(.playPause)
        scheduleQuickRefresh()
    }

    func nextTrack() {
        MediaKeySender.post(.next)
        scheduleQuickRefresh()
    }

    func previousTrack() {
        MediaKeySender.post(.previous)
        scheduleQuickRefresh()
    }

    private func scheduleQuickRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.refresh()
        }
    }
}

@MainActor
private final class MediaRemoteNowPlayingClient {
    typealias NowPlayingInfoCompletion = @convention(block) (CFDictionary?) -> Void
    typealias IsPlayingCompletion = @convention(block) (Bool) -> Void
    typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, NowPlayingInfoCompletion) -> Void
    typealias GetIsPlaying = @convention(c) (DispatchQueue, IsPlayingCompletion) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetNowPlayingInfo?
    private let getIsPlaying: GetIsPlaying?

    var isAvailable: Bool {
        getNowPlayingInfo != nil
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
    }

    func fetchSnapshot(completion: @escaping (MediaPlaybackSnapshot) -> Void) {
        guard let getNowPlayingInfo else {
            completion(.empty)
            return
        }

        getNowPlayingInfo(.main) { [weak self] info in
            guard let self else {
                completion(.empty)
                return
            }

            let partial = Self.snapshot(from: info, isPlaying: false)
            guard let getIsPlaying else {
                completion(partial)
                return
            }

            getIsPlaying(.main) { isPlaying in
                var snapshot = partial
                snapshot.isPlaying = isPlaying
                completion(snapshot)
            }
        }
    }

    private static func snapshot(from info: CFDictionary?, isPlaying: Bool) -> MediaPlaybackSnapshot {
        guard let info = info as? [String: Any] else {
            return .empty
        }

        return MediaPlaybackSnapshot(
            title: string(info, "kMRMediaRemoteNowPlayingInfoTitle"),
            artist: string(info, "kMRMediaRemoteNowPlayingInfoArtist"),
            album: string(info, "kMRMediaRemoteNowPlayingInfoAlbum"),
            isPlaying: isPlaying,
            artwork: artwork(info, "kMRMediaRemoteNowPlayingInfoArtworkData")
        )
    }

    private static func string(_ info: [String: Any], _ key: String) -> String {
        info[key] as? String ?? ""
    }

    private static func artwork(_ info: [String: Any], _ key: String) -> NSImage? {
        guard let data = info[key] as? Data else {
            return nil
        }
        return NSImage(data: data)
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
