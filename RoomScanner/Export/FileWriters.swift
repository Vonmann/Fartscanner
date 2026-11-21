import Foundation
import simd

/// Turns ARKit meters (Y up) into export units and axes.
struct CoordConverter {
    /// Unit factor times calibration correction.
    var scale: Float
    /// Fusion 360 uses Z up by default. ARKit uses Y up.
    var zUp: Bool

    func convert(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let q = p * scale
        return zUp ? SIMD3(q.x, -q.z, q.y) : q
    }
}

/// Writes text in big chunks so large meshes stay fast.
final class TextFileWriter {
    private let handle: FileHandle
    private var buffer = ""
    private var bufferedBytes = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ s: String) {
        buffer += s
        bufferedBytes += s.utf8.count
        if bufferedBytes > 1 << 20 { flush() }
    }

    func flush() {
        if let data = buffer.data(using: .utf8) { handle.write(data) }
        buffer = ""
        bufferedBytes = 0
    }

    func close() {
        flush()
        try? handle.close()
    }
}

@inline(__always) private func num(_ v: Float) -> String { String(format: "%.4f", v) }

enum OBJWriter {
    static func write(_ meshes: [NamedMesh], converter: CoordConverter, unitLabel: String, to url: URL) throws {
        let out = try TextFileWriter(url: url)
        defer { out.close() }
        out.write("# Room Scanner export\n# Units: \(unitLabel)\n# Up axis: \(converter.zUp ? "Z" : "Y")\n")
        var offset: UInt32 = 1 // OBJ indices start at 1
        for m in meshes where !m.isEmpty {
            out.write("o \(m.name)\ng \(m.name)\n")
            for v in m.vertices {
                let p = converter.convert(v)
                out.write("v \(num(p.x)) \(num(p.y)) \(num(p.z))\n")
            }
            for f in m.faces {
                out.write("f \(f.x + offset) \(f.y + offset) \(f.z + offset)\n")
            }
            offset += UInt32(m.vertices.count)
        }
    }
}

enum STLWriter {
    /// Binary STL (smaller and faster than text STL). Fusion 360 reads it fine.
    static func write(_ meshes: [NamedMesh], converter: CoordConverter, to url: URL) throws {
        let triCount = meshes.reduce(0) { $0 + $1.faces.count }
        var data = Data(capacity: 84 + triCount * 50)
        var header = [UInt8]("Room Scanner binary STL".utf8)
        header += [UInt8](repeating: 0, count: 80 - header.count)
        data.append(contentsOf: header)
        appendLE(&data, UInt32(triCount))

        for m in meshes {
            let pts = m.vertices.map(converter.convert)
            for f in m.faces {
                let a = pts[Int(f.x)], b = pts[Int(f.y)], c = pts[Int(f.z)]
                var n = simd_cross(b - a, c - a)
                let len = simd_length(n)
                n = len > 0 ? n / len : .zero
                for v in [n, a, b, c] {
                    appendLE(&data, v.x.bitPattern)
                    appendLE(&data, v.y.bitPattern)
                    appendLE(&data, v.z.bitPattern)
                }
                appendLE(&data, UInt16(0))
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

enum DXFWriter {
    /// 2D floor plan. Fusion 360: Insert > Insert DXF. Opens as a sketch you can extrude.
    static func write(_ g: RoomGeometry, scale: Float, unit: LengthUnit, to url: URL) throws {
        var s = ""
        func pair(_ code: Int, _ value: String) { s += "\(code)\n\(value)\n" }
        func plan(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x * scale, -p.y * scale) } // (x, z) -> (x, -z)

        func line(_ layer: String, _ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            pair(0, "LINE"); pair(8, layer)
            pair(10, num(a.x)); pair(20, num(a.y)); pair(30, "0.0")
            pair(11, num(b.x)); pair(21, num(b.y)); pair(31, "0.0")
        }
        func text(_ layer: String, _ at: SIMD2<Float>, _ height: Float, _ angle: Float, _ value: String) {
            pair(0, "TEXT"); pair(8, layer)
            pair(10, num(at.x)); pair(20, num(at.y)); pair(30, "0.0")
            pair(40, num(height)); pair(1, value); pair(50, num(angle))
        }

        pair(0, "SECTION"); pair(2, "HEADER")
        pair(9, "$ACADVER"); pair(1, "AC1009")
        pair(9, "$INSUNITS"); pair(70, "\(unit.dxfCode)")
        pair(0, "ENDSEC")

        pair(0, "SECTION"); pair(2, "ENTITIES")
        let textHeight = Float(0.08 * unit.perMeter)

        for p in g.parts {
            switch p.kind {
            case .wall, .door, .window, .opening:
                let (a0, b0) = p.planSegment
                let a = plan(a0), b = plan(b0)
                let layer = p.kind.rawValue.uppercased() + "S"
                line(layer, a, b)
                if p.kind == .wall {
                    let mid = (a + b) / 2
                    var angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
                    if angle > 90 { angle -= 180 }
                    if angle <= -90 { angle += 180 }
                    let length = simd_distance(a, b)
                    let label = unit == .inches ? String(format: "%.2f\"", length) : String(format: "%.1f", length)
                    text("LABELS", mid, textHeight, angle, label)
                }
            case .floor:
                let pts = p.worldOutline.map { plan(SIMD2($0.x, $0.z)) }
                for i in pts.indices { line("FLOOR", pts[i], pts[(i + 1) % pts.count]) }
            case .object:
                let d = p.dimensions / 2
                let corners = [SIMD3(-d.x, 0, -d.z), SIMD3(d.x, 0, -d.z), SIMD3(d.x, 0, d.z), SIMD3(-d.x, 0, d.z)]
                    .map { p.transform.apply($0) }
                    .map { plan(SIMD2($0.x, $0.z)) }
                for i in corners.indices { line("OBJECTS", corners[i], corners[(i + 1) % corners.count]) }
            }
        }
        pair(0, "ENDSEC")
        pair(0, "EOF")
        try s.write(to: url, atomically: true, encoding: .ascii)
    }
}

enum CSVWriter {
    static func write(_ m: RoomMeasurements, unit: LengthUnit, to url: URL) throws {
        func v(_ meters: Double) -> String { String(format: "%.4f", meters * unit.perMeter) }
        var s = "Category,Name,Width (\(unit.label)),Height (\(unit.label)),Bottom above floor (\(unit.label))\n"
        for r in m.rows {
            s += "\(r.category),\(r.name),\(v(r.width)),\(v(r.height)),\(r.aboveFloor.map(v) ?? "")\n"
        }
        s += "\nSummary,Wall perimeter,\(v(m.wallPerimeter)),,\n"
        s += "Summary,Ceiling height,,\(v(m.ceilingHeight)),\n"
        let areaFactor = unit.perMeter * unit.perMeter
        s += "Summary,Floor area (\(unit.label)²),\(String(format: "%.4f", m.floorArea * areaFactor)),,\n"
        try s.write(to: url, atomically: true, encoding: .utf8)
    }
}
