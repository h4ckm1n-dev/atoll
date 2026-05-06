import SwiftUI
import OpenIslandCore

/// Renders a session's plan as an indented list of steps. When `interactive`
/// is true, each row is a tappable checkbox that toggles via `onToggle`. In
/// read-only mode (pre-approval review), checkboxes are displayed as static
/// circles so the user can scan the structure without committing.
struct PlanChecklistView: View {
    let state: PlanState
    let interactive: Bool
    let onToggle: ((String) -> Void)?

    @Environment(\.themePalette) private var palette

    private static let baseIndent: CGFloat = 12

    init(state: PlanState, interactive: Bool, onToggle: ((String) -> Void)? = nil) {
        self.state = state
        self.interactive = interactive
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(state.steps) { step in
                row(for: step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for step: PlanStep) -> some View {
        let checked = state.checkedIDs.contains(step.id)
        return HStack(alignment: .top, spacing: 8) {
            checkbox(checked: checked)
            Text(step.title)
                .font(.system(size: 12, weight: checked ? .regular : .medium))
                .foregroundStyle(checked ? palette.text.swiftUIColor.opacity(0.5) : palette.text.swiftUIColor.opacity(0.92))
                .strikethrough(checked, color: palette.text.swiftUIColor.opacity(0.4))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(step.depth) * Self.baseIndent)
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            onToggle?(step.id)
        }
    }

    private func checkbox(checked: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(checked ? palette.role(.success).swiftUIColor.opacity(0.85) : palette.text.swiftUIColor.opacity(0.35), lineWidth: 1.5)
                .frame(width: 12, height: 12)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.role(.success).swiftUIColor.opacity(0.95))
            }
        }
        .padding(.top, 2)
    }
}
