import SwiftUI

struct JoinRideView: View {
    var prefillCode: String? = nil

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var paywall: PaywallPresenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var inviteCode = ""
    @State private var ridePreview: InviteCodeResponse? = nil
    @State private var isLookingUp = false
    @State private var isJoining = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var showScanner = false
    /// The last join was refused for a plan reason (trial over / monthly rides used up).
    @State private var joinBlockedByPlan = false

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
                DSScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                        heroSection

                        // The active Join button sits directly beneath the verified ride details so
                        // it's reachable without scrolling to the bottom. Hidden until a ride is
                        // looked up (via code, link, or QR).
                        if ridePreview != nil {
                            DSPrimaryButton(
                                title: alreadyInThisRide ? "Open lobby" : "Join ride",
                                systemImage: alreadyInThisRide ? "arrow.right" : "bolt.fill",
                                isLoading: isJoining
                            ) { Task { await joinRide() } }
                            .disabled(!canJoin)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let errorMessage {
                            DSInlineError(message: LocalizedStringKey(errorMessage))
                        }
                        if joinBlockedByPlan {
                            DSPrimaryButton(title: "See Pro plans", systemImage: "rosette") { openPaywall() }
                        }

                        codeInputSection

                        DSOrDivider()

                        qrSection
                    }
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.top, DS.Space.p2)
                    .padding(.bottom, DS.Space.p10)
                    .dsAnimation(DS.Motion.standard, value: ridePreview != nil)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A way out other than swiping the sheet away.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Surface.sheet)
        .preferredColorScheme(.dark)
        .task {
            if let code = prefillCode, !code.isEmpty {
                inviteCode = code
                await lookupCode(code)
            }
        }
        // The scanner is a camera view, so it is full screen rather than a second sheet on top
        // of this one (one sheet at a time).
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerSheet { code in
                inviteCode = code
                Task { await lookupCode(code) }
            }
        }
    }

    // MARK: - Hero (standby → verified)

    private var heroSection: some View {
        let verified = ridePreview != nil
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        return Group {
            if let preview = ridePreview {
                verifiedRideInfo(preview)
            } else {
                standbyInfo
            }
        }
        .padding(DS.Space.p4)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottomLeading)
        .background {
            ZStack {
                // Standby is a card; verified is the accent tint.
                if verified { shape.fill(DS.Accent.tint) } else { shape.fill(DS.Surface.card) }
                DotGrid()
            }
        }
        .clipShape(shape)
        .overlay(
            shape.stroke(verified ? AnyShapeStyle(DS.Accent.border) : AnyShapeStyle(DS.Border.subtle),
                         lineWidth: verified ? DS.BorderWidth.emphasis : DS.BorderWidth.default)
        )
        .accessibilityElement(children: .combine)
    }

    private var standbyInfo: some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            DSChip(title: "System: Standby", variant: .neutral)
            Text("Ready to Connect")
                .dsText(.titleLarge)
                .foregroundStyle(DS.Text.primary)
            if isLookingUp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).tint(DS.Accent.base)
                    Text("Verifying code…").dsText(.bodySmall).foregroundStyle(DS.Text.muted)
                }
            } else {
                Text("Enter the 6-character code from your Ride Leader")
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.muted)
            }
        }
    }

    private func verifiedRideInfo(_ preview: InviteCodeResponse) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            DSAdaptiveStack(spacing: DS.Space.p2) {
                DSChip(title: alreadyInThisRide ? "Your ride" : "Code verified", variant: .positive)
                if alreadyInThisRide {
                    Text("You're the leader").dsText(.badge).foregroundStyle(DS.Accent.base)
                }
            }
            Text(preview.title)
                .dsText(.titleLarge)
                .foregroundStyle(DS.Text.primary)
            DSAdaptiveStack(spacing: DS.Space.p2) {
                Label(preview.leaderName, systemImage: "person.fill")
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.secondary)
                Label("\(preview.participantCount)/\(preview.maxParticipants)", systemImage: "person.3.fill")
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
    }

    // MARK: - Code Input

    private var codeInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Enter invite code", systemImage: "key")
            DSCodeInput(text: $inviteCode, kind: .invite, length: 6, isVerifying: isLookingUp)
                .onChange(of: inviteCode) { _, newValue in
                    ridePreview = nil
                    errorMessage = nil
                    joinBlockedByPlan = false
                    // Sanitize: uppercase, alphanumeric only, max 6
                    let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if cleaned != newValue { inviteCode = cleaned }
                    if cleaned.count == 6 {
                        Task { await lookupCode(cleaned) }
                    }
                }
            Text("6-character code shared by the Ride Leader. Case-insensitive.")
                .dsText(.bodySmall)
                .foregroundStyle(DS.Text.muted)
                .padding(.top, DS.Space.p3)
        }
    }

    // MARK: - QR Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Scan QR code", systemImage: "camera")
            Button { showScanner = true } label: {
                ZStack {
                    QRCornerBrackets()
                    VStack(spacing: DS.Space.p3) {
                        Image(systemName: "camera")
                            .dsIcon(30, weight: .medium)
                            .foregroundStyle(DS.Accent.base)
                            .frame(width: 64, height: 64)
                            .background(DS.Accent.tint, in: Circle())
                        Text("Tap to scan").dsText(.buttonPill).foregroundStyle(DS.Accent.base)
                    }
                }
                .frame(width: 260, height: 260)
                .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle(scale: 0.98))
            .accessibilityLabel(Text("Scan QR code"))
        }
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
                errorMessage = UserFacingError.message(forCode: "INVITE_CODE_NOT_FOUND")
                    ?? UserFacingError.generic
                showError = true
            case .serverError(let msg) where msg.contains("RIDE_ENDED"):
                errorMessage = UserFacingError.message(forCode: "RIDE_ENDED") ?? UserFacingError.generic
                showError = true
            default:
                errorMessage = error.riderMessage
                showError = true
            }
        } catch {
            errorMessage = error.riderMessage
            showError = true
        }
        isLookingUp = false
    }

    /// The paywall is a sibling sheet on `MainTabView`, and a view can't present a second sheet
    /// while this one is up — so close this sheet first and open the paywall once it has gone.
    private func openPaywall() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            paywall.present(.joinBlocked)
        }
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
                if msg.contains("ALREADY") || msg.contains("already") || msg.contains("BAD_REQUEST") {
                    // Already a participant — treat as success and navigate to lobby
                    appState.currentRideId = preview.rideId
                    appState.inviteCode = normalizedCode
                    appState.currentRide = nil
                    dismiss()
                    return
                }
                // Everything else takes its wording from the central map, so a code this switch
                // hasn't heard of can no longer reach the rider as "Couldn't join: QUOTA_EXCEEDED".
                errorMessage = error.riderMessage
                joinBlockedByPlan = error.isPlanLimit
                showError = true
            default:
                errorMessage = error.riderMessage
                showError = true
            }
        } catch {
            errorMessage = error.riderMessage
            showError = true
        }
        isJoining = false
    }
}

/// Dot-grid texture (1.2 pt dots every 24 pt) for the Join hero.
private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            for x in stride(from: 12.0, to: size.width, by: 24) {
                for y in stride(from: 12.0, to: size.height, by: 24) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(DS.Control.dotGrid))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Accent corner brackets (32 pt long, 4 pt stroke, 16 pt inset, round caps).
struct QRCornerBrackets: View {
    var color: Color = DS.Accent.base
    let bracketSize: CGFloat = 32
    let lineWidth: CGFloat = 4
    let inset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // top-leading
                p.move(to: CGPoint(x: inset, y: inset + bracketSize))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + bracketSize, y: inset))
                // top-trailing
                p.move(to: CGPoint(x: w - inset - bracketSize, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + bracketSize))
                // bottom-leading
                p.move(to: CGPoint(x: inset, y: h - inset - bracketSize))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + bracketSize, y: h - inset))
                // bottom-trailing
                p.move(to: CGPoint(x: w - inset - bracketSize, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - bracketSize))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    JoinRideView()
        .environmentObject(AppState())
        .environmentObject(PaywallPresenter())
}
