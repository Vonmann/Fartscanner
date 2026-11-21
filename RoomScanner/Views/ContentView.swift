import SwiftUI
import RoomPlan

struct ContentView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var showScanner = false

    private var supported: Bool { RoomCaptureSession.isSupported }

    var body: some View {
        NavigationStack {
            List {
                if !supported {
                    Text("This device has no LiDAR scanner, so room scanning is not available.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.scans) { record in
                    NavigationLink(value: record) {
                        VStack(alignment: .leading) {
                            Text(record.name).font(.headline)
                            Text(record.date, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let items = offsets.map { store.scans[$0] }
                    items.forEach { store.delete($0) }
                }
            }
            .overlay {
                if store.scans.isEmpty && supported {
                    ContentUnavailableView("No scans yet",
                                           systemImage: "cube.transparent",
                                           description: Text("Tap + to scan a room."))
                }
            }
            .navigationTitle("Room Scanner")
            .toolbar {
                Button {
                    showScanner = true
                } label: {
                    Label("New Scan", systemImage: "plus")
                }
                .disabled(!supported)
            }
            .navigationDestination(for: ScanRecord.self) { record in
                ScanDetailView(recordID: record.id)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanScreen()
            }
        }
    }
}
