import SwiftUI

/// Compare one scanned wall with a tape measure and save a scale correction.
struct CalibrationView: View {
    let recordID: UUID
    let geometry: RoomGeometry

    @EnvironmentObject private var store: ScanStore
    @AppStorage("unit") private var unit: LengthUnit = .millimeters
    @State private var wallIndex = 0
    @State private var measuredText = ""

    private var walls: [RoomPart] {
        geometry.parts(of: .wall).sorted { $0.width > $1.width }
    }

    private var scannedMeters: Double? {
        walls.indices.contains(wallIndex) ? Double(walls[wallIndex].width) : nil
    }

    private var measuredMeters: Double? {
        let cleaned = measuredText.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v / unit.perMeter
    }

    var body: some View {
        Form {
            Section {
                Picker("Wall", selection: $wallIndex) {
                    ForEach(walls.indices, id: \.self) { i in
                        Text("\(walls[i].label): \(unit.format(meters: Double(walls[i].width)))").tag(i)
                    }
                }
                TextField("Tape measure length (\(unit.label))", text: $measuredText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("1. Pick a wall and measure it")
            } footer: {
                Text("Pick a long wall. Measure along the floor, corner to corner, with a tape or laser measure.")
            }

            if let scanned = scannedMeters, let measured = measuredMeters {
                let diff = scanned - measured
                Section("2. Result") {
                    LabeledContent("Scanned", value: unit.format(meters: scanned))
                    LabeledContent("Tape", value: unit.format(meters: measured))
                    LabeledContent("Difference", value: unit.format(meters: abs(diff)))
                    LabeledContent("Error", value: String(format: "%.2f%%", diff / measured * 100))
                    Button("Use this correction") {
                        save(scale: measured / scanned,
                             note: "Matched \(walls[wallIndex].label) to \(unit.format(meters: measured))")
                    }
                }
            }

            if let record = store.record(id: recordID), record.calibrationScale != 1 {
                Section("Current correction") {
                    Text(String(format: "%+.2f%%", (record.calibrationScale - 1) * 100))
                    if let note = record.calibrationNote { Text(note).font(.caption) }
                    Button("Remove correction", role: .destructive) { save(scale: 1, note: nil) }
                }
            }
        }
        .navigationTitle("Accuracy check")
    }

    private func save(scale: Double, note: String?) {
        guard var record = store.record(id: recordID) else { return }
        record.calibrationScale = scale
        record.calibrationNote = note
        store.update(record)
    }
}
