import SwiftUI
import simd

/// Top-down drawing of the room with wall lengths.
struct FloorPlanView: View {
    let geometry: RoomGeometry
    let unit: LengthUnit
    /// Tape-measure correction.
    let scale: Double

    var body: some View {
        Canvas { context, size in
            // Seen from above: x to the right, -z up the screen.
            var all: [SIMD2<Float>] = []
            for p in geometry.parts where p.kind != .object {
                if p.kind == .floor {
                    all += p.worldOutline.map { SIMD2($0.x, $0.z) }
                } else {
                    let s = p.planSegment
                    all += [s.0, s.1]
                }
            }
            guard let first = all.first else { return }
            var lo = first, hi = first
            for p in all { lo = simd_min(lo, p); hi = simd_max(hi, p) }

            let pad: CGFloat = 36
            let span = hi - lo
            let fit = min((size.width - pad * 2) / CGFloat(max(span.x, 0.01)),
                          (size.height - pad * 2) / CGFloat(max(span.y, 0.01)))
            let offsetX = (size.width - CGFloat(span.x) * fit) / 2
            let offsetY = (size.height - CGFloat(span.y) * fit) / 2
            func screen(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: offsetX + CGFloat(p.x - lo.x) * fit,
                        y: offsetY + CGFloat(p.y - lo.y) * fit)
            }

            // Floor fill
            for f in geometry.parts(of: .floor) {
                let pts = f.worldOutline.map { screen(SIMD2($0.x, $0.z)) }
                guard pts.count >= 3 else { continue }
                var path = Path()
                path.addLines(pts)
                path.closeSubpath()
                context.fill(path, with: .color(.gray.opacity(0.15)))
            }

            // Furniture footprints
            for o in geometry.parts(of: .object) {
                let d = o.dimensions / 2
                let pts = [SIMD3<Float>(-d.x, 0, -d.z), SIMD3(d.x, 0, -d.z), SIMD3(d.x, 0, d.z), SIMD3(-d.x, 0, d.z)]
                    .map { o.transform.apply($0) }
                    .map { screen(SIMD2($0.x, $0.z)) }
                var path = Path()
                path.addLines(pts)
                path.closeSubpath()
                context.stroke(path, with: .color(.orange.opacity(0.6)), lineWidth: 1)
            }

            // Walls, doors, windows, openings
            let styles: [(PartKind, Color, CGFloat)] = [
                (.wall, .primary, 4), (.opening, .gray, 4), (.door, .blue, 6), (.window, .cyan, 6),
            ]
            for (kind, color, width) in styles {
                for p in geometry.parts(of: kind) {
                    let s = p.planSegment
                    var path = Path()
                    path.move(to: screen(s.0))
                    path.addLine(to: screen(s.1))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }

            // Wall length labels, pushed slightly toward the room's middle.
            let mid2 = SIMD2<Float>(geometry.center.x, geometry.center.z)
            for p in geometry.parts(of: .wall) {
                let s = p.planSegment
                let m = (s.0 + s.1) / 2
                let inward = simd_length(mid2 - m) > 0 ? simd_normalize(mid2 - m) : .zero
                let at = screen(m + inward * Float(14 / fit))
                let text = Text(unit.format(meters: Double(p.width) * scale)).font(.system(size: 9))
                context.draw(text, at: at)
            }
        }
        .accessibilityLabel("Floor plan")
    }
}
