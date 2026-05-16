import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let jumpToFocusedSession = Self("jumpToFocusedSession")
    static let approveFocusedPermission = Self("approveFocusedPermission")
    static let denyFocusedPermission = Self("denyFocusedPermission")
    static let cycleToNextAttentionSession = Self("cycleToNextAttentionSession")
    static let toggleDictation = Self("toggleDictation")
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
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [model] in
            let dc = model.dictationController
            Task { @MainActor in
                switch dc.state {
                case .idle:
                    try? await dc.startRecording()
                case .failed, .completed:
                    dc.reset()
                    try? await dc.startRecording()
                case .recording:
                    if let transcription = try? await dc.stopAndTranscribe() {
                        model.routeDictationTranscript(transcription)
                    }
                case .preparing, .transcribing:
                    // Hotkey is a no-op while a transition is already in flight.
                    break
                }
            }
        }
    }
}
