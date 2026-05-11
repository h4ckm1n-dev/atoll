import SwiftUI
import AppKit
@preconcurrency import MarkdownUI
import AtollCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Auto-height container: renders content directly (auto-sizing).
/// When content exceeds maxHeight, wraps in ScrollView at fixed maxHeight.
struct AutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    private var isScrollable: Bool { contentHeight > maxHeight }

    var body: some View {
        // Always use ScrollView so the content gets unconstrained vertical
        // space for measurement.  Without this, a tight parent window can
        // cap the GeometryReader measurement, making long content appear
        // truncated instead of scrollable.
        ScrollView(.vertical) {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(ContentHeightKey.self) { height in
                    if height > 0 { contentHeight = height }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isScrollable ? .automatic : .hidden)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

// MARK: - Row Height Estimation

extension AgentSession {
    /// Estimated row height matching `IslandSessionRow` layout for viewport sizing.
    func estimatedIslandRowHeight(at date: Date, isManuallyExpanded: Bool = false) -> CGFloat {
        let rawPresence = islandPresence(at: date)
        let presence = (rawPresence == .inactive && isManuallyExpanded) ? .active : rawPresence
        // Base: vertical padding (28) + headline (~18) + rounding (2)
        var height: CGFloat = 48
        guard presence != .inactive else { return height }
        if spotlightPromptLineText != nil || (isManuallyExpanded && spotlightPromptText != nil) {
            height += 24   // spacing (8) + text (16)
        }
        if spotlightActivityLineText != nil || isManuallyExpanded {
            height += 22  // spacing (8) + text (14)
        }
        if let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty {
            height += 22  // spacing (8) + header (14)
            height += CGFloat(subagents.count) * 18  // each subagent row (spacing 4 + text 14)
        }
        if let tasks = claudeMetadata?.activeTasks, !tasks.isEmpty {
            height += 20  // spacing (8) + summary (12)
            height += CGFloat(tasks.count) * 16  // each task row (spacing 3 + text 13)
        }
        return height
    }
}

// MARK: - Animations

private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
private let closeAnimation = Animation.smooth(duration: 0.3)
private let popAnimation = Animation.spring(response: 0.3, dampingFraction: 0.5)

/// Composite equatable key so `hasClosedPresence` and `expansionWidth` share
/// a single `.animation(.smooth, value:)` modifier instead of two separate
/// ones that can conflict when both change simultaneously.
private struct ClosedPresenceKey: Equatable {
    var present: Bool
    var width: CGFloat
}

private struct ConditionalDrawingGroup: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

// MARK: - Main island view

struct IslandPanelView: View {
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchLaneSafetyInset: CGFloat = 12
    private static let closedIdleEdgeHeight: CGFloat = 4

    var model: AppModel

    @Environment(\.themePalette) private var palette
    @Namespace private var notchNamespace
    @State private var isHovering = false
    @State private var lastCompletionTimestamp: Date?
    @State private var lastCelebrationTimestamp: Date?

    @AppStorage("appearance.panelMaterial")
    private var panelMaterialRaw: String = AppPanelMaterial.solid.rawValue

    private var panelMaterial: AppPanelMaterial {
        AppPanelMaterial(rawValue: panelMaterialRaw) ?? .solid
    }

    private var isOpened: Bool {
        model.notchStatus == .opened
    }

    private var usesOpenedVisualState: Bool {
        isOpened
    }

    /// Returns the fill for the opened-panel surface.
    /// Collapsed/idle state is pure black on notched MacBooks to preserve
    /// the physical-notch blend illusion. On external / non-notched
    /// displays there is no hardware notch to blend with, so honor the
    /// active theme — otherwise a light theme (e.g. Cappuccino) shows a
    /// black bubble against a cream chrome.
    @ViewBuilder
    private func surfaceFill(
        palette: ThemePalette,
        hidesChrome: Bool
    ) -> some View {
        if hidesChrome {
            Color.clear
        } else if !usesOpenedVisualState {
            if isExternalDisplayPlacement {
                Rectangle().fill(palette.mantle.swiftUIColor)
            } else {
                Color.black
            }
        } else {
            switch panelMaterial {
            case .solid:
                Rectangle()
                    .fill(palette.mantle.swiftUIColor)
            case .frostedThin:
                ZStack {
                    Rectangle().fill(.thinMaterial)
                    Rectangle().fill(palette.crust.swiftUIColor.opacity(0.55))
                }
            case .frostedUltraThin:
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(palette.crust.swiftUIColor.opacity(0.55))
                }
            }
        }
    }

    private var isPopping: Bool {
        model.notchStatus == .popping
    }

    /// Single animation selection based on the current notch status.
    private var notchTransitionAnimation: Animation {
        switch model.notchStatus {
        case .opened:  return openAnimation
        case .closed:  return closeAnimation
        case .popping: return popAnimation
        }
    }

    private var closedSpotlightSession: AgentSession? {
        model.surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? model.surfacedSessions.first(where: { $0.phase == .running })
            ?? model.surfacedSessions.first
    }

    private var hasClosedPresence: Bool {
        model.liveSessionCount > 0
    }

    private var showsIdleEdgeWhenCollapsed: Bool {
        model.showsIdleEdgeWhenCollapsed
    }

    /// Whether any session has activity worth showing in the closed notch
    private var hasClosedActivity: Bool {
        guard let session = closedSpotlightSession else {
            return false
        }
        return session.phase == .running || session.phase.requiresAttention
    }

    /// Scout icon tint: tracks the spotlight session's phase via the
    /// user-configured status colors. Falls back to the surfaced-session
    /// summary (blue running / green idle / gray empty) when no session
    /// is currently spotlighted.
    private var scoutTint: Color {
        if let phase = closedSpotlightSession?.phase {
            return model.statusColor(for: phase)
        }
        let sessions = model.surfacedSessions
        if sessions.contains(where: { $0.phase == .running }) {
            return palette.blue.swiftUIColor // working
        }
        if !sessions.isEmpty {
            return palette.green.swiftUIColor // idle/live
        }
        return palette.text.swiftUIColor.opacity(0.4) // gray
    }

    private var displayedPixelShapeStyle: IslandPixelShapeStyle {
        let style = model.islandPixelShapeStyle
        return model.advancedAvatarsEnabled || !style.isAdvanced ? style : .bars
    }

    private var countBadgeWidth: CGFloat {
        let digits = max(1, "\(model.liveSessionCount)".count)
        return CGFloat(26 + max(0, digits - 1) * 8)
    }

    private var expansionWidth: CGFloat {
        guard !showsIdleEdgeWhenCollapsed else { return 0 }
        guard hasClosedPresence else { return 0 }
        let hasPending = closedSpotlightSession?.phase.requiresAttention == true
        let leftWidth = sideWidth + 8 + (hasPending ? 18 : 0)
        let rightWidth = max(sideWidth, countBadgeWidth) + (hasPending ? 18 : 0)
        return leftWidth + rightWidth + 16 + (hasPending ? 6 : 0)
    }

    /// Composite key combining `hasClosedPresence` and `expansionWidth` so a
    /// single `.animation(.smooth)` modifier drives both values.  Previously
    /// they had two separate `.animation(.smooth, value:)` modifiers that
    /// could conflict when they changed in the same runloop pass.
    private var closedPresenceAnimationKey: ClosedPresenceKey {
        ClosedPresenceKey(present: hasClosedPresence, width: expansionWidth)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchHeight - 12) + 10
    }

    private var targetOverlayScreen: NSScreen? {
        if let targetScreenID = model.overlayPlacementDiagnostics?.targetScreenID,
           let screen = NSScreen.screens.first(where: { screenID(for: $0) == targetScreenID }) {
            return screen
        }

        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private var usesNotchAwareOpenedHeader: Bool {
        model.overlayPlacementDiagnostics?.mode == .notch
            || targetOverlayScreen?.safeAreaInsets.top ?? 0 > 0
    }

    /// True when the closed island sits on an external (non-notched) display.
    /// The central black rectangle is otherwise aligned with the physical
    /// notch, so center content is only useful here.
    private var isExternalDisplayPlacement: Bool {
        if let mode = model.overlayPlacementDiagnostics?.mode {
            return mode == .topBar
        }
        // Fallback when diagnostics haven't been populated yet.
        return (targetOverlayScreen?.safeAreaInsets.top ?? 0) == 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear

                notchContent(availableSize: geometry.size)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onChange(of: closedSpotlightSession?.phase) { _, newPhase in
            if newPhase == .completed {
                lastCompletionTimestamp = Date()
            }
        }
        .onChange(of: lastCompletionTimestamp) { _, timestamp in
            guard timestamp != nil else { return }
            guard model.celebrationsEnabled else { return }
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            lastCelebrationTimestamp = Date()
        }
        .task(id: lastCompletionTimestamp) {
            await expireTimestamp(
                $lastCompletionTimestamp,
                window: CompanionState.celebratingWindow
            )
        }
        .task(id: lastCelebrationTimestamp) {
            await expireTimestamp(
                $lastCelebrationTimestamp,
                window: CelebrationParticles.duration
            )
        }
    }

    @ViewBuilder
    private func notchContent(availableSize: CGSize) -> some View {
        // Window is always at opened size — use opened insets unconditionally.
        let panelShadowHorizontalInset = IslandChromeMetrics.openedShadowHorizontalInset
        let panelShadowBottomInset = IslandChromeMetrics.openedShadowBottomInset
        let layoutWidth = max(0, availableSize.width - (panelShadowHorizontalInset * 2))
        let layoutHeight = max(0, availableSize.height - panelShadowBottomInset)

        // Opened dimensions: fill the layout area with outer padding.
        let outerHorizontalPadding: CGFloat = 28
        let outerBottomPadding: CGFloat = 14
        let openedWidth = max(0, layoutWidth - outerHorizontalPadding)
        let openedHeight = max(closedNotchHeight, layoutHeight - outerBottomPadding)

        // Closed dimensions: sized to the actual notch + session indicators.
        let closedTotalWidth = closedNotchWidth + expansionWidth + (isPopping ? 18 : 0)
        let closedTotalHeight = closedNotchHeight

        let currentWidth = usesOpenedVisualState ? openedWidth : closedTotalWidth
        let currentHeight = usesOpenedVisualState ? openedHeight : closedTotalHeight
        let horizontalInset = usesOpenedVisualState ? 14.0 : 0.0
        let bottomInset = usesOpenedVisualState ? 14.0 : 0.0
        let surfaceWidth = currentWidth + (horizontalInset * 2)
        let surfaceHeight = currentHeight + bottomInset
        let surfaceShape = NotchShape(
            topCornerRadius: usesOpenedVisualState ? NotchShape.openedTopRadius : NotchShape.closedTopRadius,
            bottomCornerRadius: usesOpenedVisualState ? NotchShape.openedBottomRadius : NotchShape.closedBottomRadius
        )
        let hidesClosedSurfaceChrome = showsIdleEdgeWhenCollapsed && !usesOpenedVisualState
        let idleEdgeWidth = closedNotchWidth + (isPopping ? 18 : 0)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Build the surface fill based on panel material + collapsed-vs-open state.
                // Collapsed (notch-blend) is always pure black regardless of material —
                // frosting in idle would break the physical-notch illusion.
                surfaceShape
                    .fill(Color.clear)
                    .background(
                        surfaceFill(
                            palette: model.themeManager.palette,
                            hidesChrome: hidesClosedSurfaceChrome
                        )
                        .clipShape(surfaceShape)
                    )
                    .frame(width: surfaceWidth, height: surfaceHeight)

                VStack(spacing: 0) {
                    headerRow
                        .frame(height: closedNotchHeight)
                        .opacity(hidesClosedSurfaceChrome ? 0 : 1)

                    openedContent
                        .frame(width: openedWidth - 24)
                        .frame(maxHeight: usesOpenedVisualState ? currentHeight - closedNotchHeight - 12 : 0, alignment: .top)
                        .opacity(usesOpenedVisualState ? 1 : 0)
                        .clipped()
                }
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
                .padding(.horizontal, horizontalInset)
                .padding(.bottom, bottomInset)
                .clipShape(surfaceShape)
                .overlay(alignment: .bottom) {
                    if usesOpenedVisualState, model.mediaControlsEnabled {
                        MediaControlDock(
                            snapshot: model.mediaPlaybackController.snapshot,
                            palette: model.themeManager.palette,
                            showsArtwork: model.mediaArtworkEnabled,
                            onPrevious: { model.mediaPlaybackController.previousTrack() },
                            onPlayPause: { model.mediaPlaybackController.togglePlayPause() },
                            onNext: { model.mediaPlaybackController.nextTrack() }
                        )
                        .padding(.bottom, 8)
                    }
                }
                .overlay(alignment: .top) {
                    // Black strip to blend with physical notch at the very top
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                        .padding(.horizontal, usesOpenedVisualState ? NotchShape.openedTopRadius : NotchShape.closedTopRadius)
                        .opacity(hidesClosedSurfaceChrome ? 0 : 1)
                }
                .overlay {
                    surfaceShape
                        .stroke(palette.text.swiftUIColor.opacity(hidesClosedSurfaceChrome ? 0 : (usesOpenedVisualState ? 0.07 : 0.04)), lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: idleEdgeWidth, height: Self.closedIdleEdgeHeight)
                        .overlay {
                            Capsule()
                                .stroke(palette.text.swiftUIColor.opacity(0.05), lineWidth: 1)
                        }
                        .opacity(showsIdleEdgeWhenCollapsed ? 1 : 0)
                }

                if let ts = lastCelebrationTimestamp,
                   Date().timeIntervalSince(ts) < CelebrationParticles.duration {
                    CelebrationParticles(
                        tint: spotlightProjectColor,
                        startedAt: ts,
                        count: 12
                    )
                    .frame(width: surfaceWidth, height: surfaceHeight)
                    .clipShape(surfaceShape)
                    .allowsHitTesting(false)
                    .id(ts)
                }
            }
            .frame(width: surfaceWidth, height: surfaceHeight, alignment: .top)
        }
        .scaleEffect(usesOpenedVisualState ? 1 : (isHovering ? IslandChromeMetrics.closedHoverScale : 1), anchor: .top)
        .padding(.horizontal, panelShadowHorizontalInset)
        .padding(.bottom, panelShadowBottomInset)
        .animation(notchTransitionAnimation, value: model.notchStatus)
        .animation(.smooth, value: closedPresenceAnimationKey)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if !isOpened {
                model.notchOpen(reason: .click)
            }
        }
    }

    // MARK: - Closed state

    private var closedNotchWidth: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.notchSize.width ?? NSScreen.externalDisplayNotchWidth
    }

    private var closedNotchHeight: CGFloat {
        (targetOverlayScreen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }))?.islandClosedHeight ?? 24
    }

    private var spotlightProjectColor: ProjectColor? {
        guard let key = closedSpotlightSession?.jumpTarget?.workingDirectory
            ?? closedSpotlightSession?.jumpTarget?.workspaceName else {
            return nil
        }
        return model.projectColorRegistry.color(for: key)
    }

    /// Sleeps until the time window from the bound timestamp elapses, then
    /// nils it out. Driven by `.task(id:)` so each new timestamp cancels the
    /// prior pending expiry. Without this, the confetti container would persist
    /// past its window whenever no other observed state changed in the meantime.
    @MainActor
    private func expireTimestamp(
        _ binding: Binding<Date?>,
        window: TimeInterval
    ) async {
        guard let ts = binding.wrappedValue else { return }
        let elapsed = Date().timeIntervalSince(ts)
        let remaining = max(0, window - elapsed)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        guard !Task.isCancelled, binding.wrappedValue == ts else { return }
        binding.wrappedValue = nil
    }

    // MARK: - Header row (shared between closed and opened)

    @ViewBuilder
    private var headerRow: some View {
        if usesOpenedVisualState {
            openedHeaderContent
                .frame(height: closedNotchHeight)
        } else {
            HStack(spacing: 0) {
                if hasClosedPresence {
                    IslandPixelGlyph(
                        tint: scoutTint,
                        style: displayedPixelShapeStyle,
                        isAnimating: hasClosedActivity,
                        customAvatarImage: model.customAvatarImage
                    )
                    .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)
                    .frame(width: sideWidth + 8)
                }

                if !hasClosedPresence {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: closedNotchWidth - 20)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0))
                        .overlay(
                            CentralActivityLabel(
                                toolName: closedSpotlightSession?.currentToolName,
                                preview: streamSafeOptional(closedSpotlightSession?.currentCommandPreviewText),
                                isVisible: isExternalDisplayPlacement && hasClosedPresence
                            )
                        )
                }

                if hasClosedPresence {
                    let slotWidth = max(sideWidth, countBadgeWidth)

                    ClosedCountBadge(liveCount: model.liveSessionCount, tint: palette.text.swiftUIColor.opacity(0.85))
                        .matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)
                        .frame(width: slotWidth)
                }
            }
            .frame(height: closedNotchHeight)
        }
    }

    @ViewBuilder
    private var openedHeaderContent: some View {
        if usesNotchAwareOpenedHeader {
            GeometryReader { geometry in
                let providers = openedUsageProviders
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        usageLaneView(providerGroups.left, alignment: .leading)
                    }
                    .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: 0) {
                        usageLaneView(providerGroups.right, alignment: .trailing)
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, Self.headerHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, Self.headerHorizontalPadding)
            .padding(.trailing, Self.headerHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedContent: some View {
        VStack(spacing: 8) {
            if !model.hasAnyInstalledAgent {
                installHooksHint
            }

            if model.shouldShowSessionBootstrapPlaceholder {
                sessionBootstrapPlaceholder
            } else if model.islandListSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, mediaControlDockContentReserve)
    }

    /// Persistent hint at the top of the expanded island while no agent
    /// hooks are installed. Decoupled from session presence — process
    /// discovery routinely surfaces sessions even on a freshly cleaned
    /// install, so the empty-state branch alone never reaches users who
    /// already run an agent.
    private var installHooksHint: some View {
        Button {
            model.showOnboarding()
        } label: {
            notchAuxiliaryCard(
                icon: "sparkles",
                title: model.lang.t("island.hint.installHooks"),
                detail: nil,
                tint: palette.role(.working).swiftUIColor,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionBootstrapPlaceholder: some View {
        notchAuxiliaryCard(
            icon: "antenna.radiowaves.left.and.right",
            title: model.lang.t("island.checkingTerminals"),
            detail: model.lang.t("island.terminalOwnership"),
            tint: palette.blue.swiftUIColor,
            showsProgress: true
        )
    }

    private var emptyState: some View {
        notchAuxiliaryCard(
            icon: "terminal",
            title: model.lang.t("island.noTerminals"),
            detail: model.recentSessions.isEmpty
                ? model.lang.t("island.startAgent")
                : model.lang.t("island.recentSessions"),
            tint: palette.text.swiftUIColor.opacity(0.58)
        )
    }

    private func notchAuxiliaryCard(
        icon: String,
        title: String,
        detail: String?,
        tint: Color,
        showsProgress: Bool = false,
        showsChevron: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)

                if showsProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(tint.opacity(0.88))
                        .scaleEffect(0.58)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.95))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.82))
                    .lineLimit(2)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.text.swiftUIColor.opacity(0.42))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.crust.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(0.22))
        )
    }

    private var actionableSessionID: String? {
        model.islandSurface.sessionID
    }

    /// Whether the panel was opened by a notification (show only actionable session + footer).
    private var isNotificationMode: Bool {
        model.notchOpenReason == .notification && actionableSessionID != nil
    }

    private static let mediaControlDockControlsReserve: CGFloat = 42
    private static let mediaControlDockArtworkReserve: CGFloat = 112
    private static let maxSessionListHeight: CGFloat = 560

    private var mediaControlDockContentReserve: CGFloat {
        guard model.mediaControlsEnabled else { return 0 }
        return model.mediaArtworkEnabled
            ? Self.mediaControlDockArtworkReserve
            : Self.mediaControlDockControlsReserve
    }

    private var sessionList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if isNotificationMode {
                // Notification mode: NO ScrollView — content sizes naturally
                sessionListContent(context: context)
                    .padding(.vertical, 2)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: NotificationContentHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
                    .onPreferenceChange(NotificationContentHeightKey.self) { height in
                        if height > 0 {
                            model.measuredNotificationContentHeight = height
                        }
                    }
            } else if model.islandListSessions.count <= 1 {
                sessionListContent(context: context)
                    .padding(.vertical, 2)
            } else {
                // List mode: scroll when content exceeds the panel's available space.
                // The parent frame constraint (currentHeight - closedNotchHeight - 12)
                // determines the viewport; ScrollView handles overflow naturally.
                ScrollView(.vertical) {
                    sessionListContent(context: context)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func sessionListContent(context: TimelineViewDefaultContext) -> some View {
        VStack(spacing: 6) {
            if isNotificationMode, let session = model.activeIslandCardSession {
                IslandSessionRow(
                    session: session,
                    referenceDate: context.date,
                    isActionable: true,
                    isKeyboardSelected: model.selectedSessionID == session.id,
                    isKeyboardReplyFocused: model.keyboardReplySessionID == session.id,
                    useDrawingGroup: model.notchStatus == .opened,
                    isInteractive: model.notchStatus == .opened,
                    lang: model.lang,
                    onApprove: { model.approvePermission(for: session.id, action: $0) },
                    onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                    onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                        ? { model.submitIslandKeyboardReply(for: session, text: $0) } : nil,
                    onCancelReply: { model.cancelIslandKeyboardReply() },
                    contextUsage: model.contextUsageRegistry.usage(for: session.id),
                    gitSnapshot: (model.sessionGitBranchBadgeEnabled || model.sessionGitDiffBadgeEnabled)
                        ? model.gitWorkspaceStatusRegistry.snapshot(for: session.jumpTarget?.workingDirectory)
                        : nil,
                    planState: model.planModeRegistry.plan(for: session.id),
                    onTogglePlanStep: { stepID in
                        model.planModeRegistry.toggleCheck(sessionID: session.id, stepID: stepID)
                    },
                    showsToolBadge: model.sessionToolBadgeEnabled,
                    showsTerminalBadge: model.sessionTerminalBadgeEnabled,
                    showsGitBranchBadge: model.sessionGitBranchBadgeEnabled,
                    showsGitDiffBadge: model.sessionGitDiffBadgeEnabled,
                    showsContextBadge: model.sessionContextBadgeEnabled,
                    showsAgeBadge: model.sessionAgeBadgeEnabled,
                    themePalette: model.themeManager.palette,
                    streamSafeTextEnabled: model.liveCodingModeEnabled,
                    isManuallyExpanded: model.expandedSessionCardIDs.contains(session.id),
                    onManualExpansionChange: { expanded in
                        model.setSessionCardExpanded(session.id, expanded: expanded)
                    },
                    onJump: { model.jumpToSession(session) }
                )

                if model.allSessions.count > 1 {
                    Button {
                        let isCompletion = session.phase == .completed
                        model.expandNotificationToSessionList(clearExpansion: isCompletion)
                    } label: {
                        Text(model.lang.t("island.showAll", model.allSessions.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.text.swiftUIColor.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(model.islandListSessions) { session in
                    IslandSessionRow(
                        session: session,
                        referenceDate: context.date,
                        isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                        isKeyboardSelected: model.selectedSessionID == session.id,
                        isKeyboardReplyFocused: model.keyboardReplySessionID == session.id,
                        useDrawingGroup: model.notchStatus == .opened,
                        isInteractive: model.notchStatus == .opened,
                        lang: model.lang,
                        onApprove: { model.approvePermission(for: session.id, action: $0) },
                        onAnswer: { model.answerQuestion(for: session.id, answer: $0) },
                        onReply: TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled)
                            ? { model.submitIslandKeyboardReply(for: session, text: $0) } : nil,
                        onCancelReply: { model.cancelIslandKeyboardReply() },
                        contextUsage: model.contextUsageRegistry.usage(for: session.id),
                        gitSnapshot: (model.sessionGitBranchBadgeEnabled || model.sessionGitDiffBadgeEnabled)
                            ? model.gitWorkspaceStatusRegistry.snapshot(for: session.jumpTarget?.workingDirectory)
                            : nil,
                        planState: model.planModeRegistry.plan(for: session.id),
                        onTogglePlanStep: { stepID in
                            model.planModeRegistry.toggleCheck(sessionID: session.id, stepID: stepID)
                        },
                        showsToolBadge: model.sessionToolBadgeEnabled,
                        showsTerminalBadge: model.sessionTerminalBadgeEnabled,
                        showsGitBranchBadge: model.sessionGitBranchBadgeEnabled,
                        showsGitDiffBadge: model.sessionGitDiffBadgeEnabled,
                        showsContextBadge: model.sessionContextBadgeEnabled,
                        showsAgeBadge: model.sessionAgeBadgeEnabled,
                        themePalette: model.themeManager.palette,
                        streamSafeTextEnabled: model.liveCodingModeEnabled,
                        isManuallyExpanded: model.expandedSessionCardIDs.contains(session.id),
                        onManualExpansionChange: { expanded in
                            model.setSessionCardExpanded(session.id, expanded: expanded)
                        },
                        onJump: { model.jumpToSession(session) },
                        onDismiss: session.isRemote ? { model.dismissSession(session.id) } : nil
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private var surfaceFill: some ShapeStyle {
        Color.black
    }

    private func phaseColor(_ phase: SessionPhase) -> Color {
        model.statusColor(for: phase)
    }

    private func streamSafeOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        return model.liveCodingModeEnabled ? LiveCodingRedactor.redact(text) : text
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        let providers = openedUsageProviders

        if providers.isEmpty == false {
            ViewThatFits(in: .horizontal) {
                usageSummaryView(providers, layout: .full)
                usageSummaryView(providers, layout: .compact)
                usageSummaryView(providers, layout: .condensed)
                usageSummaryView(providers, layout: .minimal)
            }
        } else {
            HStack(spacing: 8) {
                Text(model.lang.t("app.name"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.9))

                Text(model.lang.t("island.usageWaiting"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.4))
            }
            .lineLimit(1)
        }
    }

    private var openedUsageProviders: [UsageProviderPresentation] {
        var providers: [UsageProviderPresentation] = []

        if let snapshot = model.claudeUsageSnapshot,
           snapshot.isEmpty == false {
            var windows: [UsageWindowPresentation] = []

            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: fiveHour.usedPercentage,
                        resetsAt: fiveHour.resetsAt
                    )
                )
            }

            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: sevenDay.usedPercentage,
                        resetsAt: sevenDay.resetsAt
                    )
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if model.showCodexUsage,
           let snapshot = model.codexUsageSnapshot,
           snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageWindowPresentation(
                    id: "codex-\(window.key)",
                    label: window.label,
                    usedPercentage: window.usedPercentage,
                    resetsAt: window.resetsAt
                )
            }

            if windows.isEmpty == false {
                providers.append(
                    UsageProviderPresentation(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        return providers
    }

    private func splitUsageProviders(
        _ providers: [UsageProviderPresentation]
    ) -> (left: [UsageProviderPresentation], right: [UsageProviderPresentation]) {
        switch providers.count {
        case 0:
            return ([], [])
        case 1:
            return ([providers[0]], [])
        case 2:
            return ([providers[0]], [providers[1]])
        default:
            let splitIndex = Int(ceil(Double(providers.count) / 2.0))
            return (
                Array(providers.prefix(splitIndex)),
                Array(providers.dropFirst(splitIndex))
            )
        }
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                usageSummaryView(providers, layout: .full)
                usageSummaryView(providers, layout: .compact)
                usageSummaryView(providers, layout: .condensed)
                usageSummaryView(providers, layout: .minimal)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> OpenedHeaderMetrics {
        let contentWidth = max(0, totalWidth - (Self.headerHorizontalPadding * 2))
        guard usesNotchAwareOpenedHeader,
              let screen = targetOverlayScreen else {
            let rightLaneWidth = contentWidth / 2
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return OpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightLaneWidth: rightLaneWidth
            )
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + Self.headerHorizontalPadding
        let contentMaxX = panelMaxX - Self.headerHorizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightLaneWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return OpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightLaneWidth: rightLaneWidth
        )
    }

    private func usageSummaryView(
        _ providers: [UsageProviderPresentation],
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: layout.providerSpacing) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    usageSeparator(layout.providerSeparator, opacity: layout.providerSeparatorOpacity)
                }

                usageProviderView(provider, layout: layout)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func usageProviderView(
        _ provider: UsageProviderPresentation,
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: 6) {
            UsageProviderIcon(providerID: provider.id, size: layout.providerIconSize)

            Text(layout.usesShortProviderTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text.swiftUIColor.opacity(0.9))

            ForEach(Array(provider.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    usageSeparator(layout.windowSeparator, opacity: layout.windowSeparatorOpacity)
                }

                usageWindowView(window: window, layout: layout)
            }
        }
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }

        return screen.localizedName
    }

    private func usageWindowView(
        window: UsageWindowPresentation,
        layout: UsageSummaryLayout
    ) -> some View {
        HStack(spacing: 4) {
            if layout.showsWindowLabel {
                Text(window.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.55))
            }

            Text("\(window.roundedUsedPercentage)%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(usageColor(for: window.usedPercentage))

            if layout.showsResetTime,
               let resetsAt = window.resetsAt,
               let remaining = remainingDurationString(until: resetsAt) {
                Text(remaining)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.35))
            }
        }
    }

    private func usageSeparator(_ title: String, opacity: Double) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.text.swiftUIColor.opacity(opacity))
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.surface0.swiftUIColor, in: Capsule())
    }

    private func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case 90...:
            palette.role(.danger).swiftUIColor.opacity(0.95)
        case 70..<90:
            palette.role(.warning).swiftUIColor.opacity(0.95)
        default:
            palette.role(.success).swiftUIColor.opacity(0.95)
        }
    }

    private func remainingDurationString(until date: Date) -> String? {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated

        if interval >= 86_400 {
            formatter.allowedUnits = [.day]
            formatter.maximumUnitCount = 1
        } else if interval >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
            formatter.maximumUnitCount = 2
        } else {
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
        }

        return formatter.string(from: interval)
    }
}

