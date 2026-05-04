import SwiftUI
import OpenIslandCore

struct ContextLeftBadge: View {
    let usage: ContextUsage
    var palette: ThemePalette = .mocha

    static let barWidth: CGFloat = 18
    static let barHeight: CGFloat = 4

    enum FillColor: Equatable {
        case green, yellow, orange, red
    }

    var body: some View {
        if usage.percentLeft < 1 {
            Circle()
                .fill(palette.red.swiftUIColor)
                .frame(width: 6, height: 6)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(palette.surface0.swiftUIColor.opacity(0.4), in: Capsule())
                .accessibilityLabel("\(Int(usage.percentUsed.rounded()))% context used")
                .allowsHitTesting(false)
        } else {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.surface1.swiftUIColor.opacity(0.6))
                        .frame(width: Self.barWidth, height: Self.barHeight)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(swiftUIColor(for: fillColor))
                        .frame(width: fillWidth, height: Self.barHeight)
                }
                Text("\(Int(usage.percentUsed.rounded()))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.subtext0.swiftUIColor)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(palette.surface0.swiftUIColor.opacity(0.4), in: Capsule())
            .accessibilityLabel("\(Int(usage.percentUsed.rounded()))% context used")
            .allowsHitTesting(false)
        }
    }

    var fillWidth: CGFloat {
        let used = max(0, min(100, usage.percentUsed))
        let raw = Self.barWidth * CGFloat(used / 100)
        return used > 0 ? max(2, raw) : 0
    }

    var fillColor: FillColor {
        let left = usage.percentLeft
        if left > 50 { return .green }
        if left > 20 { return .yellow }
        if left > 10 { return .orange }
        return .red
    }

    private func swiftUIColor(for fill: FillColor) -> Color {
        switch fill {
        case .green:  return palette.green.swiftUIColor
        case .yellow: return palette.yellow.swiftUIColor
        case .orange: return palette.peach.swiftUIColor
        case .red:    return palette.red.swiftUIColor
        }
    }
}
