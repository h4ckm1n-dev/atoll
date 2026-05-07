import SwiftUI
@preconcurrency import MarkdownUI
import AtollCore

/// Read-only render of a session's full plan markdown in the row
/// disclosure. The legacy `PlanChecklistView` only shows the parsed
/// step skeleton (headings + bullets); plans with paragraphs, code
/// blocks, or non-bullet structure render as empty there because the
/// parser drops those sections. This view shows the original document.
///
/// Bounded vertical space — the notch is small, so we cap the scroll
/// area and let MarkdownUI handle wrapping internally.
struct PlanMarkdownView: View {
    let rawMarkdown: String
    let palette: ThemePalette
    var emptyMessage: String = "No plan recorded yet."

    var body: some View {
        Group {
            if rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Markdown(rawMarkdown)
                        .markdownTheme(.planMarkdown(palette))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var emptyState: some View {
        Text(emptyMessage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.text.swiftUIColor.opacity(0.45))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    /// Theme tuned for the row plan disclosure — readable inside the
    /// constrained notch surface, palette-aware so colors track the
    /// active theme. Mirrors `completionCard` patterns but uses slightly
    /// smaller body type for the denser context.
    @MainActor static func planMarkdown(_ palette: ThemePalette) -> Theme {
        let text = palette.text.swiftUIColor
        let surface0 = palette.surface0.swiftUIColor
        let surface1 = palette.surface1.swiftUIColor
        let attention = palette.role(.attention).swiftUIColor
        let bulletMarker = text.opacity(0.6)

        return Theme()
            .text {
                ForegroundColor(text)
                FontSize(12)
            }
            .strong { FontWeight(.bold) }
            .emphasis { FontStyle(.italic) }
            .link { ForegroundColor(attention) }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(11.5)
                ForegroundColor(text)
                BackgroundColor(surface1)
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(11.5)
                        ForegroundColor(text)
                    }
                    .padding(8)
                    .background(surface0)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(surface1, lineWidth: 1)
                    )
                    .markdownMargin(top: 6, bottom: 6)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(16)
                        FontWeight(.bold)
                        ForegroundColor(text)
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(14.5)
                        FontWeight(.bold)
                        ForegroundColor(text)
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(13)
                        FontWeight(.semibold)
                        ForegroundColor(text)
                    }
                    .markdownMargin(top: 6, bottom: 2)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(12.5)
                        FontWeight(.semibold)
                        ForegroundColor(text.opacity(0.92))
                    }
                    .markdownMargin(top: 4, bottom: 2)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 2, bottom: 2)
            }
            .bulletedListMarker { _ in
                Text("•")
                    .foregroundColor(bulletMarker)
            }
            .numberedListMarker { configuration in
                Text("\(configuration.itemNumber).")
                    .foregroundColor(bulletMarker)
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(text.opacity(0.85))
                        FontSize(12)
                    }
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(attention.opacity(0.4))
                            .frame(width: 3)
                    }
            }
            .thematicBreak {
                Divider()
                    .background(text.opacity(0.15))
                    .markdownMargin(top: 8, bottom: 8)
            }
    }
}
