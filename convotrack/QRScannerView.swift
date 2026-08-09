import SwiftUI
import AVFoundation

// AVFoundation-based QR scanner. Works on any device with a camera —
// avoids VisionKit's DataScannerViewController availability checks, which
// can report `false` even when the camera is fully authorized and leave
// the UI stuck on the "Open Settings" screen.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onFound = { raw in
            let code = Self.extractInviteCode(from: raw)
            guard code.count == 6 else { return false }
            onCode(code)
            return true
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    private static func extractInviteCode(from raw: String) -> String {
        if let url = URL(string: raw) {
            // convotrack://join/ABC123
            if url.scheme == "convotrack", url.host == "join",
               let segment = url.pathComponents.first(where: { $0 != "/" }) {
                return String(segment.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            }
            // https://convotrack.in/join/ABC123 (Universal Link) — validate the host to
            // match DeepLinkRouter.handle, so an off-domain link can't masquerade as an invite.
            if url.scheme == "https", url.host == AppURLs.joinLinkHost, url.path.hasPrefix(AppURLs.joinPathPrefix) {
                return String(url.lastPathComponent.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            }
        }
        // Plain 6-char code
        return String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }
}

// UIKit capture controller driving the live camera preview and QR detection.
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    // Returns true when the payload was a valid code and scanning should stop.
    var onFound: ((String) -> Bool)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "convotrack.qr.session")
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        // startRunning() blocks — keep it off the main thread.
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let raw = object.stringValue else { return }

        if onFound?(raw) == true {
            handled = true
            sessionQueue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }
    }
}

// Full-screen scanner sheet with overlay UI
struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var onCode: (String) -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraPermission {
            case .authorized:
                scannerContent
            case .notDetermined:
                permissionRequestView
            default:
                permissionDeniedView
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onChange(of: scenePhase) { _, phase in
            // Re-check when returning from Settings so a newly granted
            // permission takes effect without reopening the sheet.
            if phase == .active {
                cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private var scannerContent: some View {
        ZStack {
            QRScannerView { code in
                dismiss()
                onCode(code)
            }
            .ignoresSafeArea()

            // Overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(20)
                }
                Spacer()
                Text("Point at a ConvoTrack QR code")
                    .font(.labelCaps)
                    .foregroundColor(.white.opacity(0.8))
                    .tracking(2)
                    .padding(.bottom, 48)
            }
        }
    }

    private var permissionRequestView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.primaryFixed)
            Text("Camera Access Required")
                .font(.headlineMd)
                .foregroundColor(.white)
            Text("ConvoTrack needs camera access to scan QR codes.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Button("Continue") {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraPermission = granted ? .authorized : .denied
                    }
                }
            }
            .modifier(LimePrimaryButton())
            .padding(.horizontal, 40)
        }
        .padding(32)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.errorColor)
            Text("Camera Access Denied")
                .font(.headlineMd)
                .foregroundColor(.white)
            Text("Enable camera access in Settings to scan QR codes.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .modifier(LimePrimaryButton())
            .padding(.horizontal, 40)
            Button("Cancel") { dismiss() }
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
        }
        .padding(32)
    }
}
