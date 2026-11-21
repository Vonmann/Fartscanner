import Foundation
import ARKit
import simd

/// Raw LiDAR surface mesh, in world space, meters (ARKit: Y is up).
struct MeshData {
    var vertices: [SIMD3<Float>] = []
    var faces: [SIMD3<UInt32>] = []

    var isEmpty: Bool { faces.isEmpty }

    init() {}

    init(anchors: [ARMeshAnchor]) {
        for anchor in anchors {
            let geometry = anchor.geometry
            let base = UInt32(vertices.count)

            let vSource = geometry.vertices
            let vPtr = vSource.buffer.contents()
            vertices.reserveCapacity(vertices.count + vSource.count)
            for i in 0..<vSource.count {
                let p = vPtr.advanced(by: vSource.offset + vSource.stride * i)
                    .assumingMemoryBound(to: Float.self)
                vertices.append(anchor.transform.apply(SIMD3(p[0], p[1], p[2])))
            }

            let fElement = geometry.faces
            let fPtr = fElement.buffer.contents()
            let perFace = fElement.indexCountPerPrimitive
            let bytes = fElement.bytesPerIndex
            guard perFace == 3 else { continue }
            faces.reserveCapacity(faces.count + fElement.count)
            for i in 0..<fElement.count {
                var tri = SIMD3<UInt32>(0, 0, 0)
                for j in 0..<3 {
                    let offset = (i * perFace + j) * bytes
                    if bytes == 4 {
                        tri[j] = fPtr.load(fromByteOffset: offset, as: UInt32.self)
                    } else {
                        tri[j] = UInt32(fPtr.load(fromByteOffset: offset, as: UInt16.self))
                    }
                }
                faces.append(tri &+ SIMD3(repeating: base))
            }
        }
    }

    // MARK: Simple binary save format (header: vertex count, face count)

    private static let headerSize = 16

    func write(to url: URL) throws {
        var data = Data()
        let counts: [UInt64] = [UInt64(vertices.count), UInt64(faces.count)]
        counts.withUnsafeBytes { data.append(contentsOf: $0) }
        vertices.withUnsafeBytes { data.append(contentsOf: $0) }
        faces.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url, options: .atomic)
    }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= Self.headerSize else { return }
        var counts: [UInt64] = [0, 0]
        counts.withUnsafeMutableBytes { dst in
            _ = data.copyBytes(to: dst, from: 0..<Self.headerSize)
        }
        let vCount = Int(counts[0]), fCount = Int(counts[1])
        let vBytes = vCount * MemoryLayout<SIMD3<Float>>.stride
        let fBytes = fCount * MemoryLayout<SIMD3<UInt32>>.stride
        guard data.count >= Self.headerSize + vBytes + fBytes else { return }

        var v = [SIMD3<Float>](repeating: .zero, count: vCount)
        v.withUnsafeMutableBytes { dst in
            _ = data.copyBytes(to: dst, from: Self.headerSize..<(Self.headerSize + vBytes))
        }
        var f = [SIMD3<UInt32>](repeating: .zero, count: fCount)
        f.withUnsafeMutableBytes { dst in
            let start = Self.headerSize + vBytes
            _ = data.copyBytes(to: dst, from: start..<(start + fBytes))
        }
        vertices = v
        faces = f
    }
}
