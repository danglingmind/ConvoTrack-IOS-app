import SwiftUI
import VisionKit
import Vision
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var handled = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled, let item = addedItems.first,
                  case .barcode(let barcode) = item,
                  let raw = barcode.payloadStringValue else { return }
            handled = true
            dataScanner.stopScanning()

            let code = extractInviteCode(from: raw)
            guard code.count == 6 else {
                handled = false
                try? dataScanner.startScanning()
                return
            }
            onCode(code)
        }

        private func extractInviteCode(from raw: String) -> String {
            // convotrack://join/ABC123
            if let url = URL(string: raw),
               url.scheme == "convotrack",
               url.host == "join",
               let segment = url.pathComponents.first(where: { $0 != "/" }) {
                return String(segment.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            }
            // Plain 6-char code
            let plain = String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            return plain
        }
    }
}

// Full-screen scanner sheet with overlay UI
struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scannerAvailable: Bool = DataScannerViewController.isSupported && DataScannerViewController.isAvailable

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraPermission == .authorized && scannerAvailable {
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
            } else if cameraPermission == .notDetermined {
                permissionRequestView
            } else {
                permissionDeniedView
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
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
            Button("Allow Camera") {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        cameraPermission = granted ? .authorized : .denied
                        scannerAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
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
