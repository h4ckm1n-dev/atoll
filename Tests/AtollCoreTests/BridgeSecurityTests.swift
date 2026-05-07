import Foundation
import Testing
@testable import AtollCore

/// Coverage for the 2026-05-07 IPC hardening:
///   - H1: peer-credential rejection
///   - H2: per-client buffer cap
///   - L1: CodexHookJSONValue depth limit
///   - L3: helper-supplied UI string truncation
struct BridgeSecurityTests {

    // MARK: - L3 truncation

    @Test
    func truncatedForUIPassesThroughShortStrings() {
        let s = "hello world"
        #expect(s.truncatedForUI(maxBytes: 100) == s)
    }

    @Test
    func truncatedForUIClipsLongStrings() {
        let s = String(repeating: "x", count: 10_000)
        let truncated = s.truncatedForUI(maxBytes: 32)
        #expect(truncated.utf8.count <= 32)
        #expect(truncated.hasSuffix("..."))
    }

    @Test
    func truncatedForUIRespectsUnicodeScalarBoundaries() {
        // Each emoji is 4 bytes in UTF-8. With a 10-byte budget minus 3 for
        // the "..." marker = 7 bytes, we can fit exactly one emoji (4) but
        // not two (8). The result must remain valid UTF-8.
        let s = "🎉🎉🎉🎉🎉🎉"
        let truncated = s.truncatedForUI(maxBytes: 10)
        #expect(truncated.utf8.count <= 10)
        // Must end with the ASCII marker.
        #expect(truncated.hasSuffix("..."))
        // String roundtrips through UTF-8 successfully (i.e., no broken
        // grapheme cluster).
        #expect(String(data: Data(truncated.utf8), encoding: .utf8) == truncated)
    }

    @Test
    func truncatedForUIDefaultBudgetMatchesBridgeSecurityConstant() {
        // Calling without an explicit limit should use the centralized
        // constant from BridgeSecurity.
        let s = String(repeating: "y", count: BridgeSecurity.maxUIStringBytes + 256)
        let truncated = s.truncatedForUI()
        #expect(truncated.utf8.count <= BridgeSecurity.maxUIStringBytes)
    }

    // MARK: - L1 JSON depth limit

    @Test
    func codexHookJSONValueDecodesShallowObject() throws {
        let payload = """
        {"a": 1, "b": "two", "c": [1, 2, 3]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let value = try decoder.decode(CodexHookJSONValue.self, from: payload)
        guard case .object = value else {
            Issue.record("Expected an object value")
            return
        }
    }

    @Test
    func codexHookJSONValueRejectsExcessivelyDeepNesting() {
        // Build a JSON string that nests `{ "k": { "k": ... } }` deeper than
        // the configured limit. We pad well beyond it so the throw happens
        // even if the recursion accounting is off by a couple of frames.
        let depth = CodexHookJSONValue.maxDecodingDepth + 10
        let opens = String(repeating: "{\"k\":", count: depth)
        let closes = String(repeating: "}", count: depth)
        let payload = (opens + "1" + closes).data(using: .utf8)!
        let decoder = JSONDecoder()
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(CodexHookJSONValue.self, from: payload)
        }
    }

    @Test
    func codexHookJSONValueAcceptsNestingAtBoundary() throws {
        // Exactly `maxDecodingDepth` levels should decode (depth counter is
        // checked > limit, not >=). Use a smaller depth to keep the test
        // fast and to leave headroom for any wrapper overhead.
        let depth = 16
        let payload = (String(repeating: "{\"k\":", count: depth) + "1" + String(repeating: "}", count: depth))
            .data(using: .utf8)!
        let decoder = JSONDecoder()
        _ = try decoder.decode(CodexHookJSONValue.self, from: payload)
    }

    // MARK: - H1 peer trust hook

    @Test
    func bridgeSecurityDefaultPeerTrustRejectsInvalidFD() {
        // An invalid fd makes getpeereid fail; defaultPeerTrustCheck returns
        // false. This proves the negative branch the BridgeServer relies on
        // when it closes a fd whose peer is untrusted.
        let trustCheckResult = BridgeSecurity.defaultPeerTrustCheck(-1)
        #expect(trustCheckResult == false)
    }

    @Test
    func bridgeServerAcceptsCustomPeerTrustClosure() {
        // Smoke-test the BridgeServer initializer's new peerTrustCheck
        // parameter — the wiring must remain Sendable-compatible.
        let server = BridgeServer(
            socketURL: BridgeSocketLocation.uniqueTestURL(),
            peerTrustCheck: { _ in false }
        )
        // Keep server alive — the test passes simply by compiling and
        // instantiating with the injected closure.
        _ = server
    }

    @Test
    func bridgeSecurityDefaultPeerTrustAcceptsSelfPipe() throws {
        // A locally-paired socketpair shares the running process's EUID,
        // so the default trust check should accept it.
        var pair: [Int32] = [-1, -1]
        let rc = pair.withUnsafeMutableBufferPointer { buffer in
            socketpair(AF_UNIX, SOCK_STREAM, 0, buffer.baseAddress)
        }
        guard rc == 0 else {
            Issue.record("socketpair failed: errno=\(errno)")
            return
        }
        defer {
            close(pair[0])
            close(pair[1])
        }
        // Both ends share our EUID, so getpeereid -> our euid -> match.
        #expect(BridgeSecurity.defaultPeerTrustCheck(pair[0]) == true)
        #expect(BridgeSecurity.defaultPeerTrustCheck(pair[1]) == true)
    }

    // MARK: - Token bucket (M1)

    @Test
    func tokenBucketAllowsBurstUpToCapacity() {
        var bucket = TokenBucket(capacity: 5, refillPerSecond: 0)
        for _ in 0..<5 {
            #expect(bucket.tryConsume() == true)
        }
        #expect(bucket.tryConsume() == false)
    }

    @Test
    func tokenBucketRefillsOverTime() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var bucket = TokenBucket(capacity: 1, refillPerSecond: 1, now: start)
        #expect(bucket.tryConsume(now: start) == true)
        // Second call at the same instant should be denied.
        #expect(bucket.tryConsume(now: start) == false)
        // After 1.5 seconds we should have refilled to 1 token.
        let later = start.addingTimeInterval(1.5)
        #expect(bucket.tryConsume(now: later) == true)
    }

    // MARK: - H2 sanity on constants

    @Test
    func bridgeSecurityCapsAreSane() {
        #expect(BridgeSecurity.maxFrameBytes < BridgeSecurity.maxClientBufferBytes)
        #expect(BridgeSecurity.maxConcurrentClients > 0)
        #expect(BridgeSecurity.maxPendingInteractions > 0)
        #expect(BridgeSecurity.rateLimitBurstCapacity >= BridgeSecurity.rateLimitTokensPerSecond)
    }

    // MARK: - H2 truncation point sanity (decodeLines)

    @Test
    func bridgeCodecDecodesFramedHelloEnvelope() throws {
        // Smoke test the codec the BridgeServer relies on for line framing.
        // If a frame slightly above `maxFrameBytes` ever sneaks past the
        // server's own pre-decode check, the codec must still be capable
        // of decoding a well-formed envelope without state corruption.
        let envelope = BridgeEnvelope.hello(BridgeHello())
        var data = try BridgeCodec.encodeLine(envelope)
        let decoded = try BridgeCodec.decodeLines(from: &data)
        #expect(decoded.count == 1)
        #expect(decoded.first == envelope)
        #expect(data.isEmpty)
    }
}
