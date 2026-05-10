import SwiftUI
import AtollCore

struct ApprovalCockpitView: View {
    var model: AppModel

    @Environment(\.themePalette) private var palette

    private var lang: LanguageManager { model.lang }
    private var sessions: [AgentSession] { model.approvalCockpitSessions }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lang.t("cockpit.title"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.58))

                    Text(lang.t("cockpit.pending", sessions.count))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.text.swiftUIColor)
                }

                Spacer(minLength: 0)

                Image(systemName: sessions.isEmpty ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(sessions.isEmpty ? palette.role(.completion).swiftUIColor : palette.role(.attention).swiftUIColor)
            }

            if sessions.isEmpty {
                Text(lang.t("cockpit.empty"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            Divider()
                                .overlay(palette.text.swiftUIColor.opacity(0.08))
                        }
                        ApprovalCockpitRow(model: model, session: session)
                    }

                    if sessions.count > 4 {
                        Divider()
                            .overlay(palette.text.swiftUIColor.opacity(0.08))
                        Text(lang.t("cockpit.more", sessions.count - 4))
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
                        .strokeBorder(
                            sessions.isEmpty
                                ? palette.text.swiftUIColor.opacity(0.06)
                                : palette.role(.attention).swiftUIColor.opacity(0.18)
                        )
                )
        )
    }
}

private struct ApprovalCockpitRow: View {
    var model: AppModel
    let session: AgentSession

    @Environment(\.themePalette) private var palette

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(visible(session.spotlightWorkspaceName))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.text.swiftUIColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(session.tool.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BadgeColors.agent(session.tool, palette: palette))
                            .lineLimit(1)
                    }

                    Text(visible(primaryText))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.66))
                        .lineLimit(2)

                    if let secondaryText {
                        Text(visible(secondaryText))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.text.swiftUIColor.opacity(0.38))
                            .lineLimit(1)
                    }
                }
            }

            actionRow
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                primaryActions
                secondaryActions
            }

            VStack(alignment: .leading, spacing: 8) {
                primaryActions
                secondaryActions
            }
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch session.phase {
        case .waitingForApproval:
            HStack(spacing: 8) {
                Button(lang.t("cockpit.deny")) {
                    model.approvePermission(for: session.id, action: .deny)
                }
                .buttonStyle(CockpitButtonStyle(kind: .secondary, palette: palette))

                Button(lang.t("cockpit.allow")) {
                    model.approvePermission(for: session.id, action: .allowOnce)
                }
                .buttonStyle(CockpitButtonStyle(kind: .attention, palette: palette))

                if let toolName = session.permissionRequest?.toolName {
                    Button(lang.t("cockpit.alwaysAllow")) {
                        let rule = ClaudePermissionRuleValue(toolName: toolName)
                        let update = ClaudePermissionUpdate.addRules(
                            destination: .session,
                            rules: [rule],
                            behavior: .allow
                        )
                        model.approvePermission(for: session.id, action: .allowWithUpdates([update]))
                    }
                    .buttonStyle(CockpitButtonStyle(kind: .danger, palette: palette))
                }
            }
        case .waitingForAnswer:
            HStack(spacing: 8) {
                ForEach(quickQuestionOptions, id: \.label) { option in
                    Button(visible(option.label)) {
                        model.answerQuestion(for: session.id, answer: option.response)
                    }
                    .buttonStyle(CockpitButtonStyle(kind: .question, palette: palette))
                }
            }
        case .running, .completed:
            EmptyView()
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 8) {
            Button {
                model.openActionableSession(session.id)
            } label: {
                Label(lang.t("cockpit.open"), systemImage: "rectangle.expand.vertical")
            }
            .buttonStyle(CockpitButtonStyle(kind: .secondary, palette: palette))
            .help(lang.t("cockpit.open"))

            Button {
                model.jumpToSession(session)
            } label: {
                Label(lang.t("cockpit.jump"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(CockpitButtonStyle(kind: .secondary, palette: palette))
            .disabled(session.jumpTarget == nil)
            .help(lang.t("cockpit.jump"))
        }
    }

    private var quickQuestionOptions: [(label: String, response: QuestionPromptResponse)] {
        guard let prompt = session.questionPrompt else { return [] }

        if prompt.questions.count == 1,
           let question = prompt.questions.first,
           !question.multiSelect {
            return question.options
                .filter { !$0.allowsFreeform }
                .prefix(3)
                .map { option in
                    (
                        label: option.label,
                        response: QuestionPromptResponse(answers: [question.question: option.label])
                    )
                }
        }

        return prompt.options
            .prefix(3)
            .map { option in
                (label: option, response: QuestionPromptResponse(answer: option))
            }
    }

    private var primaryText: String {
        switch session.phase {
        case .waitingForApproval:
            trimmed(session.permissionRequest?.summary) ?? session.summary
        case .waitingForAnswer:
            trimmed(session.questionPrompt?.title) ?? session.summary
        case .running, .completed:
            session.summary
        }
    }

    private var secondaryText: String? {
        if let path = trimmed(session.permissionRequest?.affectedPath) {
            return path
        }

        if let command = trimmed(session.currentCommandPreviewText) {
            return command
        }

        return session.spotlightTerminalLabel
    }

    private var phaseIcon: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "bolt.fill"
        case .completed:
            "checkmark.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .waitingForApproval:
            palette.role(.attention).swiftUIColor
        case .waitingForAnswer:
            palette.role(.question).swiftUIColor
        case .running:
            palette.role(.working).swiftUIColor
        case .completed:
            palette.role(.completion).swiftUIColor
        }
    }

    private func visible(_ text: String) -> String {
        model.liveCodingModeEnabled ? LiveCodingRedactor.redact(text) : text
    }

    private func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct CockpitButtonStyle: ButtonStyle {
    enum Kind {
        case attention
        case question
        case danger
        case secondary
    }

    let kind: Kind
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background(configuration: configuration), in: Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .attention, .question, .danger:
            Color.black.opacity(0.86)
        case .secondary:
            palette.text.swiftUIColor.opacity(0.72)
        }
    }

    private func background(configuration: Configuration) -> Color {
        let pressedOpacity = configuration.isPressed ? 0.66 : 0.92

        switch kind {
        case .attention:
            return palette.role(.attention).swiftUIColor.opacity(pressedOpacity)
        case .question:
            return palette.role(.question).swiftUIColor.opacity(pressedOpacity)
        case .danger:
            return palette.role(.danger).swiftUIColor.opacity(pressedOpacity)
        case .secondary:
            return palette.text.swiftUIColor.opacity(configuration.isPressed ? 0.10 : 0.07)
        }
    }
}
