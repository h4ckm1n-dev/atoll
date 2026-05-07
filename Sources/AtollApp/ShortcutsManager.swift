import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let jumpToFocusedSession = Self("jumpToFocusedSession")
    static let approveFocusedPermission = Self("approveFocusedPermission")
    static let denyFocusedPermission = Self("denyFocusedPermission")
    static let cycleToNextAttentionSession = Self("cycleToNextAttentionSession")
}

@MainActor
final class ShortcutsManager {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [model] in
            model.toggleOverlay()
        }
        KeyboardShortcuts.onKeyDown(for: .jumpToFocusedSession) { [model] in
            model.jumpToFocusedSession()
        }
        KeyboardShortcuts.onKeyDown(for: .approveFocusedPermission) { [model] in
            model.approveFocusedPermission(true)
        }
        KeyboardShortcuts.onKeyDown(for: .denyFocusedPermission) { [model] in
            model.approveFocusedPermission(false)
        }
        KeyboardShortcuts.onKeyDown(for: .cycleToNextAttentionSession) { [model] in
            model.cycleToNextAttentionSession()
        }
    }
}
