import SwiftUI
import OpenIslandCore

/// Renders a `ToolDiff` as a unified-style diff with red/green tinted
/// rows and lightweight syntax highlighting. Used in the approval card to
/// preview what's about to happen before the user clicks Yes/No, so they
/// can decide without switching back to the terminal.
struct InlineDiffView: View {
    let diff: ToolDiff
    let palette: ThemePalette

    init(diff: ToolDiff, palette: ThemePalette = .mocha) {
        self.diff = diff
        self.palette = palette
    }

    private static let maxBodyHeight: CGFloat = 240
    private static let rowVerticalPadding: CGFloat = 1
    private static let rowHorizontalPadding: CGFloat = 6
    private static let prefixWidth: CGFloat = 12

    private var language: LightweightSyntaxHighlighter.Language? {
        LightweightSyntaxHighlighter.language(forFilePath: diff.filePath)
    }

    private var tokenColors: LightweightSyntaxHighlighter.TokenColors {
        LightweightSyntaxHighlighter.TokenColors.from(palette: palette)
    }

    private var truncationMessage: String {
        if diff.filePath == "(multi-file patch)" {
            return "Multi-file patch detected. Open the terminal to review each affected file before approving — preview hidden to prevent filename spoofing."
        }
        return "Diff too large to preview (\(diff.additionCount) lines). Click Yes to apply, or open the file to review."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if diff.truncated {
                Text(truncationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.subtext0.swiftUIColor)
                    .padding(.horizontal, Self.rowHorizontalPadding)
            } else if diff.lines.isEmpty {
                Text("(empty)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.overlay0.swiftUIColor)
                    .padding(.horizontal, Self.rowHorizontalPadding)
            } else {
                AutoHeightScrollView(maxHeight: Self.maxBodyHeight) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                            row(for: line)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.crust.swiftUIColor.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.surface0.swiftUIColor.opacity(0.55))
        )
    }

    private var header: some View {
        let pathRisk = PathRiskClassifier.classify(diff.filePath, palette: palette)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: pathRisk.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(pathRisk.iconColor)
                Text(diff.filePath)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.text.swiftUIColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                if diff.additionCount > 0 {
                    stat(symbol: "+", count: diff.additionCount, tint: palette.green.swiftUIColor)
                }
                if diff.removalCount > 0 {
                    stat(symbol: "−", count: diff.removalCount, tint: palette.red.swiftUIColor)
                }
            }

            if let warning = pathRisk.warningMessage {
                Text(warning)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.yellow.swiftUIColor)
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.top, 6)
    }

    private func stat(symbol: String, count: Int, tint: Color) -> some View {
        Text("\(symbol)\(count)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
    }

    private func row(for line: DiffLine) -> some View {
        let sanitized = DiffTextSanitizer.sanitize(line.text)
        return HStack(alignment: .top, spacing: 0) {
            Text(prefix(for: line))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(prefixColor(for: line))
                .frame(width: Self.prefixWidth, alignment: .leading)

            Text(LightweightSyntaxHighlighter.attribute(sanitized.text, language: language, colors: tokenColors))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if sanitized.hadHiddenCharacters {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.yellow.swiftUIColor)
                    .help("This line contains hidden Unicode characters that have been replaced with visible placeholders. Review carefully before approving.")
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .background(rowBackground(for: line))
    }

    private func prefix(for line: DiffLine) -> String {
        switch line {
        case .add:     return "+"
        case .remove:  return "−"
        case .context: return " "
        }
    }

    private func prefixColor(for line: DiffLine) -> Color {
        switch line {
        case .add:     return palette.green.swiftUIColor
        case .remove:  return palette.red.swiftUIColor
        case .context: return palette.overlay0.swiftUIColor
        }
    }

    private func rowBackground(for line: DiffLine) -> Color {
        switch line {
        case .add:     return palette.green.swiftUIColor.opacity(0.18)
        case .remove:  return palette.red.swiftUIColor.opacity(0.20)
        case .context: return .clear
        }
    }

}

/// Classifies a `file_path` from a tool input into a risk band so the
/// approval card can call out paths that traverse outside the user's
/// home directory or contain `..` segments. Backstops the F1 hardening
/// (full path display) by warning the user when the displayed path
/// touches sensitive locations even if the rendering itself can't be
/// spoofed.
enum PathRiskClassifier {
    struct Risk {
        var iconName: String
        var iconColor: Color
        var warningMessage: String?
    }

    static func benign(palette: ThemePalette) -> Risk {
        Risk(
            iconName: "doc.text.fill",
            iconColor: palette.overlay1.swiftUIColor,
            warningMessage: nil
        )
    }

    static func classify(_ path: String, palette: ThemePalette) -> Risk {
        if path.isEmpty || path == "(patch)" {
            return benign(palette: palette)
        }
        if containsDotDotTraversal(path) {
            return Risk(
                iconName: "exclamationmark.triangle.fill",
                iconColor: palette.yellow.swiftUIColor,
                warningMessage: "Path contains '..' traversal — verify the resolved target before approving."
            )
        }
        if path.hasPrefix("/") && !isUnderUserHome(path) {
            return Risk(
                iconName: "exclamationmark.triangle.fill",
                iconColor: palette.yellow.swiftUIColor,
                warningMessage: "Writes outside your home directory — uncommon for project edits."
            )
        }
        return benign(palette: palette)
    }

    private static func containsDotDotTraversal(_ path: String) -> Bool {
        path.split(separator: "/").contains(where: { $0 == ".." })
    }

    private static func isUnderUserHome(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/")
    }
}
