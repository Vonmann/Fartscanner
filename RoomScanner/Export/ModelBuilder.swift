import Foundation
import simd

/// A named triangle mesh (one body in Fusion 360).
struct NamedMesh {
    var name: String
    var vertices: [SIMD3<Float>] = []
    var faces: [SIMD3<UInt32>] = []

    var isEmpty: Bool { faces.isEmpty }

    private mutating func addQuad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        faces.append(SIMD3(a, b, c))
        faces.append(SIMD3(a, c, d))
    }

    /// Adds a box given in the part's local space. Faces point outward.
    mutating func addBox(transform: simd_float4x4, min lo: SIMD3<Float>, max hi: SIMD3<Float>) {
        let base = UInt32(vertices.count)
        // Corner index = i + 2*j + 4*k, where i/j/k pick min (0) or max (1) on x/y/z.
        for k in 0...1 { for j in 0...1 { for i in 0...1 {
            let p = SIMD3<Float>(i == 0 ? lo.x : hi.x, j == 0 ? lo.y : hi.y, k == 0 ? lo.z : hi.z)
            vertices.append(transform.apply(p))
        } } }
        func c(_ i: UInt32, _ j: UInt32, _ k: UInt32) -> UInt32 { base + i + 2 * j + 4 * k }
        addQuad(c(0,0,0), c(0,0,1), c(0,1,1), c(0,1,0)) // -x
        addQuad(c(1,0,0), c(1,1,0), c(1,1,1), c(1,0,1)) // +x
        addQuad(c(0,0,0), c(1,0,0), c(1,0,1), c(0,0,1)) // -y
        addQuad(c(0,1,0), c(0,1,1), c(1,1,1), c(1,1,0)) // +y
        addQuad(c(0,0,0), c(0,1,0), c(1,1,0), c(1,0,0)) // -z
        addQuad(c(0,0,1), c(1,0,1), c(1,1,1), c(0,1,1)) // +z
    }

    /// Adds a solid made by pushing a flat local-XY outline from z0 to z1 (z0 < z1).
    mutating func addPrism(transform: simd_float4x4, outline: [SIMD2<Float>], z0: Float, z1: Float) {
        guard outline.count >= 3 else { return }
        let pts = Geometry2D.signedArea(outline) < 0 ? Array(outline.reversed()) : outline
        let n = UInt32(pts.count)
        let base = UInt32(vertices.count)
        for p in pts { vertices.append(transform.apply(SIMD3(p.x, p.y, z0))) }
        for p in pts { vertices.append(transform.apply(SIMD3(p.x, p.y, z1))) }
        let tris = Geometry2D.triangulate(pts)
        for (a, b, c) in tris {
            // Top (z1) faces +z, bottom (z0) faces -z.
            faces.append(SIMD3(base + n + UInt32(a), base + n + UInt32(b), base + n + UInt32(c)))
            faces.append(SIMD3(base + UInt32(a), base + UInt32(c), base + UInt32(b)))
        }
        for i in 0..<n {
            let j = (i + 1) % n
            addQuad(base + i, base + j, base + n + j, base + n + i)
        }
    }
}

struct ModelOptions {
    /// Walls and floor are pushed outward by this much, so inside faces stay exactly where scanned.
    var wallThickness: Float = 0.1
    var includeObjects: Bool = true
}

enum ModelBuilder {
    /// Builds clean solid bodies from the RoomPlan result (meters, ARKit axes).
    static func build(_ g: RoomGeometry, options: ModelOptions) -> [NamedMesh] {
        let t = options.wallThickness
        var walls = NamedMesh(name: "Walls")
        var floor = NamedMesh(name: "Floor")
        var doors = NamedMesh(name: "Doors")
        var windows = NamedMesh(name: "Windows")
        var objects = NamedMesh(name: "Objects")

        for p in g.parts {
            let w = p.width / 2, h = p.height / 2
            let s = g.outwardSign(for: p)
            switch p.kind {
            case .wall:
                let z = s > 0 ? (Float(0), t) : (-t, Float(0))
                walls.addBox(transform: p.transform, min: SIMD3(-w, -h, z.0), max: SIMD3(w, h, z.1))
            case .door, .window:
                // A little thicker than the wall so it shows on both sides.
                let z = s > 0 ? (Float(-0.01), t + 0.01) : (-t - 0.01, Float(0.01))
                if p.kind == .door {
                    doors.addBox(transform: p.transform, min: SIMD3(-w, -h, z.0), max: SIMD3(w, h, z.1))
                } else {
                    windows.addBox(transform: p.transform, min: SIMD3(-w, -h, z.0), max: SIMD3(w, h, z.1))
                }
            case .floor:
                let z = s > 0 ? (Float(0), t) : (-t, Float(0))
                floor.addPrism(transform: p.transform, outline: p.localOutline, z0: z.0, z1: z.1)
            case .object:
                guard options.includeObjects else { continue }
                let d = p.dimensions / 2
                objects.addBox(transform: p.transform, min: -d, max: d)
            case .opening:
                continue // An opening is a hole, so there is nothing solid to add.
            }
        }
        return [walls, floor, doors, windows, objects].filter { !$0.isEmpty }
    }
}
