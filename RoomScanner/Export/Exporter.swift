import Foundation
import RoomPlan

struct ExportSettings {
    var unit: LengthUnit = .millimeters
    var zUp = true
    var applyCalibration = true
    var wallThickness: Double = 0.1 // meters
    var includeObjects = true

    var roomOBJ = true
    var roomSTL = true
    var meshOBJ = true
    var meshSTL = true
    var floorPlanDXF = true
    var measurementsCSV = true
    var usdz = false
}

enum Exporter {
    /// Writes every chosen file into a fresh temp folder and returns their URLs.
    static func export(room: CapturedRoom, mesh: MeshData?, record: ScanRecord, settings: ExportSettings) throws -> [URL] {
        let safeName = record.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let base = safeName.isEmpty ? "Room" : safeName
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(record.id.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let calibration = settings.applyCalibration ? record.calibrationScale : 1
        let scale = Float(settings.unit.perMeter * calibration)
        let converter = CoordConverter(scale: scale, zUp: settings.zUp)
        let geometry = RoomGeometry(room: room)
        var urls: [URL] = []

        if settings.roomOBJ || settings.roomSTL {
            let model = ModelBuilder.build(geometry, options: ModelOptions(wallThickness: Float(settings.wallThickness),
                                                                           includeObjects: settings.includeObjects))
            if settings.roomOBJ {
                let url = dir.appendingPathComponent("\(base)_model.obj")
                try OBJWriter.write(model, converter: converter, unitLabel: settings.unit.label, to: url)
                urls.append(url)
            }
            if settings.roomSTL {
                let url = dir.appendingPathComponent("\(base)_model.stl")
                try STLWriter.write(model, converter: converter, to: url)
                urls.append(url)
            }
        }

        if let mesh, !mesh.isEmpty, settings.meshOBJ || settings.meshSTL {
            let named = [NamedMesh(name: "LidarMesh", vertices: mesh.vertices, faces: mesh.faces)]
            if settings.meshOBJ {
                let url = dir.appendingPathComponent("\(base)_lidar_mesh.obj")
                try OBJWriter.write(named, converter: converter, unitLabel: settings.unit.label, to: url)
                urls.append(url)
            }
            if settings.meshSTL {
                let url = dir.appendingPathComponent("\(base)_lidar_mesh.stl")
                try STLWriter.write(named, converter: converter, to: url)
                urls.append(url)
            }
        }

        if settings.floorPlanDXF {
            let url = dir.appendingPathComponent("\(base)_floor_plan.dxf")
            try DXFWriter.write(geometry, scale: scale, unit: settings.unit, to: url)
            urls.append(url)
        }

        if settings.measurementsCSV {
            let url = dir.appendingPathComponent("\(base)_measurements.csv")
            try CSVWriter.write(RoomMeasurements(geometry: geometry, scale: calibration), unit: settings.unit, to: url)
            urls.append(url)
        }

        if settings.usdz {
            let url = dir.appendingPathComponent("\(base).usdz")
            try room.export(to: url, exportOptions: .parametric)
            urls.append(url)
        }
        return urls
    }

    /// A USDZ file for the 3D preview (Apple Quick Look).
    static func previewUSDZ(room: CapturedRoom, id: UUID) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(id.uuidString).usdz")
        try? FileManager.default.removeItem(at: url)
        try room.export(to: url, exportOptions: .parametric)
        return url
    }
}
