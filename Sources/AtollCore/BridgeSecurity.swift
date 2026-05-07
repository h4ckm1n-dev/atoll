import Darwin
import Foundation

/// Hardening constants and helpers for the local IPC bridge.
///
/// Security goals (see 2026-05-07 audit):
///   - H1 socket trust boundary (peer credential check, file-mode lockdown)
///   - H2 per-client buffer cap + concurrent-client cap (DoS resistance)
///   - M1 per-client rate limit + bounded pending-state maps
///   - L3 length-bounded helper-supplied UI strings
public enum BridgeSecurity {
    /// Maximum bytes accumulated per client before we drop the connection.
    /// 1 MiB is comfortably above any legitimate hook payload (Claude/Codex
    /// payloads are typically <16 KiB, large diff payloads <256 KiB).
    public static let maxClientBufferBytes: Int = 1 * 1024 * 1024

    /// Maximum bytes allowed for a single newline-delimited frame.
    public static let maxFrameBytes: Int = 256 * 1024

    /// Maximum number of concurrent client connections we will service.
    /// Past this cap, accept() returns the fd which we close immediately.
    public static let maxConcurrentClients: Int = 32

    /// Token-bucket sustained rate (events/sec) per client.
    public static let rateLimitTokensPerSecond: Double = 100

    /// Token-bucket burst capacity per client.
    public static let rateLimitBurstCapacity: Double = 200

    /// Bound for `pendingApprovals`, `pendingClaudeInteractions`, and
    /// related state maps. Above this, the oldest entry is evicted on
    /// insert to keep memory finite under flooding.
    public static let maxPendingInteractions: Int = 256

    /// Maximum byte length applied to any helper-supplied UI string before
    /// it is stored in `SessionState`/UI labels.
    public static let maxUIStringBytes: Int = 4096

    /// Returns the effective UID of the peer connected to `fd`, or `nil`
    /// when the kernel cannot determine it.
    public static func peerEUID(of fileDescriptor: Int32) -> uid_t? {
        var euid: uid_t = 0
        var egid: gid_t = 0
        guard getpeereid(fileDescriptor, &euid, &egid) == 0 else {
            return nil
        }
        return euid
    }

    /// Default trust check: accept only peers whose effective UID matches
    /// the running server process. Rejects forwarded (e.g. SSH-tunnelled)
    /// connections that arrive at the socket as a different user.
    public static func defaultPeerTrustCheck(_ fileDescriptor: Int32) -> Bool {
        guard let euid = peerEUID(of: fileDescriptor) else {
            return false
        }
        return euid == geteuid()
    }
}

extension String {
    /// Truncates this string so its UTF-8 representation fits within
    /// `maxBytes`. Appends an ASCII ellipsis marker when truncation occurs
    /// so downstream UI signals that the value was clipped. Truncation
    /// respects Unicode scalar boundaries to avoid producing invalid UTF-8.
    public func truncatedForUI(maxBytes: Int = BridgeSecurity.maxUIStringBytes) -> String {
        let utf8Count = self.utf8.count
        guard utf8Count > maxBytes else {
            return self
        }

        // Reserve room for the marker (3 bytes for "...").
        let marker = "..."
        let markerBytes = marker.utf8.count
        let budget = max(0, maxBytes - markerBytes)

        // Walk Character by Character and accumulate while we still fit.
        // Characters are unicode-scalar grapheme clusters, so this never
        // splits an emoji/grapheme.
        var result = String()
        result.reserveCapacity(budget)
        var bytesUsed = 0
        for character in self {
            let charBytes = String(character).utf8.count
            if bytesUsed + charBytes > budget {
                break
            }
            result.append(character)
            bytesUsed += charBytes
        }
        result.append(marker)
        return result
    }
}

/// Per-client token bucket used to drop hostile / runaway hook traffic
/// without killing the connection. See M1 in 2026-05-07 audit.
struct TokenBucket {
    private(set) var tokens: Double
    let capacity: Double
    let refillPerSecond: Double
    private var lastRefill: Date

    init(
        capacity: Double = BridgeSecurity.rateLimitBurstCapacity,
        refillPerSecond: Double = BridgeSecurity.rateLimitTokensPerSecond,
        now: Date = Date()
    ) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.lastRefill = now
    }

    /// Attempts to consume one token. Refills based on elapsed time first.
    /// Returns `true` if a token was available (frame allowed), `false`
    /// when the caller should drop the frame.
    mutating func tryConsume(now: Date = Date()) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(lastRefill))
        if elapsed > 0 {
            tokens = min(capacity, tokens + elapsed * refillPerSecond)
            lastRefill = now
        }
        guard tokens >= 1 else {
            return false
        }
        tokens -= 1
        return true
    }
}