private struct MediaControlDock: View {
    let snapshot: MediaPlaybackSnapshot
    let palette: ThemePalette
    let showsArtwork: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            if showsArtwork, let artwork = snapshot.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 116, height: 65)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(palette.text.swiftUIColor.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 6) {
                mediaButton(systemName: "backward.fill", label: "Previous", action: onPrevious)
                mediaButton(
                    systemName: snapshot.isPlaying ? "pause.fill" : "play.fill",
                    label: snapshot.isPlaying ? "Pause" : "Play",
                    action: onPlayPause,
                    isPrimary: true
                )
                mediaButton(systemName: "forward.fill", label: "Next", action: onNext)
            }
        }
        .fixedSize()
        .opacity(0.82)
        .help(helpText)
    }

    private func mediaButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void,
        isPrimary: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? 10.5 : 9, weight: .bold))
                .foregroundStyle(palette.text.swiftUIColor.opacity(isPrimary ? 0.9 : 0.62))
                .frame(width: isPrimary ? 28 : 24, height: isPrimary ? 24 : 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isPrimary ? 0.075 : 0.035))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var helpText: String {
        if snapshot.hasContent {
            let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Media controls" : title
        }
        return "Media controls"
    }
}

private struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

    var shortTitle: String {
        switch id {
        case "claude":
            "Cl"
        case "codex":
            "Cx"
        default:
            String(title.prefix(2))
        }
    }
}

