import Foundation

public enum AutomationAction: String, Codable, CaseIterable, Sendable {
    case toggleOverlay
    case showOverlay
    case hideOverlay
    case jumpFocusedSession
    case approveFocusedPermission
    case denyFocusedPermission
    case cycleAttentionSession
    case showSettings
    case showControlCenter
    case toggleLiveCoding
    case startStreamOverlay
    case stopStreamOverlay
    case copyStreamOverlayURL
}

public enum AutomationDeepLink {
    public static let supportedSchemes: Set<String> = ["atoll", "openisland", "open-island"]

    public static func action(from url: URL) -> AutomationAction? {
        guard let scheme = url.scheme?.lowercased(),
              supportedSchemes.contains(scheme) else {
            return nil
        }

        let pathParts = url.path
            .split(separator: "/")
            .map(String.init)
        let rawParts = ([url.host].compactMap { $0 } + pathParts)
            .compactMap { $0.removingPercentEncoding }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parts = rawParts.first?.caseInsensitiveCompare("action") == .orderedSame
            ? Array(rawParts.dropFirst())
            : rawParts

        guard let token = parts.first else {
            return nil
        }

        return action(named: token)
    }

    public static func action(named rawName: String) -> AutomationAction? {
        switch normalized(rawName) {
        case "toggleoverlay", "toggleisland":
            return .toggleOverlay
        case "showoverlay", "showisland", "openoverlay", "openisland":
            return .showOverlay
        case "hideoverlay", "hideisland", "closeoverlay", "closeisland":
            return .hideOverlay
        case "jumpfocusedsession", "jumpfocused", "jump":
            return .jumpFocusedSession
        case "approvefocusedpermission", "approvefocused", "approve", "allow":
            return .approveFocusedPermission
        case "denyfocusedpermission", "denyfocused", "deny":
            return .denyFocusedPermission
        case "cycleattentionsession", "cycleattention", "nextattention", "nextpending":
            return .cycleAttentionSession
        case "showsettings", "settings":
            return .showSettings
        case "showcontrolcenter", "controlcenter", "cockpit":
            return .showControlCenter
        case "togglelivecoding", "livecoding", "streamsafe":
            return .toggleLiveCoding
        case "startstreamoverlay", "showstreamoverlay", "streamoverlayon":
            return .startStreamOverlay
        case "stopstreamoverlay", "hidestreamoverlay", "streamoverlayoff":
            return .stopStreamOverlay
        case "copystreamoverlayurl", "copyoverlayurl", "overlayurl":
            return .copyStreamOverlayURL
        default:
            return nil
        }
    }

    public static func urlString(for action: AutomationAction, scheme: String = "atoll") -> String {
        "\(scheme)://action/\(slug(for: action))"
    }

    public static func slug(for action: AutomationAction) -> String {
        switch action {
        case .toggleOverlay:
            return "toggle-overlay"
        case .showOverlay:
            return "show-overlay"
        case .hideOverlay:
            return "hide-overlay"
        case .jumpFocusedSession:
            return "jump-focused-session"
        case .approveFocusedPermission:
            return "approve-focused-permission"
        case .denyFocusedPermission:
            return "deny-focused-permission"
        case .cycleAttentionSession:
            return "cycle-attention-session"
        case .showSettings:
            return "show-settings"
        case .showControlCenter:
            return "show-control-center"
        case .toggleLiveCoding:
            return "toggle-live-coding"
        case .startStreamOverlay:
            return "start-stream-overlay"
        case .stopStreamOverlay:
            return "stop-stream-overlay"
        case .copyStreamOverlayURL:
            return "copy-stream-overlay-url"
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
