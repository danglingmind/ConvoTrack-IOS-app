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

// Full-screen scanner (presented with `.fullScreenCover`: it is a camera view, and the Join sheet
// beneath it must not become a nested sheet).
struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var onCode: (String) -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// Brackets flash accent-bright for 120 ms when a code is read.
    @State private var flash = false

    var body: some View {
        ZStack {
            switch cameraPermission {
            case .authorized:
                scannerContent
            case .notDetermined:
                permissionRequestView
            default:
                permissionDeniedView
            }
        }
        .overlay(alignment: .topLeading) {
            DSFloatingButton(systemImage: "xmark", label: "Close") { dismiss() }
                .padding(.leading, DS.Space.screenInset)
                .padding(.top, DS.Space.p2)
        }
        .preferredColorScheme(.dark)
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
            Color.black.ignoresSafeArea()

            QRScannerView { code in
                DSHaptic.selection()
                flash = true
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    dismiss()
                    onCode(code)
                }
            }
            .ignoresSafeArea()

            // 260 pt viewfinder: 56% scrim outside it, accent brackets on it.
            GeometryReader { proxy in
                let side: CGFloat = 260
                let frame = CGRect(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2, width: side, height: side)
                ZStack {
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: proxy.size))
                        p.addRoundedRect(in: frame, cornerSize: CGSize(width: DS.Radius.lg, height: DS.Radius.lg))
                    }
                    .fill(DS.Surface.scrim, style: FillStyle(eoFill: true))
                    QRCornerBrackets(color: flash ? DS.Accent.bright : DS.Accent.base)
                        .frame(width: side, height: side)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                Spacer()
                DSGlassPill {
                    Text("Point at a ConvoTrack QR code")
                        .dsText(.buttonPill)
                        .foregroundStyle(DS.Text.onPhoto)
                        .padding(.vertical, DS.Space.p1)
                }
                .padding(.bottom, DS.Space.p12)
            }
        }
    }

    private var permissionRequestView: some View {
        permissionLayout(
            systemImage: "camera",
            tint: DS.Accent.base,
            disc: DS.Accent.tint,
            title: "Camera Access Required",
            message: "ConvoTrack needs camera access to scan QR codes."
        ) {
            DSPrimaryButton(title: "Continue") {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraPermission = granted ? .authorized : .denied
                    }
                }
            }
        }
        .background { DSScreenBackground() }
    }

    private var permissionDeniedView: some View {
        permissionLayout(
            systemImage: "camera.badge.ellipsis",
            tint: DS.Status.danger,
            disc: DS.Status.dangerTint,
            title: "Camera Access Denied",
            message: "Enable camera access in Settings to scan QR codes."
        ) {
            VStack(spacing: DS.Space.p3) {
                DSPrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                DSSecondaryButton(title: "Close") { dismiss() }
            }
        }
        .background {
            ZStack(alignment: .top) {
                DSScreenBackground()
                DS.Gradient.dangerAura(endRadius: 420).ignoresSafeArea()
            }
        }
    }

    private func permissionLayout<Actions: View>(
        systemImage: String, tint: Color, disc: Color,
        title: LocalizedStringKey, message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: DS.Space.p6) {
            Image(systemName: systemImage)
                .dsIcon(30, weight: .medium)
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(disc, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.p2) {
                Text(title).dsText(.titleLarge).foregroundStyle(DS.Text.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message).dsText(.body).foregroundStyle(DS.Text.secondary)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(.horizontal, DS.Space.p8)
        .frame(maxWidth: DS.Space.contentMaxWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }
}