private struct UsageProviderIcon: View {
    let providerID: String
    let size: CGFloat

    var body: some View {
        ZStack {
            switch providerID {
            case "claude":
                Text("A")
                    .font(.system(size: size * 0.72, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            case "codex":
                ForEach(0..<6, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.86))
                        .frame(width: size * 0.18, height: size * 0.44)
                        .offset(y: -size * 0.18)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: size * 0.28, height: size * 0.28)
            default:
                Circle()
                    .strokeBorder(.white.opacity(0.82), lineWidth: max(1, size * 0.12))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

private enum UsageSummaryLayout {
    case full
    case compact
    case condensed
    case minimal

    var showsResetTime: Bool {
        switch self {
        case .full:
            true
        case .compact, .condensed, .minimal:
            false
        }
    }

    var showsWindowLabel: Bool {
        switch self {
        case .full, .compact:
            true
        case .condensed, .minimal:
            false
        }
    }

    var usesShortProviderTitle: Bool {
        self == .minimal
    }

    var providerIconSize: CGFloat {
        switch self {
        case .full, .compact:
            13
        case .condensed, .minimal:
            12
        }
    }

    var providerSpacing: CGFloat {
        switch self {
        case .full, .compact:
            8
        case .condensed, .minimal:
            6
        }
    }

    var providerSeparator: String {
        "|"
    }

    var providerSeparatorOpacity: Double {
        switch self {
        case .full, .compact:
            0.2
        case .condensed, .minimal:
            0.12
        }
    }

    var windowSeparator: String {
        switch self {
        case .full, .compact:
            "|"
        case .condensed, .minimal:
            "/"
        }
    }

    var windowSeparatorOpacity: Double {
        switch self {
        case .full, .compact:
            0.16
        case .condensed, .minimal:
            0.28
        }
    }
}

private struct OpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightLaneWidth: CGFloat
}

// MARK: - Session row (opened state)

private struct IslandSessionRow: View {
    let session: AgentSession
    let referenceDate: Date
    var isActionable: Bool = false
    var isKeyboardSelected: Bool = false
    var isKeyboardReplyFocused: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    var lang: LanguageManager = .shared
    var onApprove: ((ApprovalAction) -> Void)?
    var onAnswer: ((QuestionPromptResponse) -> Void)?
    var onReply: ((String) -> Void)?
    var onCancelReply: (() -> Void)?
    var contextUsage: ContextUsage? = nil
    var gitSnapshot: GitWorkspaceSnapshot? = nil
    var planState: PlanState? = nil
    var onTogglePlanStep: ((String) -> Void)? = nil
    var showsToolBadge: Bool = true
    var showsTerminalBadge: Bool = true
    var showsGitBranchBadge: Bool = true
    var showsGitDiffBadge: Bool = true
    var showsContextBadge: Bool = true
    var showsAgeBadge: Bool = true
    var themePalette: ThemePalette = .mocha
    var streamSafeTextEnabled: Bool = false
    var isManuallyExpanded: Bool = false
    var onManualExpansionChange: ((Bool) -> Void)?
    @State private var planExpanded: Bool = false
    let onJump: () -> Void
    var onDismiss: (() -> Void)?

    @State private var isHighlighted = false
    @State private var replyText: String = ""

    var body: some View {
        rowBody(referenceDate: referenceDate)
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let presence = (rawPresence == .inactive && isManuallyExpanded) ? .active : rawPresence
        let showsExpandedContent = presence != .inactive
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(streamSafe(session.spotlightHeadlineText))
                            .font(.system(size: isActionable ? 15 : 14, weight: .semibold))
                            .foregroundStyle(headlineColor(for: presence))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            if showsToolBadge {
                                compactBadge(session.tool.displayName, presence: presence,
                                             tint: BadgeColors.agent(session.tool, palette: themePalette).opacity(presence == .inactive ? 0.4 : 1.0))
                            }
                            if showsTerminalBadge, session.isRemote {
                                compactBadge("SSH", presence: presence)
                            }
                            if showsTerminalBadge, let terminalBadge = session.spotlightTerminalBadge {
                                compactBadge(terminalBadge, presence: presence,
                                             tint: BadgeColors.terminal(terminalBadge, palette: themePalette).opacity(presence == .inactive ? 0.4 : 1.0))
                            }
                            if let gitSnapshot {
                                if showsGitBranchBadge {
                                    gitBranchBadge(gitSnapshot, presence: presence)
                                }
                                if showsGitDiffBadge {
                                    gitDiffBadge(gitSnapshot, presence: presence)
                                }
                            }
                            if showsContextBadge, presence != .inactive, let usage = contextUsage {
                                ContextLeftBadge(usage: usage, palette: themePalette)
                            }
                            if showsAgeBadge {
                                compactBadge(session.spotlightAgeBadge, presence: presence)
                            }
                            if let onDismiss {
                                DismissButton(action: onDismiss)
                            }
                        }
                    }

                    if showsExpandedContent || isActionable,
                       let promptLine = session.spotlightPromptLineText ?? expandedPromptLineText {
                        Text(streamSafe(promptLine))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.62))
                            .lineLimit(1)
                    }

