import AVFoundation
import SwiftUI

/// Live camera feed that reports the first STSA QR code it sees, once.
///
/// The counterpart to `QRCode`, which draws them. `AVCaptureMetadataOutput` does
/// the decoding, so there is no third-party scanner here for the same reason
/// there is no HTTP client — the platform already ships one.
struct CameraScanner: UIViewRepresentable {
    /// Handed the raw payload, prefix included. The session is already stopped
    /// by the time this fires, so it arrives exactly once per scan: the web
    /// scanner keeps its stream live across the validation round-trip, which
    /// lets one card fire several requests.
    let onScan: (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start(previewing: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    /// Hosting the preview in the view's *own* layer lets AutoLayout size it; a
    /// sublayer would need its frame kept by hand in `layoutSubviews`.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScan: (String) -> Void

        /// `AVCaptureSession` is an unannotated Objective-C class, so the
        /// compiler cannot see that AVFoundation documents `startRunning` and
        /// `stopRunning` as safe from any queue. The discipline this stands on:
        /// configuration happens once on the main actor before `start`, and
        /// after that only those two calls touch it, both on `queue`.
        nonisolated(unsafe) private let session = AVCaptureSession()

        /// `startRunning` blocks until the camera is configured — long enough to
        /// be visible as a hitch if it ran on the main actor.
        private let queue = DispatchQueue(label: "tw.stsa.memberapp.scanner")

        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
            super.init()
        }

        func start(previewing view: PreviewView) {
            view.previewLayer.session = session
            configure()
            resume()
        }

        // MARK: - Session

        private func configure() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            guard let device = Self.camera,
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            // Both lines have to come after `addOutput`: until the output is on a
            // session that has a camera, `.qr` is not among the types it will
            // accept and setting it traps.
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            focusUpClose(device)
        }

        /// A membership QR is held up close, where the default focus range hunts
        /// past it to the room behind.
        private func focusUpClose(_ device: AVCaptureDevice) {
            guard device.isAutoFocusRangeRestrictionSupported,
                  (try? device.lockForConfiguration()) != nil
            else { return }
            device.autoFocusRangeRestriction = .near
            device.unlockForConfiguration()
        }

        /// Prefers the virtual multi-camera devices, which let iOS fall back to
        /// the ultra-wide when the subject is nearer than the wide lens can
        /// focus — which is where a phone screen held out to be scanned sits.
        ///
        /// No torch: the thing being scanned is a lit screen, and a light on a
        /// glossy one only adds the glare that stops it scanning.
        private static var camera: AVCaptureDevice? {
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            ).devices.first
        }

        private func resume() {
            queue.async { [session] in
                guard !session.isRunning else { return }
                session.startRunning()
            }
        }

        func stop() {
            queue.async { [session] in
                guard session.isRunning else { return }
                session.stopRunning()
            }
        }

        // MARK: - Detection

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // Reduced to `[String]` here so that only Sendable values cross into
            // the main actor below.
            let payloads = metadataObjects.compactMap {
                ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
            }
            // The delegate queue *is* `.main`, so this is an assertion rather
            // than a hop. It has to stay synchronous with the frame that
            // triggered it: hopping through a `Task` would let the next frame's
            // codes slip past `hasScanned` before the first one lands.
            MainActor.assumeIsolated {
                deliver(payloads)
            }
        }

        private func deliver(_ payloads: [String]) {
            guard !hasScanned,
                  let payload = payloads.first(where: { $0.hasPrefix(MembershipValidator.prefix) })
            else { return }

            // Stopped before the payload goes out, so the frames already in
            // flight cannot open a second validation request.
            hasScanned = true
            stop()
            onScan(payload)
        }
    }
}
