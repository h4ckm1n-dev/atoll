import SwiftUI
import AppKit

struct IslandPixelGlyph: View {
    var tint: Color
    var style: IslandPixelShapeStyle
    var isAnimating: Bool
    var width: CGFloat = 26
    var height: CGFloat = 14
    var customAvatarImage: NSImage? = nil

    @ViewBuilder
    var body: some View {
        if style == .custom, let avatar = customAvatarImage {
            Image(nsImage: avatar)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: min(width, height), height: min(width, height))
                .clipShape(Circle())
        } else if style == .bars || style == .custom {
            OpenIslandBrandMark(
                size: min(width, height),
                tint: tint,
                isAnimating: isAnimating,
                style: .duotone
            )
            .frame(width: width, height: height)
        } else if style.usesChartFrames {
            TimelineView(.animation(minimumInterval: 0.18, paused: !isAnimating)) { context in
                let frame = style.chartFrames[frameIndex(for: context.date, frameCount: style.chartFrames.count)]

                HStack(alignment: .bottom, spacing: 3) {
                    PixelColumnCluster(heights: frame.0, tint: tint)
                    PixelColumnCluster(heights: frame.1, tint: tint)
                }
                .frame(width: width, height: height, alignment: .bottomLeading)
            }
        } else {
            TimelineView(.animation(minimumInterval: 0.12, paused: !isAnimating)) { context in
                let phase = phase(for: context.date)

                switch style {
                case .matrix:
                    MatrixRainGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .glitch:
                    GlitchGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .visor:
                    NeonVisorGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .terminal:
                    TerminalCursorGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .manga:
                    MangaBurstGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .blade:
                    BladeGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .cyber:
                    CyberCircuitGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .waveform:
                    WaveformGlyph(tint: tint, phase: phase)
                        .frame(width: width, height: height)
                case .bars, .steps, .blocks, .custom:
                    EmptyView()
                }
            }
        }
    }

    private func frameIndex(for date: Date, frameCount: Int) -> Int {
        guard isAnimating else { return 0 }
        let ticks = Int(date.timeIntervalSinceReferenceDate / 0.18)
        return ticks % max(frameCount, 1)
    }

    private func phase(for date: Date) -> Double {
        guard isAnimating else { return 0 }
        return date.timeIntervalSinceReferenceDate
    }
}

extension IslandPixelShapeStyle {
    fileprivate var usesChartFrames: Bool {
        switch self {
        case .steps, .blocks:
            true
        case .bars, .matrix, .glitch, .visor, .terminal, .manga, .blade, .cyber, .waveform, .custom:
            false
        }
    }

    fileprivate var chartFrames: [([Int], [Int])] {
        switch self {
        case .bars:
            [([1, 3, 2, 1], [2, 3, 1]),
             ([2, 2, 3, 1], [1, 2, 3]),
             ([1, 2, 1, 3], [3, 1, 2]),
             ([3, 1, 2, 2], [2, 3, 1])]
        case .steps:
            [([1, 2, 3, 4], [1, 2, 3]),
             ([2, 3, 4, 3], [2, 3, 2]),
             ([1, 2, 3, 4], [3, 2, 1]),
             ([2, 3, 2, 1], [2, 3, 4])]
        case .blocks:
            [([2, 4, 4, 2], [2, 4, 2]),
             ([3, 4, 3, 2], [3, 4, 2]),
             ([2, 3, 4, 3], [2, 4, 3]),
             ([2, 4, 3, 2], [3, 4, 2])]
        case .matrix, .glitch, .visor, .terminal, .manga, .blade, .cyber, .waveform, .custom:
            [([1, 3, 2, 1], [2, 3, 1])]
        }
    }
}

private struct PixelColumnCluster: View {
    let heights: [Int]
    let tint: Color

    private let rows = 4
    private let pixelSize: CGFloat = 2.4
    private let pixelSpacing: CGFloat = 1.1

    var body: some View {
        HStack(alignment: .bottom, spacing: pixelSpacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { columnIndex, height in
                VStack(spacing: pixelSpacing) {
                    ForEach((0..<rows).reversed(), id: \.self) { row in
                        RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                            .fill(row < height ? tint.opacity(0.45 + Double(row + 1) / Double(max(height, 1)) * 0.5) : .clear)
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
                .opacity(columnIndex == heights.count - 1 ? 0.86 : 1)
            }
        }
        .shadow(color: tint.opacity(0.55), radius: 2.2, x: 0, y: 0)
    }
}

private struct MatrixRainGlyph: View {
    let tint: Color
    let phase: Double

    private let rows = 4
    private let columns = 7

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.4) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 1.1) {
                    ForEach(0..<rows, id: \.self) { row in
                        let head = (Int(phase * 7) + column * 2) % rows
                        let distance = abs(row - head)
                        RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                            .fill(tint.opacity(distance == 0 ? 0.95 : (distance == 1 ? 0.55 : 0.18)))
                            .frame(width: 2.1, height: 2.1)
                    }
                }
            }
        }
        .shadow(color: tint.opacity(0.6), radius: 2.5)
    }
}