                    if showsExpandedContent || isActionable,
                       let activityLine = session.spotlightActivityLineText ?? expandedActivityLineText {
                        Text(streamSafe(activityLine))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activityColor(for: presence).opacity(0.94))
                            .lineLimit(1)
                    }

                    if let planState, session.phase != .waitingForApproval {
                        planDisclosure(state: streamSafe(planState))
                    }

                    if showsExpandedContent,
                       let subagents = session.claudeMetadata?.activeSubagents,
                       !subagents.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9, weight: .medium))
                                Text(lang.t("subagents.title", subagents.count))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(themePalette.sky.swiftUIColor.opacity(0.8))

                            ForEach(subagents, id: \.agentID) { sub in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(sub.summary != nil
                                            ? themePalette.green.swiftUIColor
                                            : themePalette.blue.swiftUIColor)
                                        .frame(width: 6, height: 6)
                                    Text(streamSafe(sub.agentType ?? sub.agentID))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.8))
                                        .lineLimit(1)
                                    if let desc = sub.taskDescription {
                                        Text("(\(streamSafe(desc)))")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if sub.summary != nil {
                                        Text(lang.t("subagents.completed"))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.4))
                                    } else if let started = sub.startedAt {
                                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                            Text(subagentElapsed(since: started, at: timeline.date))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.4))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if showsExpandedContent,
                       let tasks = session.claudeMetadata?.activeTasks,
                       !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(taskSummary(tasks))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.45))
                            ForEach(tasks) { task in
                                HStack(spacing: 5) {
                                    taskStatusIcon(task.status)
                                    Text(streamSafe(task.title))
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(task.status == .completed
                                            ? themePalette.text.swiftUIColor.opacity(0.4)
                                            : themePalette.text.swiftUIColor.opacity(0.7))
                                        .strikethrough(task.status == .completed)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, isActionable ? 16 : 16)
            .padding(.vertical, isActionable ? 14 : 14)

            if isActionable {
                actionableBody
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .fill(isVisuallySelected ? themePalette.text.swiftUIColor.opacity(isActionable ? 0.07 : 0.055) : themePalette.crust.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous)
                .strokeBorder(actionableBorderColor)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.24), radius: isVisuallySelected ? 8 : 0, y: isVisuallySelected ? 6 : 0)
        .overlay(
            Group {
                if !isActionable {
                    Rectangle()
                        .fill(Color.white.opacity(isVisuallySelected ? 0 : 0.02))
                        .frame(height: 1)
                }
            },
            alignment: .bottom
        )
        .modifier(ConditionalDrawingGroup(enabled: useDrawingGroup && !isActionable))
        .contentShape(RoundedRectangle(cornerRadius: isActionable ? 24 : 22, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .animation(.easeInOut(duration: 0.15), value: isKeyboardSelected)
        .animation(.easeInOut(duration: 0.15), value: isKeyboardReplyFocused)
        .onTapGesture(perform: handlePrimaryTap)
        .onHover { hovering in
            guard isInteractive else { return }
            isHighlighted = hovering
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                onManualExpansionChange?(false)
            }
        }
    }

    private var actionableBorderColor: Color {
        if isKeyboardReplyFocused {
            return themePalette.sky.swiftUIColor.opacity(0.66)
        }
        if isKeyboardSelected {
            return themePalette.blue.swiftUIColor.opacity(0.52)
        }
        if isActionable {
            return actionableStatusTint.opacity(isHighlighted ? 0.45 : 0.28)
        }
        return isHighlighted ? themePalette.text.swiftUIColor.opacity(0.24) : themePalette.text.swiftUIColor.opacity(0.04)
    }

    private var isVisuallySelected: Bool {
        isHighlighted || isKeyboardSelected || isKeyboardReplyFocused
    }

    private var actionableStatusTint: Color {
        switch session.phase {
        case .waitingForApproval:
            themePalette.role(.attention).swiftUIColor
        case .waitingForAnswer:
            themePalette.role(.question).swiftUIColor
        case .running:
            themePalette.blue.swiftUIColor
        case .completed:
            themePalette.green.swiftUIColor
        }
    }

    /// Inline diff to show in the approval card, or nil when the requested
    /// tool isn't a recognized file mutator (Edit / Write / MultiEdit /
    /// apply_patch). When nil, the card falls back to the legacy
    /// command-preview block.
    private var approvalToolDiff: ToolDiff? {
        ToolDiffExtractor.diff(
            toolName: session.permissionRequest?.toolName,
            toolInput: session.permissionRequest?.toolInput
        )
    }

    /// Pre-approval plan checklist parsed from the active tool input.
    /// Recognizes both the native ExitPlanMode flow and skill-driven
    /// plan writes (brainstorming + writing-plans skills writing
    /// `docs/plans/*.md`); otherwise nil and the regular approval body
    /// renders.
    private var approvalPlanState: PlanState? {
        guard let toolName = session.permissionRequest?.toolName,
              case let .object(fields) = session.permissionRequest?.toolInput ?? .null else {
            return nil
        }

        let planMarkdown: String?
        switch toolName {
        case "ExitPlanMode":
            planMarkdown = stringValue(in: fields, key: "plan")
        case "Write":
            guard let path = stringValue(in: fields, key: "file_path"),
                  PlanFilePathClassifier.looksLikePlan(path) else {
                return nil
            }
            planMarkdown = stringValue(in: fields, key: "content")
        default:
            return nil
        }

        guard let planMarkdown else { return nil }
        let steps = PlanModeParser.parse(planMarkdown)
        guard !steps.isEmpty else { return nil }
        return PlanState(steps: steps, rawMarkdown: planMarkdown)
    }

    private func stringValue(in fields: [String: CodexHookJSONValue], key: String) -> String? {
        if case let .string(value) = fields[key] ?? .null {
            return value
        }
        return nil
    }

    /// Compact plan-progress button that expands into a full interactive
    /// checklist when tapped. Visible during the running/completed phases
    /// (after the user has approved the plan); the pre-approval body
    /// renders the same data as a read-only review block instead.
    @ViewBuilder
    private func planDisclosure(state: PlanState) -> some View {
        let total = state.steps.count
        let checked = state.checkedIDs.count

        VStack(alignment: .leading, spacing: 6) {
            Button {
                planExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: planExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 10))
                    Text("Plan (\(checked)/\(total))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(checked == total && total > 0
                    ? themePalette.role(.completion).swiftUIColor.opacity(0.92)
                    : themePalette.text.swiftUIColor.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(themePalette.surface0.swiftUIColor, in: Capsule())
            }
            .buttonStyle(.plain)

            if planExpanded {
                PlanMarkdownView(
                    rawMarkdown: state.rawMarkdown,
                    palette: themePalette,
                    emptyMessage: lang.t("island.plan.empty")
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themePalette.crust.swiftUIColor.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(themePalette.text.swiftUIColor.opacity(0.06))
                )
            }
        }
    }

    @ViewBuilder
    private var actionableBody: some View {
        switch session.phase {
        case .waitingForApproval:
            approvalActionBody
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            EmptyView()
        }
    }

    // MARK: - Approval action area

    private var approvalActionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(themePalette.role(.attention).swiftUIColor)
                Text(commandLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(themePalette.role(.attention).swiftUIColor)
            }

            if let planState = approvalPlanState {
                planApprovalBody(streamSafe(planState))
            } else if let toolDiff = approvalToolDiff {
                if streamSafeTextEnabled {
                    LiveCodingDiffSummaryView(diff: streamSafe(toolDiff), palette: themePalette, lang: lang)
                } else {
                    InlineDiffView(diff: toolDiff, palette: themePalette)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(streamSafe(commandPreviewText))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if let path = session.permissionRequest?.affectedPath.trimmedForNotificationCard,
                       !path.isEmpty {
                        Text(streamSafe(path))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.42))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themePalette.surface0.swiftUIColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(themePalette.role(.attention).swiftUIColor.opacity(0.18))
                )
            }

            HStack(spacing: 8) {
                Button("No") { onApprove?(.deny) }
                    .buttonStyle(IslandWideButtonStyle(kind: .secondary, palette: themePalette))
                Button("Yes") { onApprove?(.allowOnce) }
                    .buttonStyle(IslandWideButtonStyle(kind: .warning, palette: themePalette))
                if let toolName = session.permissionRequest?.toolName {
                    Button("Always Allow (\(toolName))") {
                        let rule = ClaudePermissionRuleValue(toolName: toolName)
                        let update = ClaudePermissionUpdate.addRules(
                            destination: .session,
                            rules: [rule],
                            behavior: .allow
                        )
                        onApprove?(.allowWithUpdates([update]))
                    }
                    .buttonStyle(IslandWideButtonStyle(kind: .danger, palette: themePalette))
                }
            }

            if onReply != nil {
                replyFallbackInput
            }
        }
    }

    /// Pre-approval plan body — read-only checklist showing the plan
    /// structure so the user can scan it before approving. Once approved
    /// (state moves out of waitingForApproval), the same plan reappears
    /// as an interactive checklist via the row's plan disclosure.
    private func planApprovalBody(_ state: PlanState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.65))
                Text("Plan (\(state.steps.count) steps)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.75))
            }

            AutoHeightScrollView(maxHeight: 240) {
                PlanChecklistView(state: state, interactive: false, paletteOverride: themePalette)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(themePalette.crust.swiftUIColor.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(themePalette.text.swiftUIColor.opacity(0.06))
        )
    }

    // MARK: - Question action area

    private var questionActionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            StructuredQuestionPromptView(
                prompt: session.questionPrompt,
                lang: lang,
                palette: themePalette,
                streamSafeTextEnabled: streamSafeTextEnabled,
                onAnswer: { onAnswer?($0) }
            )

            if onReply != nil {
                replyFallbackInput
            }
        }
    }

    /// Free-text reply input shown alongside structured approve / answer
    /// flows for `.waitingForApproval` and `.waitingForAnswer`. The
    /// structured flows cover the common path (Yes/No, AskUserQuestion
    /// options); this input is the universal fallback for any other prompt
    /// shape, since text injection through the host terminal types the
    /// answer as if the user typed it directly.
    private var replyFallbackInput: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                // 1px stroke — palette.text.opacity(0.04) is invisible.
                .fill(.white.opacity(0.04))
                .frame(height: 1)
            completionReplyInput
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // Below the perceptible-tint threshold (≤0.04) — palette.text would
                // vanish here on dark themes; kept as Color.white literal.
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(themePalette.text.swiftUIColor.opacity(0.06))
        )
    }

    // MARK: - Completion action area

    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(streamSafe(completionPromptLabel))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.8))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(lang.t("completion.done"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(themePalette.role(.completion).swiftUIColor.opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                // 1px stroke — palette.text.opacity(0.04) is invisible.
                .fill(.white.opacity(0.04))
                .frame(height: 1)

            AutoHeightScrollView(maxHeight: 260) {
                Markdown(streamSafe(completionMessageText))
                    .markdownTheme(.completionCard(themePalette))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if onReply != nil {
                Rectangle()
                    // 1px stroke — palette.text.opacity(0.04) is invisible.
                    .fill(.white.opacity(0.04))
                    .frame(height: 1)

                completionReplyInput
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(themePalette.crust.swiftUIColor.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(themePalette.text.swiftUIColor.opacity(0.08))
        )
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder"),
                text: $replyText,
                isFocused: isKeyboardReplyFocused,
                onSubmit: { submitReply() },
                onCancel: { onCancelReply?() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? themePalette.text.swiftUIColor.opacity(0.2) : themePalette.text.swiftUIColor.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @discardableResult
    private func submitReply() -> Bool {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        replyText = ""
        onReply?(text)
        return true
    }

    // MARK: - Actionable helpers

    private var completionPromptLabel: String {
        if let prompt = session.latestUserPromptText?.trimmedForNotificationCard, !prompt.isEmpty {
            return "You: \(prompt)"
        }
        return "You:"
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForNotificationCard, !text.isEmpty {
            return text
        }
        return session.summary
    }

    private var commandLabel: String {
        switch session.currentToolName {
        case "exec_command", "Bash": return "Bash"
        case "AskUserQuestion": return "Question"
        case "ExitPlanMode": return "Plan"
        case "apply_patch": return "Patch"
        case "write_stdin": return "Input"
        case let value?: return value.capitalized
        case nil: return "Command"
        }
    }

    private var commandPreviewText: String {
        let preview = session.currentCommandPreviewText?.trimmedForNotificationCard
        if let preview, !preview.isEmpty {
            return "$ \(preview)"
        }
        return session.permissionRequest?.summary.trimmedForNotificationCard ?? session.summary.trimmedForNotificationCard
    }

    private func streamSafe(_ text: String) -> String {
        streamSafeTextEnabled ? LiveCodingRedactor.redact(text) : text
    }

    private func streamSafe(_ diff: ToolDiff) -> ToolDiff {
        guard streamSafeTextEnabled else { return diff }
        return ToolDiff(
            filePath: LiveCodingRedactor.redact(diff.filePath),
            lines: diff.lines.map { line in
                switch line {
                case let .context(text):
                    return .context(LiveCodingRedactor.redact(text))
                case let .add(text):
                    return .add(LiveCodingRedactor.redact(text))
                case let .remove(text):
                    return .remove(LiveCodingRedactor.redact(text))
                }
            },
            additionCount: diff.additionCount,
            removalCount: diff.removalCount,
            truncated: diff.truncated
        )
    }

    private func streamSafe(_ state: PlanState) -> PlanState {
        guard streamSafeTextEnabled else { return state }
        return PlanState(
            steps: state.steps.map { step in
                PlanStep(
                    id: step.id,
                    title: LiveCodingRedactor.redact(step.title),
                    depth: step.depth
                )
            },
            checkedIDs: state.checkedIDs,
            capturedAt: state.capturedAt,
            rawMarkdown: LiveCodingRedactor.redact(state.rawMarkdown)
        )
    }


    private func subagentElapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    private func taskSummary(_ tasks: [ClaudeTaskInfo]) -> String {
        let done = tasks.filter { $0.status == .completed }.count
        let prog = tasks.filter { $0.status == .inProgress }.count
        let pend = tasks.filter { $0.status == .pending }.count
        return lang.t("tasks.summary", done, prog, pend)
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 9))
                .foregroundStyle(themePalette.text.swiftUIColor.opacity(0.35))
        case .inProgress:
            Circle()
                .fill(themePalette.blue.swiftUIColor)
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(themePalette.text.swiftUIColor.opacity(0.3), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }

    /// Prompt line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedPromptLineText: String? {
        guard isManuallyExpanded, let prompt = session.spotlightPromptText else { return nil }
        return "You: \(prompt)"
    }

    /// Activity line for manually expanded inactive rows (bypasses time-based filter).
    private var expandedActivityLineText: String? {
        guard isManuallyExpanded else { return nil }
        let trimmed = session.lastAssistantMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assistantMessage = trimmed, !assistantMessage.isEmpty {
            return assistantMessage
        }
        return session.jumpTarget != nil ? "Ready" : "Completed"
    }

    private func handlePrimaryTap() {
        let rawPresence = session.islandPresence(at: referenceDate)
        if rawPresence == .inactive && !isManuallyExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                onManualExpansionChange?(true)
            }
        } else {
            onJump()
        }
    }

    private func compactBadge(
        _ title: String,
        presence: IslandSessionPresence,
        tint: Color? = nil
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint ?? badgeTextColor(for: presence))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(themePalette.surface0.swiftUIColor, in: Capsule())
    }

    private func gitBranchBadge(
        _ snapshot: GitWorkspaceSnapshot,
        presence: IslandSessionPresence
    ) -> some View {
        compactBadge(
            shortBranchName(snapshot.branchName),
            presence: presence,
            tint: themePalette.mauve.swiftUIColor.opacity(presence == .inactive ? 0.42 : 0.88)
        )
    }

    @ViewBuilder
    private func gitDiffBadge(
        _ snapshot: GitWorkspaceSnapshot,
        presence: IslandSessionPresence
    ) -> some View {
        if snapshot.additions == 0, snapshot.removals == 0 {
            compactBadge(
                snapshot.isDirty ? "\(snapshot.changedFileCount)" : "clean",
                presence: presence,
                tint: themePalette.text.swiftUIColor.opacity(presence == .inactive ? 0.34 : 0.48)
            )
        } else {
            let inactiveOpacity = presence == .inactive ? 0.48 : 0.95
            HStack(spacing: 5) {
                if snapshot.additions > 0 {
                    Text("+\(snapshot.additions)")
                        .foregroundStyle(themePalette.green.swiftUIColor.opacity(inactiveOpacity))
                }
                if snapshot.removals > 0 {
                    Text("-\(snapshot.removals)")
                        .foregroundStyle(themePalette.red.swiftUIColor.opacity(inactiveOpacity))
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(themePalette.surface0.swiftUIColor, in: Capsule())
        }
    }

    private func shortBranchName(_ branchName: String) -> String {
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return "\(trimmed.prefix(15))..."
    }

    private func headlineColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? themePalette.text.swiftUIColor.opacity(0.78) : themePalette.text.swiftUIColor
    }

    private func badgeTextColor(for presence: IslandSessionPresence) -> Color {
        presence == .inactive ? themePalette.text.swiftUIColor.opacity(0.42) : themePalette.text.swiftUIColor.opacity(0.56)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        if session.phase == .waitingForApproval {
            return themePalette.role(.attention).swiftUIColor.opacity(0.94)
        }

        if session.phase == .waitingForAnswer {
            return themePalette.role(.question).swiftUIColor.opacity(0.96)
        }

        switch presence {
        case .running:
            return themePalette.blue.swiftUIColor
        case .active:
            return themePalette.green.swiftUIColor
        case .inactive:
            return themePalette.text.swiftUIColor.opacity(0.38)
        }
    }

    private func activityColor(for presence: IslandSessionPresence) -> Color {
        switch session.spotlightActivityTone {
        case .attention:
            themePalette.role(.attention).swiftUIColor.opacity(0.94)
        case .live:
            statusTint(for: presence)
        case .idle:
            themePalette.text.swiftUIColor.opacity(0.46)
        case .ready:
            presence == .inactive ? themePalette.text.swiftUIColor.opacity(0.46) : statusTint(for: presence)
        }
    }
}

private struct LiveCodingDiffSummaryView: View {
    let diff: ToolDiff
    var palette: ThemePalette
    var lang: LanguageManager = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.role(.attention).swiftUIColor)
                Text(lang.t("liveCoding.diffHidden"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text.swiftUIColor.opacity(0.86))
            }

            Text(diff.filePath)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.text.swiftUIColor.opacity(0.6))
                .lineLimit(1)

            Text(lang.t("liveCoding.diffSummary", diff.additionCount, diff.removalCount))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text.swiftUIColor.opacity(0.62))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface0.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.role(.attention).swiftUIColor.opacity(0.18))
        )
    }
}

