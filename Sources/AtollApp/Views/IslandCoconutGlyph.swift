import SwiftUI

/// Tiny vector island-with-palm-tree glyph for the menu bar. Drawn with
/// SwiftUI `Path` shapes (not `Canvas` — Canvas re-evaluates its draw
/// closure on every parent body invalidation, and the menu bar's render
/// loop kept it spinning at 100% CPU). Static `Path` views render once
/// and stay put. Inherits `foregroundStyle` so macOS handles
/// dark/light/active menu bar tinting automatically.
struct IslandCoconutGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            islandShape
                .fill(.foreground.opacity(0.92))
            trunkShape
                .stroke(.foreground, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            ForEach([CGFloat(-130), -100, -55, -25], id: \.self) { angle in
                frondShape(angle: angle)
                    .stroke(.foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
            coconutShape
                .fill(.foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Shapes

    private var islandShape: some Shape {
        IslandBaseShape()
    }

    private var trunkShape: some Shape {
        TrunkShape()
    }

    private func frondShape(angle: CGFloat) -> some Shape {
        FrondShape(angleDegrees: angle)
    }

    private var coconutShape: some Shape {
        CoconutShape()
    }
}

private struct IslandBaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let baseY = rect.height * 0.78
        let scale = min(rect.width, rect.height) / 18.0
        var p = Path()
        p.move(to: CGPoint(x: cx - 7 * scale, y: baseY))
        p.addQuadCurve(
            to: CGPoint(x: cx + 7 * scale, y: baseY),
            control: CGPoint(x: cx, y: baseY + 3 * scale)
        )
        p.addQuadCurve(
            to: CGPoint(x: cx - 7 * scale, y: baseY),
            control: CGPoint(x: cx, y: baseY - 1.2 * scale)
        )
        return p
    }
}

private struct TrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let baseY = rect.height * 0.78
        let scale = min(rect.width, rect.height) / 18.0
        let trunkStart = CGPoint(x: cx - 0.3 * scale, y: baseY - 0.5 * scale)
        let trunkEnd   = CGPoint(x: cx + 1.0 * scale, y: baseY - 8 * scale)
        var p = Path()
        p.move(to: trunkStart)
        p.addQuadCurve(to: trunkEnd,
                       control: CGPoint(x: cx + 2.6 * scale, y: baseY - 4 * scale))
        return p
    }
}

private struct FrondShape: Shape {
    var angleDegrees: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let baseY = rect.height * 0.78
        let scale = min(rect.width, rect.height) / 18.0
        let crown = CGPoint(x: cx + 1.0 * scale, y: baseY - 8 * scale)
        let length = 4.6 * scale

        let r = Double(angleDegrees) * .pi / 180
        let cosR = CGFloat(cos(r))
        let sinR = CGFloat(sin(r))
        let cosPerp = CGFloat(cos(r + .pi / 2))
        let sinPerp = CGFloat(sin(r + .pi / 2))

        let tip = CGPoint(
            x: crown.x + length * cosR,
            y: crown.y + length * sinR
        )
        let mid = CGPoint(
            x: crown.x + length * 0.55 * cosR + 0.6 * scale * cosPerp,
            y: crown.y + length * 0.55 * sinR + 0.6 * scale * sinPerp
        )
        var p = Path()
        p.move(to: crown)
        p.addQuadCurve(to: tip, control: mid)
        return p
    }
}

private struct CoconutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let baseY = rect.height * 0.78
        let scale = min(rect.width, rect.height) / 18.0
        let crown = CGPoint(x: cx + 1.0 * scale, y: baseY - 8 * scale)

        var p = Path()
        for dx in [CGFloat(-1.4), CGFloat(1.6)] {
            p.addEllipse(in: CGRect(
                x: crown.x + dx * scale - 0.7 * scale,
                y: crown.y - 0.2 * scale,
                width: 1.4 * scale,
                height: 1.4 * scale
            ))
        }
        return p
    }
}
