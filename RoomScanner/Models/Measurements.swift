import Foundation

struct MeasurementRow: Identifiable {
    let id = UUID()
    var category: String
    var name: String
    /// All lengths in meters (already corrected by calibration).
    var width: Double
    var height: Double
    var aboveFloor: Double?
}

/// Room numbers, in meters, with the tape-measure correction applied.
struct RoomMeasurements {
    var rows: [MeasurementRow] = []
    var floorArea: Double = 0
    var wallPerimeter: Double = 0
    var ceilingHeight: Double = 0

    init(geometry: RoomGeometry, scale: Double) {
        let floorY = geometry.floorY
        let order: [PartKind] = [.wall, .door, .window, .opening, .object]
        for kind in order {
            for p in geometry.parts(of: kind) {
                var above: Double? = nil
                if kind == .window || kind == .door || kind == .opening {
                    above = Double(p.bottomY - floorY) * scale
                }
                rows.append(MeasurementRow(category: kind.rawValue.capitalized,
                                           name: p.label,
                                           width: Double(p.width) * scale,
                                           height: Double(p.height) * scale,
                                           aboveFloor: above))
            }
        }

        let walls = geometry.parts(of: .wall)
        wallPerimeter = walls.reduce(0) { $0 + Double($1.width) } * scale
        ceilingHeight = Double(walls.map { $0.height }.max() ?? 0) * scale

        // Floor area from the floor outline seen from above.
        var area: Double = 0
        for f in geometry.parts(of: .floor) {
            let pts = f.worldOutline.map { SIMD2<Float>($0.x, $0.z) }
            area += abs(Double(Geometry2D.signedArea(pts)))
        }
        floorArea = area * scale * scale
    }
}
