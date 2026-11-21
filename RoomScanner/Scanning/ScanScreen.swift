import SwiftUI

struct ScanScreen: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ScanModel()
    @State private var name = ""
    @State private var saveError: String?

    var body: some View {
        ZStack {
            RoomCaptureContainer(model: model)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if model.phase == .scanning {
                        Button("Done") { model.finish() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()

                if model.phase == .scanning {
                    Text("Move slowly. Point at every wall, corner, door and window. Keep 1 to 3 m from walls.")
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                Spacer()

                switch model.phase {
                case .processing:
                    ProgressView("Building room…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                case .finished:
                    savePanel
                case .failed(let message):
                    Text(message)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                default:
                    EmptyView()
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var savePanel: some View {
        VStack(spacing: 12) {
            TextField("Room name", text: $name)
                .textFieldStyle(.roundedBorder)
            if let saveError { Text(saveError).foregroundStyle(.red).font(.footnote) }
            Button("Save Scan") {
                guard let room = model.room else { return }
                do {
                    try store.save(room: room, mesh: model.mesh, name: name)
                    dismiss()
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
