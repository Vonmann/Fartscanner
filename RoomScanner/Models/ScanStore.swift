import Foundation
import RoomPlan

struct ScanRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var date: Date
    var hasMesh: Bool
    /// Multiply scanned lengths by this to match a tape measure. 1 = no correction.
    var calibrationScale: Double = 1
    var calibrationNote: String?
}

/// Saves scans in the app's Documents/Scans folder (visible in the Files app).
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var scans: [ScanRecord] = []

    let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        scans = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) else { return nil }
            return try? JSONDecoder().decode(ScanRecord.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    @discardableResult
    func save(room: CapturedRoom, mesh: MeshData, name: String) throws -> ScanRecord {
        let record = ScanRecord(id: UUID(), name: name.isEmpty ? "Room" : name, date: Date(), hasMesh: !mesh.isEmpty)
        let dir = folder(for: record.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(room).write(to: dir.appendingPathComponent("room.json"))
        if !mesh.isEmpty {
            try mesh.write(to: dir.appendingPathComponent("mesh.bin"))
        }
        try writeMeta(record)
        reload()
        return record
    }

    func update(_ record: ScanRecord) {
        try? writeMeta(record)
        reload()
    }

    func delete(_ record: ScanRecord) {
        try? FileManager.default.removeItem(at: folder(for: record.id))
        reload()
    }

    func record(id: UUID) -> ScanRecord? { scans.first { $0.id == id } }

    nonisolated static func loadRoom(_ record: ScanRecord, root: URL) throws -> CapturedRoom {
        let url = root.appendingPathComponent(record.id.uuidString).appendingPathComponent("room.json")
        return try JSONDecoder().decode(CapturedRoom.self, from: Data(contentsOf: url))
    }

    nonisolated static func loadMesh(_ record: ScanRecord, root: URL) -> MeshData? {
        guard record.hasMesh else { return nil }
        let url = root.appendingPathComponent(record.id.uuidString).appendingPathComponent("mesh.bin")
        return try? MeshData(contentsOf: url)
    }

    private func writeMeta(_ record: ScanRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: folder(for: record.id).appendingPathComponent("meta.json"), options: .atomic)
    }
}