private struct StructuredQuestionPromptView: View {
    let prompt: QuestionPrompt?
    var lang: LanguageManager = .shared
    var palette: ThemePalette? = nil
    var streamSafeTextEnabled: Bool = false
    let onAnswer: (QuestionPromptResponse) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var freeformTexts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptTitle {
                Text(streamSafe(promptTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle((palette ?? .mocha).role(.question).swiftUIColor.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(structuredQuestions, id: \.question) { question in
                    questionRow(question)
                }

                Button(lang.t("question.submit")) {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                }
                .buttonStyle(IslandWideButtonStyle(kind: .primary, palette: palette))
                .disabled(!hasCompleteSelection)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Below the perceptible-tint threshold (≤0.04) — palette.text would
                // vanish here on dark themes; kept as Color.white literal.
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder((palette ?? .mocha).text.swiftUIColor.opacity(0.06))
        )
    }

    // MARK: - Per-question row

    /// Renders a single question with its header, text, and vertical option list.
    @ViewBuilder
    private func questionRow(_ question: QuestionPromptItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if structuredQuestions.count > 1 {
                Text(streamSafe(question.header))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle((palette ?? .mocha).text.swiftUIColor.opacity(0.5))
            }

            Text(streamSafe(question.question))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle((palette ?? .mocha).text.swiftUIColor.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            // Vertical option list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(question.options) { option in
                    optionRow(option, question: question)
                }
            }
        }
    }

