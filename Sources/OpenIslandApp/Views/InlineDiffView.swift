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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if diff.truncated {
                Text("Diff too large to preview (\(diff.additionCount) lines). Click Yes to apply, or open the file to review.")
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
        HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            Text(displayName(for: diff.filePath))
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
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.top, 6)
    }

    private func stat(symbol: String, count: Int, tint: Color) -> some View {
        Text("\(symbol)\(count)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
    }

    private func row(for line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(prefix(for: line))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(prefixColor(for: line))
                .frame(width: Self.prefixWidth, alignment: .leading)

            Text(LightweightSyntaxHighlighter.attribute(line.text, language: language))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Trim the file path to a tail-friendly form so a deep nested path
    /// still shows the filename. We keep the last two path components
    /// (parent dir + filename) when possible.
    private func displayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }
}
