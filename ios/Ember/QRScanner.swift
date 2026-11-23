import SwiftUI
import AVFoundation

/// Scans the bridge key QR code made by the key generator page.
/// Accepts "EMBER-KEY:<64 hex>" or just the 64 hex characters.
struct KeyScannerSheet: View {
    let onKey: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                QRCameraView { text in
                    if let key = KeyScannerSheet.key(from: text) {
                        Haptics.success()
                        onKey(key)
                        dismiss()
                    } else {
                        problem = "That QR code isn't an Ember bridge key."
                    }
                } onError: { problem = $0 }
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 250, height: 250)

                VStack {
                    Spacer()
                    Text(problem ?? "Point the camera at the QR code from the key generator.")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .glassCard(16)
                        .padding(24)
                }
            }
            .navigationTitle("Scan bridge key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    static func key(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.uppercased().hasPrefix("EMBER-KEY:") { t = String(t.dropFirst("EMBER-KEY:".count)) }
        return SecretStore.parseHex(t) != nil ? t.lowercased() : nil
    }
}

/// Camera preview that reports the first QR code it sees.
struct QRCameraView: UIViewRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            DispatchQueue.main.async { onError("The camera isn't available. Allow camera access for Ember in iPhone Settings, or paste the key instead.") }
            return view
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async { session?.stopRunning() }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        var session: AVCaptureSession?
        private var lastCode: String?
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  code != lastCode else { return }
            lastCode = code
            onCode(code)
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