private struct GlitchGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                let tick = Int(phase * 12) + index
                Capsule(style: .continuous)
                    .fill(tint.opacity(index == 1 ? 0.95 : 0.48))
                    .frame(width: CGFloat([18, 24, 13, 20][index]), height: index == 1 ? 2.8 : 2.2)
                    .offset(x: CGFloat((tick % 3) - 1) * CGFloat(index + 1))
            }
        }
        .overlay(alignment: .topTrailing) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(width: 9, height: 1.5)
                .offset(x: CGFloat(Int(phase * 16) % 5) - 2, y: 1)
        }
        .shadow(color: tint.opacity(0.55), radius: 2)
    }
}

private struct NeonVisorGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scanX = CGFloat((sin(phase * 2.8) + 1) / 2) * max(0, size.width - 4) + 2

            ZStack {
                RoundedRectangle(cornerRadius: size.height * 0.45, style: .continuous)
                    .strokeBorder(tint.opacity(0.72), lineWidth: 1.4)

                Capsule(style: .continuous)
                    .fill(tint.opacity(0.38))
                    .frame(width: size.width * 0.58, height: 2)

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.74))
                    .frame(width: 1.5, height: size.height * 0.62)
                    .position(x: scanX, y: size.height / 2)
            }
        }
        .shadow(color: tint.opacity(0.65), radius: 2.4)
    }
}

private struct TerminalCursorGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 4, y: 4))
                path.addLine(to: CGPoint(x: 0, y: 8))
            }
            .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 5, height: 8)

            Capsule(style: .continuous)
                .fill(tint.opacity(0.7))
                .frame(width: 8, height: 2)

            RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                .fill(tint.opacity(Int(phase * 3) % 2 == 0 ? 0.95 : 0.25))
                .frame(width: 2.5, height: 9)
        }
        .shadow(color: tint.opacity(0.55), radius: 2)
    }
}

private struct MangaBurstGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let pulse = 0.86 + CGFloat((sin(phase * 5) + 1) * 0.08)

            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(index.isMultiple(of: 2) ? 0.76 : 0.42))
                        .frame(width: 1.6, height: index.isMultiple(of: 2) ? size.height * 0.48 : size.height * 0.34)
                        .offset(y: -size.height * 0.24)
                        .rotationEffect(.degrees(Double(index) * 45 + phase * 18))
                }

                DiamondShape()
                    .fill(tint.opacity(0.92))
                    .frame(width: size.height * 0.48, height: size.height * 0.48)
                    .scaleEffect(pulse)
            }
            .frame(width: size.width, height: size.height)
        }
        .shadow(color: tint.opacity(0.6), radius: 2.2)
    }
}

private struct BladeGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sweep = CGFloat((sin(phase * 4) + 1) / 2)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.14, y: size.height * 0.78))
                    path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.18))
                }
                .stroke(tint.opacity(0.94), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

                Capsule(style: .continuous)
                    .fill(tint.opacity(0.48))
                    .frame(width: size.width * 0.35, height: 2.4)
                    .rotationEffect(.degrees(-42))
                    .position(x: size.width * 0.28, y: size.height * 0.7)

                Circle()
                    .fill(Color.white.opacity(0.62))
                    .frame(width: 2.4, height: 2.4)
                    .position(x: size.width * (0.28 + sweep * 0.38), y: size.height * (0.66 - sweep * 0.38))
            }
        }
        .shadow(color: tint.opacity(0.55), radius: 2)
    }
}

private struct CyberCircuitGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let pulseIndex = Int(phase * 5) % 4

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.72))
                    path.addLine(to: CGPoint(x: size.width * 0.28, y: size.height * 0.72))
                    path.addLine(to: CGPoint(x: size.width * 0.38, y: size.height * 0.5))
                    path.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.5))
                    path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.28))
                    path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.28))
                }
                .stroke(tint.opacity(0.64), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(tint.opacity(index == pulseIndex ? 0.96 : 0.42))
                        .frame(width: index == pulseIndex ? 3.6 : 2.6, height: index == pulseIndex ? 3.6 : 2.6)
                        .position(nodePosition(index: index, size: size))
                }
            }
        }
        .shadow(color: tint.opacity(0.5), radius: 2.2)
    }

    private func nodePosition(index: Int, size: CGSize) -> CGPoint {
        switch index {
        case 0: CGPoint(x: size.width * 0.08, y: size.height * 0.72)
        case 1: CGPoint(x: size.width * 0.38, y: size.height * 0.5)
        case 2: CGPoint(x: size.width * 0.72, y: size.height * 0.28)
        default: CGPoint(x: size.width * 0.92, y: size.height * 0.28)
        }
    }
}

private struct WaveformGlyph: View {
    let tint: Color
    let phase: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<8, id: \.self) { index in
                let height = 3 + CGFloat((sin(phase * 4 + Double(index) * 0.7) + 1) * 5)
                Capsule(style: .continuous)
                    .fill(tint.opacity(index == 3 || index == 4 ? 0.95 : 0.55))
                    .frame(width: 2.2, height: height)
            }
        }
        .shadow(color: tint.opacity(0.55), radius: 2)
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
