import SwiftUI
import AtollCore

struct SessionTimelineView: View {
    var model: AppModel

    @Environment(\.themePalette) private var palette

    private var lang: LanguageManager { model.lang }
    private var entries: [SessionTimelineEntry] { Array(model.sessionTimelineEntries.prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lang.t("timeline.title"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.58))

                    Text(lang.t("timeline.recent", entries.count))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor)
                }

                Spacer(minLength: 0)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.role(.working).swiftUIColor)
            }

            if entries.isEmpty {
                Text(lang.t("timeline.empty"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                                .overlay(palette.text.swiftUIColor.opacity(0.08))
                        }
                        SessionTimelineRow(model: model, entry: entry)
                    }

                    if model.sessionTimelineEntries.count > entries.count {
                        Divider()
                            .overlay(palette.text.swiftUIColor.opacity(0.08))
                        Text(lang.t("timeline.more", model.sessionTimelineEntries.count - entries.count))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.text.swiftUIColor.opacity(0.42))
                            .padding(.top, 10)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(palette.text.swiftUIColor.opacity(0.06))
                )
        )
    }
}

private struct SessionTimelineRow: View {
    var model: AppModel
    let entry: SessionTimelineEntry

    @Environment(\.themePalette) private var palette

    private var lang: LanguageManager { model.lang }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 16, height: 16)

                Rectangle()
                    .fill(palette.text.swiftUIColor.opacity(0.10))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .padding(.top, 11)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(visible(entry.title))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.9))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.36))
                        .monospacedDigit()
                }

                Text(visible(entry.summary))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.62))
                    .lineLimit(2)

                HStack(spacing: 7) {
                    if let tool = entry.tool {
                        timelineBadge(tool.displayName, tint: BadgeColors.agent(tool, palette: palette))
                    }

                    timelineBadge(kindLabel, tint: tint)

                    if let detail = entry.detail {
                        Text(visible(detail))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.text.swiftUIColor.opacity(0.38))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if model.state.session(id: entry.sessionID) != nil {
                        Button {
                            model.openSessionInIsland(entry.sessionID)
                        } label: {
                            Image(systemName: "rectangle.expand.vertical")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.55))
                        .help(lang.t("timeline.open"))
                    }
                }
            }
            .padding(.vertical, 9)
        }
    }

    private func timelineBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        switch entry.kind {
        case .sessionStarted:
            "play.fill"
        case .activity, .metadata:
            "bolt.fill"
        case .permission:
            "exclamationmark.triangle.fill"
        case .question:
            "questionmark.circle.fill"
        case .completion:
            "checkmark.circle.fill"
        case .jumpTarget:
            "arrow.up.forward.app.fill"
        case .resolved:
            "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        if entry.requiresAttention {
            return entry.kind == .question
                ? palette.role(.question).swiftUIColor
                : palette.role(.attention).swiftUIColor
        }

        switch entry.kind {
        case .completion, .resolved:
            return palette.role(.completion).swiftUIColor
        case .question:
            return palette.role(.question).swiftUIColor
        case .permission:
            return palette.role(.attention).swiftUIColor
        default:
            return palette.role(.working).swiftUIColor
        }
    }

    private var kindLabel: String {
        switch entry.kind {
        case .sessionStarted:
            lang.t("timeline.kind.started")
        case .activity:
            lang.t("timeline.kind.activity")
        case .permission:
            lang.t("timeline.kind.permission")
        case .question:
            lang.t("timeline.kind.question")
        case .completion:
            lang.t("timeline.kind.completion")
        case .jumpTarget:
            lang.t("timeline.kind.jump")
        case .metadata:
            lang.t("timeline.kind.metadata")
        case .resolved:
            lang.t("timeline.kind.resolved")
        }
    }

    private func visible(_ text: String) -> String {
        model.liveCodingModeEnabled ? LiveCodingRedactor.redact(text) : text
    }
}
