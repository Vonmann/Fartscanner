import SwiftUI
import RoomPlan
import QuickLook

struct ScanDetailView: View {
    let recordID: UUID

    @EnvironmentObject private var store: ScanStore
    @AppStorage("unit") private var unit: LengthUnit = .millimeters

    @State private var room: CapturedRoom?
    @State private var mesh: MeshData?
    @State private var geometry: RoomGeometry?
    @State private var loadError: String?

    @State private var settings = ExportSettings()
    @State private var exporting = false
    @State private var exportedFiles: [URL] = []
    @State private var exportError: String?
    @State private var previewURL: URL?

    private var record: ScanRecord? { store.record(id: recordID) }

    var body: some View {
        Group {
            if let record, let geometry {
                content(record: record, geometry: geometry)
            } else if let loadError {
                Text(loadError).foregroundStyle(.red).padding()
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle(record?.name ?? "Scan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .quickLookPreview($previewURL)
    }

    private func content(record: ScanRecord, geometry: RoomGeometry) -> some View {
        let scale = record.calibrationScale
        let m = RoomMeasurements(geometry: geometry, scale: scale)
        return List {
            Section("Floor plan") {
                FloorPlanView(geometry: geometry, unit: unit, scale: scale)
                    .frame(height: 320)
                Button("View 3D model") { show3D() }
            }

            Section("Room") {
                LabeledContent("Floor area", value: unit.formatArea(squareMeters: m.floorArea))
                LabeledContent("Wall perimeter", value: unit.format(meters: m.wallPerimeter))
                LabeledContent("Ceiling height", value: unit.format(meters: m.ceilingHeight))
                Picker("Units", selection: $unit) {
                    ForEach(LengthUnit.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Measurements") {
                ForEach(m.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.subheadline.bold())
                        Text("W \(unit.format(meters: row.width))  ·  H \(unit.format(meters: row.height))")
                            .font(.caption)
                        if let above = row.aboveFloor {
                            Text("Bottom is \(unit.format(meters: above)) above floor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink("Check with a tape measure") {
                    CalibrationView(recordID: recordID, geometry: geometry)
                }
                if record.calibrationScale != 1 {
                    Text(String(format: "Correction in use: %+.2f%%", (record.calibrationScale - 1) * 100))
                        .font(.caption)
                }
            } header: {
                Text("Accuracy")
            } footer: {
                Text("Measure one long wall with a tape. The app fixes any scale error in all numbers and exports.")
            }

            exportSection(record: record)
        }
    }

    @ViewBuilder
    private func exportSection(record: ScanRecord) -> some View {
        Section {
            Toggle("3D room model (OBJ)", isOn: $settings.roomOBJ)
            Toggle("3D room model (STL)", isOn: $settings.roomSTL)
            if record.hasMesh {
                Toggle("Raw LiDAR mesh (OBJ)", isOn: $settings.meshOBJ)
                Toggle("Raw LiDAR mesh (STL)", isOn: $settings.meshSTL)
            }
            Toggle("Floor plan (DXF)", isOn: $settings.floorPlanDXF)
            Toggle("Measurements (CSV)", isOn: $settings.measurementsCSV)
            Toggle("Apple 3D (USDZ)", isOn: $settings.usdz)
        } header: {
            Text("Export files")
        }

        Section {
            Toggle("Z axis up (Fusion 360 default)", isOn: $settings.zUp)
            Toggle("Include furniture boxes", isOn: $settings.includeObjects)
            if record.calibrationScale != 1 {
                Toggle("Apply tape-measure correction", isOn: $settings.applyCalibration)
            }
            Stepper(value: $settings.wallThickness, in: 0.02...0.4, step: 0.01) {
                Text("Wall thickness: \(unit.format(meters: settings.wallThickness))")
            }
        } header: {
            Text("Export options")
        } footer: {
            Text("Files use the units picked above (\(unit.label)). Walls grow outward, so inside sizes stay exact.")
        }

        Section {
            Button {
                runExport(record: record)
            } label: {
                if exporting { ProgressView() } else { Text("Make files") }
            }
            .disabled(exporting)

            if let exportError { Text(exportError).foregroundStyle(.red) }

            if !exportedFiles.isEmpty {
                ForEach(exportedFiles, id: \.self) { url in
                    Text(url.lastPathComponent).font(.caption)
                }
                ShareLink(items: exportedFiles) {
                    Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func load() async {
        guard geometry == nil, let record else { return }
        let root = store.root
        let result: Result<(CapturedRoom, MeshData?), Error> = await Task.detached {
            do {
                let room = try ScanStore.loadRoom(record, root: root)
                return .success((room, ScanStore.loadMesh(record, root: root)))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let (room, mesh)):
            self.room = room
            self.mesh = mesh
            self.geometry = RoomGeometry(room: room)
        case .failure(let error):
            loadError = "Could not open this scan: \(error.localizedDescription)"
        }
    }

    private func runExport(record: ScanRecord) {
        guard let room else { return }
        var s = settings
        s.unit = unit
        let mesh = self.mesh
        exporting = true
        exportError = nil
        Task {
            let result: Result<[URL], Error> = await Task.detached {
                Result { try Exporter.export(room: room, mesh: mesh, record: record, settings: s) }
            }.value
            exporting = false
            switch result {
            case .success(let urls): exportedFiles = urls
            case .failure(let error): exportError = error.localizedDescription
            }
        }
    }

    private func show3D() {
        guard let room else { return }
        do {
            previewURL = try Exporter.previewUSDZ(room: room, id: recordID)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
