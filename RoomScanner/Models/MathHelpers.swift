import Foundation
import simd

extension simd_float4x4 {
    var position: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
    var xAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.0.x, columns.0.y, columns.0.z)) }
    var yAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.1.x, columns.1.y, columns.1.z)) }
    var zAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.2.x, columns.2.y, columns.2.z)) }

    /// Transforms a point from local space to world space.
    func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = self * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3(r.x, r.y, r.z)
    }
}

enum Geometry2D {
    static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    /// Positive when the points go counter-clockwise.
    static func signedArea(_ pts: [SIMD2<Float>]) -> Float {
        guard pts.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let d1 = cross(b - a, p - a), d2 = cross(c - b, p - b), d3 = cross(a - c, p - c)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    /// Ear-clipping triangulation. Input must be counter-clockwise.
    static func triangulate(_ pts: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        var idx = Array(pts.indices)
        var result: [(Int, Int, Int)] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < 10_000 {
            guardCount += 1
            var clipped = false
            for i in 0..<idx.count {
                let a = idx[(i + idx.count - 1) % idx.count]
                let b = idx[i]
                let c = idx[(i + 1) % idx.count]
                if cross(pts[b] - pts[a], pts[c] - pts[b]) <= 0 { continue } // reflex corner
                var blocked = false
                for j in idx where j != a && j != b && j != c {
                    if pointInTriangle(pts[j], pts[a], pts[b], pts[c]) { blocked = true; break }
                }
                if blocked { continue }
                result.append((a, b, c))
                idx.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if idx.count == 3 { result.append((idx[0], idx[1], idx[2])) }
        return result
    }
}
