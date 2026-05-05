import SwiftUI

/// Tiny vector island-with-palm-tree glyph for the menu bar. Drawn with
/// SwiftUI `Canvas` strokes/fills using the current foreground color so
/// macOS handles dark/light/active tinting automatically (template
/// behavior). Sized in point space — call site sets the frame.
struct IslandCoconutGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let baseY = canvasSize.height * 0.78
            let scale = s / 18.0

            // Island base — gentle ellipse arc from one side to the other
            let islandPath = Path { p in
                p.move(to: CGPoint(x: cx - 7 * scale, y: baseY))
                p.addQuadCurve(
                    to: CGPoint(x: cx + 7 * scale, y: baseY),
                    control: CGPoint(x: cx, y: baseY + 3 * scale)
                )
                p.addQuadCurve(
                    to: CGPoint(x: cx - 7 * scale, y: baseY),
                    control: CGPoint(x: cx, y: baseY - 1.2 * scale)
                )
            }
            ctx.fill(islandPath, with: .style(.foreground.opacity(0.92)))

            // Trunk — slight curve, thin stroke
            let trunkStart = CGPoint(x: cx - 0.3 * scale, y: baseY - 0.5 * scale)
            let trunkEnd   = CGPoint(x: cx + 1.0 * scale, y: baseY - 8 * scale)
            let trunk = Path { p in
                p.move(to: trunkStart)
                p.addQuadCurve(to: trunkEnd,
                               control: CGPoint(x: cx + 2.6 * scale, y: baseY - 4 * scale))
            }
            ctx.stroke(trunk, with: .style(.foreground), lineWidth: 1.4 * scale)

            // 4 palm fronds fanning out from the trunk top
            let crown = trunkEnd
            let frondLength: CGFloat = 4.6 * scale
            let frondAngles: [Double] = [-130, -100, -55, -25]
            for angle in frondAngles {
                let frond = frondPath(crown: crown, lengthInPoints: frondLength, angleDegrees: angle, scale: scale)
                ctx.stroke(
                    frond,
                    with: .style(.foreground),
                    style: StrokeStyle(lineWidth: 1.3 * scale, lineCap: .round)
                )
            }

            // Two coconuts at the crown — tiny filled circles
            for dx in [CGFloat(-1.4), CGFloat(1.6)] {
                let coconut = Path(ellipseIn: CGRect(
                    x: crown.x + dx * scale - 0.7 * scale,
                    y: crown.y - 0.2 * scale,
                    width: 1.4 * scale,
                    height: 1.4 * scale
                ))
                ctx.fill(coconut, with: .style(.foreground))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func frondPath(crown: CGPoint, lengthInPoints: CGFloat, angleDegrees: Double, scale: CGFloat) -> Path {
        let r = angleDegrees * .pi / 180
        let cosR = CGFloat(cos(r))
        let sinR = CGFloat(sin(r))
        let cosPerp = CGFloat(cos(r + .pi / 2))
        let sinPerp = CGFloat(sin(r + .pi / 2))
        let tip = CGPoint(
            x: crown.x + lengthInPoints * cosR,
            y: crown.y + lengthInPoints * sinR
        )
        let mid = CGPoint(
            x: crown.x + lengthInPoints * 0.55 * cosR + 0.6 * scale * cosPerp,
            y: crown.y + lengthInPoints * 0.55 * sinR + 0.6 * scale * sinPerp
        )
        return Path { p in
            p.move(to: crown)
            p.addQuadCurve(to: tip, control: mid)
        }
    }
}
