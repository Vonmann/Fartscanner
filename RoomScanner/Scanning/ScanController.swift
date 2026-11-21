import UIKit
import SwiftUI
import ARKit
import RoomPlan

/// Hosts Apple's RoomCaptureView. We give it our own ARSession so we can also
/// grab the raw LiDAR mesh when the scan ends.
final class ScanController: UIViewController, RoomCaptureViewDelegate {
    let arSession = ARSession()
    private var captureView: RoomCaptureView!
    private var started = false

    var onResult: (@MainActor (CapturedRoom?, Error?) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView = RoomCaptureView(frame: view.bounds, arSession: arSession)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        view.addSubview(captureView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Copies the LiDAR mesh seen so far. Call before stop().
    func snapshotMesh() -> MeshData {
        let anchors = arSession.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        return MeshData(anchors: anchors)
    }

    func stop() {
        captureView.captureSession.stop()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let callback = onResult
        Task { @MainActor in callback?(processedResult, error) }
    }
}

@MainActor
final class ScanModel: ObservableObject {
    enum Phase: Equatable {
        case scanning, processing, finished, failed(String)
    }

    @Published var phase: Phase = .scanning
    private(set) var room: CapturedRoom?
    private(set) var mesh = MeshData()
    weak var controller: ScanController?

    func attach(_ c: ScanController) {
        controller = c
        c.onResult = { [weak self] room, error in
            guard let self else { return }
            if let room {
                self.room = room
                self.phase = .finished
            } else {
                self.phase = .failed(error?.localizedDescription ?? "The scan could not be processed.")
            }
        }
    }

    func finish() {
        guard phase == .scanning, let controller else { return }
        mesh = controller.snapshotMesh()
        phase = .processing
        controller.stop()
    }

    func cancel() {
        if phase == .scanning { controller?.stop() }
    }
}

struct RoomCaptureContainer: UIViewControllerRepresentable {
    let model: ScanModel

    func makeUIViewController(context: Context) -> ScanController {
        let c = ScanController()
        model.attach(c)
        return c
    }

    func updateUIViewController(_ uiViewController: ScanController, context: Context) {}
}
