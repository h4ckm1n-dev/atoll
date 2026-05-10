import Foundation
import Testing
@testable import AtollCore

struct AutomationDeepLinkTests {
    @Test
    func parsesCanonicalActionURL() throws {
        let url = try #require(URL(string: "atoll://action/toggle-overlay"))

        #expect(AutomationDeepLink.action(from: url) == .toggleOverlay)
    }

    @Test
    func parsesHostOnlyShortcutURL() throws {
        let url = try #require(URL(string: "atoll://jump-focused-session"))

        #expect(AutomationDeepLink.action(from: url) == .jumpFocusedSession)
    }

    @Test
    func acceptsOpenIslandSchemeAlias() throws {
        let url = try #require(URL(string: "openisland://action/cycle-attention"))

        #expect(AutomationDeepLink.action(from: url) == .cycleAttentionSession)
    }

    @Test
    func normalizesCommonAliases() {
        #expect(AutomationDeepLink.action(named: "next-pending") == .cycleAttentionSession)
        #expect(AutomationDeepLink.action(named: "stream-safe") == .toggleLiveCoding)
        #expect(AutomationDeepLink.action(named: "overlay-url") == .copyStreamOverlayURL)
    }

    @Test
    func rejectsUnknownSchemeOrAction() throws {
        let wrongScheme = try #require(URL(string: "https://action/toggle-overlay"))
        let wrongAction = try #require(URL(string: "atoll://action/nope"))

        #expect(AutomationDeepLink.action(from: wrongScheme) == nil)
        #expect(AutomationDeepLink.action(from: wrongAction) == nil)
    }

    @Test
    func canonicalURLStringsRoundTripAllActions() throws {
        for action in AutomationAction.allCases {
            let urlString = AutomationDeepLink.urlString(for: action)
            let url = try #require(URL(string: urlString))

            #expect(AutomationDeepLink.action(from: url) == action)
        }
    }
}
