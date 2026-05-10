import Testing
@testable import AtollCore

struct StreamOverlayHTTPEndpointTests {
    @Test
    func overlayUsesStableLoopbackURL() {
        let endpoint = StreamOverlayHTTPEndpoint(port: 47_619)

        #expect(endpoint.overlayURLString == "http://127.0.0.1:47619/overlay")
        #expect(endpoint.statusURLString == "http://127.0.0.1:47619/status")
    }

    @Test
    func overlayHTMLPollsLocalStatusEndpoint() {
        let html = StreamOverlayHTTPEndpoint.overlayHTMLForTesting()

        #expect(html.contains("Atoll Live"))
        #expect(html.contains("fetch('/status'"))
        #expect(html.contains("escapeHTML"))
    }
}
