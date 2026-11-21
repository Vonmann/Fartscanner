import Foundation
import RoomPlan
import simd

enum PartKind: String, CaseIterable {
    case wall, door, window, opening, floor, object
}

/// One piece of the room (a wall, door, floor, ...), in world meters, ARKit axes (Y up).
/// Surfaces lie in their local XY plane; local Z is the surface normal.
struct RoomPart: Identifiable {
    let id = UUID()
    var kind: PartKind
    var label: String
    var transform: simd_float4x4
    var dimensions: SIMD3<Float>
    /// Floor outline corners in local space (may be empty).
    var polygon: [SIMD3<Float>] = []

    var width: Float { dimensions.x }
    var height: Float { dimensions.y }

    /// Start and end of the bottom-center line of a surface, seen from above (x, z).
    var planSegment: (SIMD2<Float>, SIMD2<Float>) {
        let a = transform.apply(SIMD3(-dimensions.x / 2, 0, 0))
        let b = transform.apply(SIMD3(dimensions.x / 2, 0, 0))
        return (SIMD2(a.x, a.z), SIMD2(b.x, b.z))
    }

    /// Lowest world Y of this surface.
    var bottomY: Float {
        let a = transform.apply(SIMD3(0, -dimensions.y / 2, 0))
        let b = transform.apply(SIMD3(0, dimensions.y / 2, 0))
        return min(a.y, b.y)
    }

    /// Outline of a surface in local XY (polygon if known, else its rectangle).
    var localOutline: [SIMD2<Float>] {
        if polygon.count >= 3 { return polygon.map { SIMD2($0.x, $0.y) } }
        let w = dimensions.x / 2, h = dimensions.y / 2
        return [SIMD2(-w, -h), SIMD2(w, -h), SIMD2(w, h), SIMD2(-w, h)]
    }

    /// Outline in world space.
    var worldOutline: [SIMD3<Float>] {
        localOutline.map { transform.apply(SIMD3($0.x, $0.y, 0)) }
    }
}

struct RoomGeometry {
    var parts: [RoomPart] = []
    /// Middle of the room (average of wall centers). Used to know which way is "outside".
    var center: SIMD3<Float> = .zero

    init(room: CapturedRoom) {
        for (i, s) in room.walls.enumerated() {
            parts.append(RoomPart(kind: .wall, label: "Wall \(i + 1)", transform: s.transform, dimensions: s.dimensions))
        }
        for (i, s) in room.doors.enumerated() {
            parts.append(RoomPart(kind: .door, label: "Door \(i + 1)", transform: s.transform, dimensions: s.dimensions))
        }
        for (i, s) in room.windows.enumerated() {
            parts.append(RoomPart(kind: .window, label: "Window \(i + 1)", transform: s.transform, dimensions: s.dimensions))
        }
        for (i, s) in room.openings.enumerated() {
            parts.append(RoomPart(kind: .opening, label: "Opening \(i + 1)", transform: s.transform, dimensions: s.dimensions))
        }
        for (i, s) in room.floors.enumerated() {
            parts.append(RoomPart(kind: .floor, label: "Floor \(i + 1)", transform: s.transform,
                                  dimensions: s.dimensions, polygon: s.polygonCorners))
        }
        for (i, o) in room.objects.enumerated() {
            let name = String(describing: o.category).capitalized
            parts.append(RoomPart(kind: .object, label: "\(name) \(i + 1)", transform: o.transform, dimensions: o.dimensions))
        }

        let walls = parts(of: .wall)
        if !walls.isEmpty {
            center = walls.map { $0.transform.position }.reduce(.zero, +) / Float(walls.count)
        }
    }

    func parts(of kind: PartKind) -> [RoomPart] { parts.filter { $0.kind == kind } }

    /// World Y of the floor.
    var floorY: Float {
        if let f = parts(of: .floor).first { return f.transform.position.y }
        return parts(of: .wall).map { $0.bottomY }.min() ?? 0
    }

    /// +1 or -1: which way along local Z points away from the room.
    func outwardSign(for part: RoomPart) -> Float {
        let toPart = part.transform.position - center
        return simd_dot(part.transform.zAxis, toPart) >= 0 ? 1 : -1
    }
}