    // MARK: - Option row (vertical, CLI-style)

    @ViewBuilder
    private func optionRow(_ option: QuestionOption, question: QuestionPromptItem) -> some View {
        let isSelected = selectedLabels(for: question).contains(option.label)
        let showsFreeform = option.allowsFreeform && isSelected
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(option: option.label, for: question)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? (palette ?? .mocha).role(.question).swiftUIColor : (palette ?? .mocha).text.swiftUIColor.opacity(0.35))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(streamSafe(option.label))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle((palette ?? .mocha).text.swiftUIColor.opacity(isSelected ? 1 : 0.78))

                        if !option.description.isEmpty {
                            Text(streamSafe(option.description))
                                .font(.system(size: 10.5))
                                .foregroundStyle((palette ?? .mocha).text.swiftUIColor.opacity(0.4))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            if showsFreeform {
                Divider()
                    .overlay((palette ?? .mocha).text.swiftUIColor.opacity(0.08))
                freeformField(for: option, question: question)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? (palette ?? .mocha).role(.question).swiftUIColor.opacity(0.10) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? (palette ?? .mocha).role(.question).swiftUIColor.opacity(0.25) : .clear)
        )
    }

    @ViewBuilder
    private func freeformField(for option: QuestionOption, question: QuestionPromptItem) -> some View {
        let key = freeformKey(for: question, option: option)
        ReplyTextField(
            placeholder: lang.t("question.otherPlaceholder"),
            text: Binding(
                get: { freeformTexts[key] ?? "" },
                set: { freeformTexts[key] = $0 }
            ),
            onSubmit: {
                if hasCompleteSelection {
                    onAnswer(QuestionPromptResponse(answers: answerMap))
                    return true
                }
                return false
            }
        )
        .frame(height: 22)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    // MARK: - Helpers

    private var structuredQuestions: [QuestionPromptItem] {
        prompt?.questions ?? []
    }

    private var promptTitle: String {
        prompt?.title.trimmedForNotificationCard ?? lang.t("question.answerNeeded")
    }

    private var showsPromptTitle: Bool {
        guard !promptTitle.isEmpty else {
            return false
        }

        guard structuredQuestions.count == 1,
              let questionTitle = structuredQuestions.first?.question.trimmedForNotificationCard else {
            return true
        }

        return questionTitle.caseInsensitiveCompare(promptTitle) != .orderedSame
    }

    private var answerMap: [String: String] {
        Dictionary(uniqueKeysWithValues: structuredQuestions.compactMap { question in
            let values = resolvedAnswers(for: question)
            guard !values.isEmpty else {
                return nil
            }
            return (question.question, values.joined(separator: ", "))
        })
    }

    private var hasCompleteSelection: Bool {
        structuredQuestions.allSatisfy { question in
            let selected = selectedLabels(for: question)
            guard !selected.isEmpty else {
                return false
            }
            // When a freeform option is selected, require non-empty text.
            for option in question.options where option.allowsFreeform && selected.contains(option.label) {
                if trimmedFreeform(for: question, option: option).isEmpty {
                    return false
                }
            }
            return true
        }
    }

    private func selectedLabels(for question: QuestionPromptItem) -> Set<String> {
        selections[question.question] ?? []
    }

    private func resolvedAnswers(for question: QuestionPromptItem) -> [String] {
        let selected = selectedLabels(for: question)
        guard !selected.isEmpty else { return [] }

        let optionOrder = question.options
        var answers: [String] = []
        for option in optionOrder where selected.contains(option.label) {
            if option.allowsFreeform {
                let text = trimmedFreeform(for: question, option: option)
                answers.append(text.isEmpty ? option.label : text)
            } else {
                answers.append(option.label)
            }
        }
        return answers
    }

    private func freeformKey(for question: QuestionPromptItem, option: QuestionOption) -> String {
        "\(question.question)|\(option.label)"
    }

    private func trimmedFreeform(for question: QuestionPromptItem, option: QuestionOption) -> String {
        (freeformTexts[freeformKey(for: question, option: option)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(option: String, for question: QuestionPromptItem) {
        var selected = selections[question.question] ?? []

        if question.multiSelect {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        } else {
            if selected.contains(option) {
                selected.removeAll()
            } else {
                selected = [option]
            }
        }

        selections[question.question] = selected
    }

    private func streamSafe(_ text: String) -> String {
        streamSafeTextEnabled ? LiveCodingRedactor.redact(text) : text
    }
}

// MARK: - Reply TextField (NSTextField wrapper for IME-safe Enter handling)

/// NSTextField wrapper that fires `onSubmit` only when the IME composition
/// is finished — pressing Enter during Chinese/Japanese IME composition
/// confirms the candidate instead of submitting.
private struct ReplyTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isFocused: Bool = false
    var resignsOnSubmit: Bool = true
    var onSubmit: () -> Bool
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.resignsOnSubmit = resignsOnSubmit

        if isFocused,
           nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, resignsOnSubmit: resignsOnSubmit)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Bool
        var onCancel: (() -> Void)?
        var resignsOnSubmit: Bool

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Bool,
            onCancel: (() -> Void)?,
            resignsOnSubmit: Bool
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.resignsOnSubmit = resignsOnSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                if onSubmit(), resignsOnSubmit {
                    restoreNotchKeyboardFocus(from: control)
                }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel?()
                restoreNotchKeyboardFocus(from: control)
                return true
            }
            return false
        }

        private func restoreNotchKeyboardFocus(from control: NSControl) {
            var view: NSView? = control
            while let candidate = view {
                if let restorer = candidate as? NotchKeyboardFocusRestoring {
                    restorer.restoreNotchKeyboardFocus()
                    return
                }
                view = candidate.superview
            }
            control.window?.makeFirstResponder(nil)
        }
    }
}

