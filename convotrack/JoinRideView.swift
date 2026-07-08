import SwiftUI

struct JoinRideView: View {
    var prefillCode: String? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""
    @State private var ridePreview: InviteCodeResponse? = nil
    @State private var isLookingUp = false
    @State private var isJoining = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var showScanner = false

    private var normalizedCode: String {
        String(inviteCode.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }
    private var codeReady: Bool { normalizedCode.count == 6 }

    // If the user is already in the looked-up ride, skip the join API call
    private var alreadyInThisRide: Bool {
        guard let preview = ridePreview else { return false }
        return preview.rideId == appState.currentRideId
    }

    private var canJoin: Bool { ridePreview != nil && !isJoining }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceDim.ignoresSafeArea()
                    .overlay(
                        Canvas { ctx, size in
                            for x in stride(from: 0, to: size.width, by: 24) {
                                for y in stride(from: 0, to: size.height, by: 24) {
                                    let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.05)))
                                }
                            }
                        }
                    )

                ScrollView {
                    VStack(spacing: 32) {
                        heroSection

                        codeInputSection

                        // Divider
                        HStack(spacing: 16) {
                            Rectangle().frame(height: 1).foregroundColor(Color.outlineVariant.opacity(0.3))
                            Text("OR").font(.labelCaps).foregroundColor(Color.outline).tracking(2)
                            Rectangle().frame(height: 1).foregroundColor(Color.outlineVariant.opacity(0.3))
                        }

                        qrSection

                        joinButton

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            if let code = prefillCode, !code.isEmpty {
                inviteCode = code
                await lookupCode(code)
            }
        }
        .alert("Couldn't Join", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An error occurred. Please try again.")
        }
    }

    // MARK: - Hero Section (transforms when a ride is verified)

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuC5cr7RP__6cnlzy_FXSEwHuecBdhk1z8CjevrsLSh8580yPlvkaGAOgKvltHeI3SpSDe6BhCU-Wh0qivmOF65xwbO6Ok0rUgGwk3aJa3DBENGrwCrvoYok04hFxnERzE-xfJ2Cdd-w8UKnM51pdZnvnL7NmnzuWqZ_g5FXV-M4B0YoY5pLaeyM_S1Oexr5oUi51eUzZtsMsdzrnpdw-AcAfGEvftwpZ73YRHSxFdIQMRDU9tEkk2583rH7GxfwZ2X56DbQuZs9EjA")) { image in
                image.resizable().scaledToFill()
                    .opacity(ridePreview != nil ? 0.25 : 0.4)
            } placeholder: {
                Color.surfaceContainerLow
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, Color.surfaceDim], startPoint: .top, endPoint: .bottom))

            // Content area switches between placeholder and real ride info
            Group {
                if let preview = ridePreview {
                    verifiedRideInfo(preview)
                } else {
                    standbyInfo
                }
            }
            .padding(16)
        }
        .frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    ridePreview != nil ? Color.primaryFixed.opacity(0.6) : Color.outlineVariant.opacity(0.3),
                    lineWidth: ridePreview != nil ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: ridePreview != nil)
    }

    private var standbyInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYSTEM: STANDBY")
                .font(.labelCaps)
                .foregroundColor(Color.primaryFixed)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.surfaceContainerHighest)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .tracking(2)
            Text("Ready to Connect")
                .font(.headlineMd)
                .foregroundColor(Color.onSurface)
            if isLookingUp {
                HStack(spacing: 6) {
                    ProgressView().tint(Color.primaryFixed).scaleEffect(0.8)
                    Text("Verifying code...").font(.bodyMd).foregroundColor(Color.onSurfaceVariant)
                }
            } else {
                Text("Enter the 6-character code from your Ride Leader")
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
            }
        }
    }

    private func verifiedRideInfo(_ preview: InviteCodeResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(alreadyInThisRide ? "YOUR RIDE" : "CODE VERIFIED")
                    .font(.labelCaps)
                    .foregroundColor(Color.onPrimaryFixed)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primaryFixed)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .tracking(2)
                if alreadyInThisRide {
                    Text("You're the leader")
                        .font(.labelCaps)
                        .foregroundColor(Color.primaryFixed)
                        .tracking(1)
                }
            }
            Text(preview.title)
                .font(.headlineMd)
                .foregroundColor(Color.onSurface)
            HStack(spacing: 8) {
                Label(preview.leaderName, systemImage: "person.fill")
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
                Text("·")
                    .foregroundColor(Color.outline)
                Label("\(preview.participantCount)/\(preview.maxParticipants)", systemImage: "person.3.fill")
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
            }
        }
    }

    // MARK: - Code Input

    private var codeInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").font(.system(size: 16)).foregroundColor(Color.primaryFixed)
                Text("ENTER INVITE CODE")
                    .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(4)
            }

            ZStack(alignment: .trailing) {
                TextField("A1B2C3", text: $inviteCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.primaryFixed)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceContainerHighest)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(codeReady ? Color.primaryFixed : Color.outlineVariant, lineWidth: 2)
                    )
                    .onChange(of: inviteCode) { _, newValue in
                        ridePreview = nil
                        errorMessage = nil
                        // Sanitize: uppercase, alphanumeric only, max 6
                        let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if cleaned != newValue { inviteCode = cleaned }
                        if cleaned.count == 6 {
                            Task { await lookupCode(cleaned) }
                        }
                    }

                if isLookingUp {
                    ProgressView().tint(Color.primaryFixed).padding(.trailing, 16)
                } else {
                    Image(systemName: codeReady ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(codeReady ? Color.primaryFixed : Color.outlineVariant)
                        .padding(.trailing, 16)
                }
            }

            Text("6-character code shared by the Ride Leader. Case-insensitive.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
        }
    }

    // MARK: - QR Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 18)).foregroundColor(Color.primaryFixed)
                Text("SCAN QR CODE")
                    .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(4)
            }

            Button(action: { showScanner = true }) {
                ZStack {
                    Color.surfaceContainerLow
                    QRCornerBrackets()
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.system(size: 36)).foregroundColor(Color.primaryFixed)
                        Text("TAP TO SCAN").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(4)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant, lineWidth: 2))
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { code in
                    inviteCode = code
                    Task { await lookupCode(code) }
                }
            }
        }
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button(action: { Task { await joinRide() } }) {
            HStack(spacing: 12) {
                if isJoining {
                    ProgressView().tint(Color.onPrimaryFixed)
                } else if alreadyInThisRide {
                    Text("OPEN LOBBY").font(.headlineMd).tracking(4)
                    Image(systemName: "arrow.right")
                } else {
                    Text("JOIN RIDE").font(.headlineMd).tracking(4)
                    Image(systemName: "bolt.fill")
                }
            }
            .modifier(LimePrimaryButton())
        }
        .disabled(!canJoin)
        .opacity(canJoin ? 1 : 0.5)
    }

    // MARK: - API Calls

    private func lookupCode(_ code: String) async {
        isLookingUp = true
        ridePreview = nil
        do {
            let preview = try await APIClient.shared.getRideByInviteCode(code)
            ridePreview = preview
        } catch let error as APIClientError {
            switch error {
            case .serverError(let msg) where msg.contains("INVITE_CODE_NOT_FOUND") || msg.contains("404") || msg.contains("NOT_FOUND"):
                errorMessage = "No ride found with this code. Double-check and try again."
                showError = true
            case .serverError(let msg) where msg.contains("RIDE_ENDED"):
                errorMessage = "This ride has already ended."
                showError = true
            default:
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLookingUp = false
    }

    private func joinRide() async {
        guard let preview = ridePreview else { return }

        // Already in this ride — just open the lobby
        if alreadyInThisRide {
            dismiss()
            return
        }

        isJoining = true
        do {
            try await APIClient.shared.joinRide(preview.rideId)
            appState.currentRideId = preview.rideId
            appState.inviteCode = normalizedCode
            appState.currentRide = nil
            dismiss()
        } catch let error as APIClientError {
            switch error {
            case .serverError(let msg):
                if msg.contains("RIDE_FULL") {
                    errorMessage = "This ride is full."
                } else if msg.contains("ALREADY") || msg.contains("already") || msg.contains("BAD_REQUEST") {
                    // Already a participant — treat as success and navigate to lobby
                    appState.currentRideId = preview.rideId
                    appState.inviteCode = normalizedCode
                    appState.currentRide = nil
                    dismiss()
                    return
                } else if msg.contains("QUOTA_EXCEEDED") {
                    errorMessage = "You're already in another active ride. End it before joining a new one."
                } else if msg.contains("RIDE_ENDED") {
                    errorMessage = "This ride has already ended."
                } else {
                    errorMessage = "Couldn't join: \(msg)"
                }
                showError = true
            default:
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isJoining = false
    }
}

struct QRCornerBrackets: View {
    let bracketSize: CGFloat = 32
    let lineWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 16, y: 16 + bracketSize))
                    p.addLine(to: CGPoint(x: 16, y: 16))
                    p.addLine(to: CGPoint(x: 16 + bracketSize, y: 16))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - 16 - bracketSize, y: 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: 16 + bracketSize))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Path { p in
                    p.move(to: CGPoint(x: 16, y: geo.size.height - 16 - bracketSize))
                    p.addLine(to: CGPoint(x: 16, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: 16 + bracketSize, y: geo.size.height - 16))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - 16 - bracketSize, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: geo.size.height - 16))
                    p.addLine(to: CGPoint(x: geo.size.width - 16, y: geo.size.height - 16 - bracketSize))
                }.stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }
}

#Preview {
    JoinRideView()
        .environmentObject(AppState())
}
