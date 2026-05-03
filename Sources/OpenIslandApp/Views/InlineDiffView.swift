import SwiftUI
import OpenIslandCore

/// Renders a `ToolDiff` as a unified-style diff with red/green tinted
/// rows and lightweight syntax highlighting. Used in the approval card to
/// preview what's about to happen before the user clicks Yes/No, so they
/// can decide without switching back to the terminal.
struct InlineDiffView: View {
    let diff: ToolDiff

    private static let maxBodyHeight: CGFloat = 240
    private static let rowVerticalPadding: CGFloat = 1
    private static let rowHorizontalPadding: CGFloat = 6
    private static let prefixWidth: CGFloat = 12

    private var language: LightweightSyntaxHighlighter.Language? {
        LightweightSyntaxHighlighter.language(forFilePath: diff.filePath)
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
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, Self.rowHorizontalPadding)
            } else if diff.lines.isEmpty {
                Text("(empty)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
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
                .fill(Color.black.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
    }

    private var header: some View {
        let pathRisk = PathRiskClassifier.classify(diff.filePath)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: pathRisk.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(pathRisk.iconColor)
                // Render the full path with middle truncation by AppKit.
                // Pre-truncating to the last two components hid traversal
                // targets like /Users/x/.ssh/authorized_keys behind a
                // benign-looking ".ssh/authorized_keys" tail.
                Text(diff.filePath)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                if diff.additionCount > 0 {
                    stat(symbol: "+", count: diff.additionCount, tint: Color(red: 0.45, green: 0.85, blue: 0.55))
                }
                if diff.removalCount > 0 {
                    stat(symbol: "−", count: diff.removalCount, tint: Color(red: 0.94, green: 0.46, blue: 0.46))
                }
            }

            if let warning = pathRisk.warningMessage {
                Text(warning)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.yellow.opacity(0.92))
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

            Text(LightweightSyntaxHighlighter.attribute(sanitized.text, language: language))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if sanitized.hadHiddenCharacters {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.yellow.opacity(0.9))
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
        case .add:     return Color(red: 0.45, green: 0.85, blue: 0.55)
        case .remove:  return Color(red: 0.94, green: 0.46, blue: 0.46)
        case .context: return .white.opacity(0.35)
        }
    }

    private func rowBackground(for line: DiffLine) -> Color {
        switch line {
        case .add:     return Color(red: 0.12, green: 0.30, blue: 0.16).opacity(0.55)
        case .remove:  return Color(red: 0.32, green: 0.13, blue: 0.13).opacity(0.55)
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

    static let benign = Risk(
        iconName: "doc.text.fill",
        iconColor: .white.opacity(0.55),
        warningMessage: nil
    )

    static func classify(_ path: String) -> Risk {
        if path.isEmpty || path == "(patch)" {
            return benign
        }
        if containsDotDotTraversal(path) {
            return Risk(
                iconName: "exclamationmark.triangle.fill",
                iconColor: .yellow,
                warningMessage: "Path contains '..' traversal — verify the resolved target before approving."
            )
        }
        if path.hasPrefix("/") && !isUnderUserHome(path) {
            return Risk(
                iconName: "exclamationmark.triangle.fill",
                iconColor: .yellow,
                warningMessage: "Writes outside your home directory — uncommon for project edits."
            )
        }
        return benign
    }

    private static func containsDotDotTraversal(_ path: String) -> Bool {
        path.split(separator: "/").contains(where: { $0 == ".." })
    }

    private static func isUnderUserHome(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/")
    }
}