private extension String {
    var trimmedForNotificationCard: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Compact button style

private struct IslandCompactButtonStyle: ButtonStyle {
    var tint: Color

    // ButtonStyle structs cannot read @Environment from caller —
    // SwiftUI passes only the Configuration. Palette must flow in via
    // a stored prop (see IslandWideButtonStyle.palette) or remain a
    // literal as here. See docs/plans/2026-05-06-theme-personalization-design.md.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .white.opacity(0.7) : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (tint == .secondary ? Color.white.opacity(0.08) : tint.opacity(0.15)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct IslandWideButtonStyle: ButtonStyle {
    // ButtonStyle structs cannot read @Environment from caller —
    // SwiftUI passes only the Configuration. Palette must flow in via
    // a stored prop (see IslandWideButtonStyle.palette) or remain a
    // literal as here. See docs/plans/2026-05-06-theme-personalization-design.md.
    enum Kind {
        case primary
        case secondary
        case warning
        case danger
    }

    let kind: Kind
    /// Optional palette injection — when present the button picks its
    /// background from `palette.blue/peach/red` so the Yes/No/Always
    /// Allow row reflects the active theme. When `nil` the button falls
    /// back to the original hard-coded values (kept for callers that
    /// don't yet route the palette through).
    var palette: ThemePalette? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor(configuration.isPressed), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .warning, .danger:
            return .white
        case .secondary:
            return .white.opacity(0.88)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        let pressedFactor: Double = isPressed ? 0.78 : 1.0
        if let palette {
            switch kind {
            case .primary:
                return palette.blue.swiftUIColor.opacity(pressedFactor)
            case .secondary:
                return palette.surface1.swiftUIColor.opacity(isPressed ? 0.7 : 0.9)
            case .warning:
                return palette.peach.swiftUIColor.opacity(pressedFactor)
            case .danger:
                return palette.red.swiftUIColor.opacity(pressedFactor)
            }
        }
        switch kind {
        case .primary:
            return Color(red: 0.26, green: 0.45, blue: 0.86).opacity(pressedFactor)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.16)
        case .warning:
            return Color(red: 0.85, green: 0.55, blue: 0.15).opacity(pressedFactor)
        case .danger:
            return Color(red: 0.82, green: 0.22, blue: 0.22).opacity(pressedFactor)
        }
    }
}

