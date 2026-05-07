import SwiftUI
import AtollCore

/// One row in the theme editor sheet. Renders the role name, a swatch,
/// a monospaced hex TextField, and a system ColorPicker — all bound to
/// the same underlying `ProjectColor`. Typing a hex value updates the
/// picker; dragging the picker updates the hex. Invalid hex on commit
/// reverts silently to the last valid value (HIG silent-revert pattern).
struct ColorRoleRow: View {
    let roleName: LocalizedStringKey
    @Binding var color: ProjectColor

    @State private var hexDraft: String

    init(roleName: LocalizedStringKey, color: Binding<ProjectColor>) {
        self.roleName = roleName
        self._color = color
        self._hexDraft = State(initialValue: color.wrappedValue.toHex())
    }

    var body: some View {
        HStack(spacing: 12) {
            swatch
                .frame(width: 28, height: 28)

            Text(roleName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("hex", text: $hexDraft)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
                .onSubmit(commitHexDraft)

            ColorPicker("", selection: colorPickerBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(roleName), \(hexDraft)"))
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            )
    }

    /// Bridges the system ColorPicker (SwiftUI `Color`) to `ProjectColor`.
    /// Uses `NSColor` for reliable sRGB component extraction on macOS.
    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: { color.swiftUIColor },
            set: { newColor in
                guard let ns = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                color = ProjectColor(
                    red: Double(ns.redComponent),
                    green: Double(ns.greenComponent),
                    blue: Double(ns.blueComponent)
                )
                hexDraft = color.toHex()
            }
        )
    }

    private func commitHexDraft() {
        if ThemePalette.isValidHex(hexDraft) {
            color = ProjectColor.fromHex(hexDraft)
            hexDraft = color.toHex()   // normalize to lowercase, no '#'
        } else {
            hexDraft = color.toHex()   // revert to last valid value
        }
    }
}