// MARK: - Closed count badge (right side of closed notch)

struct ClosedCountBadge: View {
    let liveCount: Int
    let tint: Color

    @Environment(\.themePalette) private var palette

    var body: some View {
        Text("\(liveCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(palette.surface0.swiftUIColor, in: Capsule())
    }
}

// MARK: - Central activity overlay (external-display only)

/// Renders the focus session's current tool call inside the central black
/// rectangle of the closed island. The notch on built-in displays physically
/// covers this area, so we gate rendering on `placementMode == .topBar`.
///
/// State machine: while a tool is active the label tracks it live. When the
/// tool clears (PostToolUse fires or metadata drops the field), the last
/// value lingers for `fadeDelay` then disappears.
private struct CentralActivityLabel: View {
    let toolName: String?
    let preview: String?
    let isVisible: Bool

    @State private var displayed: DisplayedActivity?
    @Environment(\.themePalette) private var palette

    private static let fadeDelay: Duration = .seconds(2)

    struct DisplayedActivity: Equatable {
        var tool: String
        var preview: String?
    }

    var body: some View {
        Group {
            if isVisible, let displayed {
                HStack(spacing: 4) {
                    Image(systemName: Self.icon(for: displayed.tool))
                        .font(.system(size: 9, weight: .semibold))
                    Text(Self.label(for: displayed))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(palette.text.swiftUIColor.opacity(0.85))
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: displayed)
        .onChange(of: trackingKey, initial: true) { _, _ in
            sync()
        }
        .task(id: clearTaskID) {
            guard toolName == nil, displayed != nil else { return }
            do {
                try await Task.sleep(for: Self.fadeDelay)
                displayed = nil
            } catch {
                // cancelled — a new tool arrived, let sync() handle it
            }
        }
    }

    /// Composite key so `.onChange` fires on either tool or preview change.
    private var trackingKey: String {
        "\(toolName ?? "")|\(preview ?? "")"
    }

    /// Key used to (re)start the clear timer. Changes whenever we transition
    /// between active/idle so `.task(id:)` cancels and restarts cleanly.
    private var clearTaskID: String {
        toolName == nil ? "clearing-\(displayed?.tool ?? "")" : "active-\(toolName ?? "")"
    }

    private func sync() {
        if let toolName, !toolName.isEmpty {
            displayed = DisplayedActivity(tool: toolName, preview: preview)
        }
    }

    private static func label(for activity: DisplayedActivity) -> String {
        if let preview = activity.preview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return "\(activity.tool) · \(preview)"
        }
        return activity.tool
    }

    private static func icon(for tool: String) -> String {
        let lower = tool.lowercased()
        if lower.contains("grep") || lower.contains("search") || lower.contains("glob") {
            return "magnifyingglass"
        }
        if lower.contains("edit") || lower.contains("write") {
            return "pencil"
        }
        if lower.contains("bash") || lower.contains("shell") || lower.contains("exec") || lower.contains("run") {
            return "terminal"
        }
        if lower.contains("read") {
            return "doc.text"
        }
        if lower.contains("web") || lower.contains("fetch") {
            return "globe"
        }
        if lower.contains("task") || lower.contains("agent") || lower.contains("subagent") {
            return "sparkles"
        }
        return "wrench.and.screwdriver"
    }
}

// MARK: - Menu bar content (unchanged)

struct MenuBarContentView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.lang.t("app.name.oss"))
                .font(.headline)
            Text(model.lang.t("menu.status", model.liveSessionCount, model.liveAttentionCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button(model.lang.t("menu.settings")) {
                model.showSettings()
            }

            #if DEBUG
            Button(model.lang.t("menu.openDebug")) {
                model.showControlCenter()
            }
            #endif

            Text(model.acceptanceStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.acceptanceStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(model.isOverlayVisible ? model.lang.t("menu.hideOverlay") : model.lang.t("menu.showOverlay")) {
                model.toggleOverlay()
            }

            Divider()

            Text(model.codexHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.codexHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.lang.t("menu.refreshCodexHooks")) {
                model.refreshCodexHookStatus()
            }

            if model.codexHooksInstalled {
                Button(model.lang.t("menu.uninstallCodexHooks")) {
                    model.uninstallCodexHooks()
                }
            } else {
                Button(model.lang.t("menu.installCodexHooks")) {
                    model.installCodexHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            Divider()

            Text(model.claudeHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.claudeHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.lang.t("menu.refreshClaudeHooks")) {
                model.refreshClaudeHookStatus()
            }

            if model.claudeHooksInstalled {
                Button(model.lang.t("menu.uninstallClaudeHooks")) {
                    model.uninstallClaudeHooks()
                }
            } else {
                Button(model.lang.t("menu.installClaudeHooks")) {
                    model.installClaudeHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            if let session = model.focusedSession {
                Divider()
                Text(streamSafe(session.title))
                    .font(.subheadline.weight(.semibold))
                Text(streamSafe(session.spotlightPrimaryText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let currentTool = session.spotlightCurrentToolLabel {
                    Text(model.lang.t("menu.liveTool", streamSafe(currentTool)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trackingLabel = session.spotlightTrackingLabel {
                    Text(model.lang.t("menu.tracking", streamSafe(trackingLabel)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func streamSafe(_ text: String) -> String {
        model.liveCodingModeEnabled ? LiveCodingRedactor.redact(text) : text
    }
}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    @MainActor static func completionCard(_ palette: ThemePalette) -> Theme {
        let text = palette.text.swiftUIColor
        let surface = palette.surface0.swiftUIColor
        let link = palette.role(.working).swiftUIColor
        return Theme()
            .text {
                ForegroundColor(text.opacity(0.88))
                FontSize(13.5)
                FontWeight(.medium)
            }
            .link {
                ForegroundColor(link)
            }
            .strong {
                FontWeight(.bold)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12.5)
                ForegroundColor(text.opacity(0.88))
                BackgroundColor(surface.opacity(0.8))
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12.5)
                        ForegroundColor(text.opacity(0.88))
                    }
                    .padding(10)
                    .background(surface.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(16)
                        FontWeight(.bold)
                        ForegroundColor(text.opacity(0.88))
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(15)
                        FontWeight(.bold)
                        ForegroundColor(text.opacity(0.88))
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(14)
                        FontWeight(.semibold)
                        ForegroundColor(text.opacity(0.88))
                    }
                    .markdownMargin(top: 6, bottom: 2)
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(text.opacity(0.6))
                        FontSize(13.5)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(text.opacity(0.2))
                            .frame(width: 3)
                    }
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 2, bottom: 2)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(.allBorders, color: text.opacity(0.15), strokeStyle: .init(lineWidth: 1)))
                    .markdownTableBackgroundStyle(
                        // .white.opacity(0.04) kept as exception (at/below threshold)
                        .alternatingRows(Color.white.opacity(0.04), surface.opacity(0.6))
                    )
                    .markdownMargin(top: 4, bottom: 8)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .relativeLineSpacing(.em(0.25))
            }
    }
}

private struct DismissButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.text.swiftUIColor.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
