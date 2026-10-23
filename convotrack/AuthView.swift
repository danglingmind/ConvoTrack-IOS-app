import SwiftUI
import ClerkKit
import AuthenticationServices

/// Whether the next Google sign-in must run in a fresh, cookie-free web session.
///
/// `ASWebAuthenticationSession` shares Safari's cookie jar by default, and that is what makes the
/// sign-in after a sign-out silent: Google still holds a session for the account that just left,
/// sees exactly one signed-in identity, skips the account chooser entirely and hands that same
/// identity straight back. Nothing in the app can ask for the chooser directly — the OAuth
/// `prompt=select_account` parameter is supported by Clerk's API but not exposed by ClerkKit's
/// sign-in flow — so the cookie jar is the only lever there is.
///
/// Running ephemeral ALWAYS would make every rider type their Google password on a fresh install,
/// where there is no stale identity to escape in the first place. So it is armed by a sign-out and
/// disarmed by the sign-in that follows it: the first sign-in on a device stays one tap, and the
/// one after a sign-out lets you pick the account.
enum WebSignInSession {
    private static let key = "convotrack.needsAccountChoice"

    static var needsAccountChoice: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The system "Continue with Apple" button (`ASAuthorizationAppleIDButton`), so its logo, label and
/// proportions follow Apple's guidelines. Authorisation itself still runs through Clerk, so this
/// only reports the tap.
private struct AppleContinueButton: UIViewRepresentable {
    var isEnabled: Bool
    var action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        // White on a dark background; 18 pt corners to match the Google button.
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
        button.cornerRadius = DS.Radius.button
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        uiView.isEnabled = isEnabled
        uiView.alpha = isEnabled ? 1 : 0.6
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

struct AuthView: View {
    /// When set, the host (ContentView) owns what comes next. When nil, AuthView presents
    /// MainTabView itself — the previous behaviour, kept for previews.
    var onAuthenticated: (() -> Void)? = nil

    @Environment(Clerk.self) private var clerk
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var membershipStore: MembershipStore
    @State private var navigateToMain = false
    @State private var appeared = false
    @State private var signingInProvider: AuthProvider?
    @State private var errorMessage: String?

    private enum AuthProvider {
        case google, apple
    }

    var body: some View {
        ZStack {
            heroBackground

            // Two equal halves: brand centred in the top, sign-in centred in the bottom.
            VStack(spacing: 0) {
                brandHeader
                    .frame(maxHeight: .infinity)
                VStack(spacing: DS.Space.p8) {
                    authButtons
                    footerSection
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, DS.Space.screenInset)
            .padding(.vertical, DS.Space.p6)
        }
        .preferredColorScheme(.dark)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            #if DEBUG
            // `-authHold YES` keeps this screen up for design review even when signed in.
            if clerk.user != nil, !UserDefaults.standard.bool(forKey: "authHold") { finishAuth() }
            #else
            if clerk.user != nil { finishAuth() }
            #endif
            withAnimation(DS.Motion.emphasized) { appeared = true }
        }
        .fullScreenCover(isPresented: $navigateToMain) {
            MainTabView()
                .environmentObject(membershipStore)
        }
    }

    // MARK: - Hero Background

    /// Bundled road photo fading into the base (was a remote URL).
    private var heroBackground: some View {
        ZStack {
            DSScreenBackground()
            DSHeroPhoto(imageName: "hero_road_sunset", height: nil)
                .ignoresSafeArea()
            // Sunset photos are bright: dim them so the tagline and sign-in copy stay legible.
            DS.Surface.scrim.ignoresSafeArea().allowsHitTesting(false)
        }
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        VStack(spacing: DS.Space.p3) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .accessibilityHidden(true)

            Text("ConvoTrack")
                .dsText(.brandWordmark)
                .foregroundStyle(DS.Text.primary)
                .lineLimit(1)
                .dsShadow(DS.Shadow.textOnPhoto)
                .accessibilityAddTraits(.isHeader)

            Text("Ride together in real time")
                .dsText(.eyebrow)
                .foregroundStyle(DS.Text.secondary)
                .dsShadow(DS.Shadow.textOnPhoto)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Auth Buttons

    /// Apple first (white, system button), Google below at the same size (dark with an outline).
    /// No lime: neither provider is "the next action".
    private var authButtons: some View {
        VStack(spacing: DS.Space.p3) {
            Text("Sign in to keep your rides and ride with others.")
                .dsText(.bodySmall)
                .foregroundStyle(DS.Text.primary)
                .dsShadow(DS.Shadow.textOnPhoto)
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.Space.p1)

            ZStack {
                AppleContinueButton(isEnabled: signingInProvider == nil, action: signInWithApple)
                    .frame(height: DS.Target.button)
                if signingInProvider == .apple { ProgressView().tint(.black) }
            }
            .frame(maxWidth: 400)

            googleButton
                .frame(maxWidth: 400)

            if let errorMessage {
                DSInlineError(message: LocalizedStringKey(errorMessage))
                    .padding(.top, DS.Space.p1)
            }
        }
    }

    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            ZStack {
                if signingInProvider == .google {
                    ProgressView().tint(DS.Text.primary.base)
                } else {
                    Text("Continue with Google")
                        .dsText(.rowTitle)
                        .foregroundStyle(DS.Text.primary)
                    // The G sits on a 32 pt white disc, 16 pt from the leading edge.
                    HStack {
                        GoogleGIcon()
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                            .padding(.leading, DS.Space.p4)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Target.button)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .stroke(DS.Border.strong, lineWidth: DS.BorderWidth.default)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .disabled(signingInProvider != nil)
        .accessibilityLabel(Text("Continue with Google"))
    }

    private func finishAuth() {
        if let onAuthenticated { onAuthenticated() } else { navigateToMain = true }
    }

    // MARK: - Auth Actions

    private func signInWithGoogle() {
        signingInProvider = .google
        errorMessage = nil
        Analytics.capture(.signInStarted, ["method": "google"])
        Task {
            do {
                try await clerk.auth.signInWithOAuth(
                    provider: .google,
                    prefersEphemeralWebBrowserSession: WebSignInSession.needsAccountChoice
                )
                // Cleared only on success: an abandoned or failed attempt leaves the rider exactly
                // where they were, still needing the chooser next time.
                WebSignInSession.needsAccountChoice = false
                Analytics.capture(.signInSucceeded, ["method": "google"])
                finishAuth()
            } catch {
                Analytics.capture(.signInFailed, ["method": "google"])
                errorMessage = error.riderMessage
            }
            signingInProvider = nil
        }
    }

    private func signInWithApple() {
        signingInProvider = .apple
        errorMessage = nil
        Analytics.capture(.signInStarted, ["method": "apple"])
        Task {
            do {
                try await clerk.auth.signInWithApple()
                Analytics.capture(.signInSucceeded, ["method": "apple"])
                finishAuth()
            } catch {
                Analytics.capture(.signInFailed, ["method": "apple"])
                errorMessage = error.riderMessage
            }
            signingInProvider = nil
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: DS.Space.p1) {
            DSTextButton(title: "Terms", role: .dismiss) {
                openURL(URL(string: AppURLs.termsOfService)!)
            }
            Circle().fill(DS.Accent.soft).frame(width: 5, height: 5).accessibilityHidden(true)
            DSTextButton(title: "Privacy", role: .dismiss) {
                openURL(URL(string: AppURLs.privacyPolicy)!)
            }
        }
    }
}

// MARK: - Google G Icon (4-color, exact SVG path conversion)

struct GoogleGIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24.0

            // Blue — right hook of G (M22.56 12.25 c0-.78-.07-1.53-.2-2.25 H12 v4.26 h5.92 c-.26 1.37-1.04 2.53-2.21 3.31 v2.77 h3.57 c2.08-1.92 3.28-4.74 3.28-8.09 z)
            var blue = Path()
            blue.move(to: CGPoint(x: 22.56 * s, y: 12.25 * s))
            blue.addCurve(
                to:       CGPoint(x: 22.36 * s, y: 10.00 * s),
                control1: CGPoint(x: 22.56 * s, y: 11.47 * s),
                control2: CGPoint(x: 22.49 * s, y: 10.72 * s))
            blue.addLine(to: CGPoint(x: 12.00 * s, y: 10.00 * s))
            blue.addLine(to: CGPoint(x: 12.00 * s, y: 14.26 * s))
            blue.addLine(to: CGPoint(x: 17.92 * s, y: 14.26 * s))
            blue.addCurve(
                to:       CGPoint(x: 15.71 * s, y: 17.57 * s),
                control1: CGPoint(x: 17.66 * s, y: 15.63 * s),
                control2: CGPoint(x: 16.88 * s, y: 16.79 * s))
            blue.addLine(to: CGPoint(x: 15.71 * s, y: 20.34 * s))
            blue.addLine(to: CGPoint(x: 19.28 * s, y: 20.34 * s))
            blue.addCurve(
                to:       CGPoint(x: 22.56 * s, y: 12.25 * s),
                control1: CGPoint(x: 21.36 * s, y: 18.42 * s),
                control2: CGPoint(x: 22.56 * s, y: 15.60 * s))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(hex: "4285F4")))

            // Green — bottom arc (M12 23 c2.97 0 5.46-.98 7.28-2.66 l-3.57-2.77 c-.98.66-2.23 1.06-3.71 1.06 -2.86 0-5.29-1.93-6.16-4.53 H2.18 v2.84 C3.99 20.53 7.7 23 12 23 z)
            var green = Path()
            green.move(to: CGPoint(x: 12.00 * s, y: 23.00 * s))
            green.addCurve(
                to:       CGPoint(x: 19.28 * s, y: 20.34 * s),
                control1: CGPoint(x: 14.97 * s, y: 23.00 * s),
                control2: CGPoint(x: 17.46 * s, y: 22.02 * s))
            green.addLine(to: CGPoint(x: 15.71 * s, y: 17.57 * s))
            green.addCurve(
                to:       CGPoint(x: 12.00 * s, y: 18.63 * s),
                control1: CGPoint(x: 14.73 * s, y: 18.23 * s),
                control2: CGPoint(x: 13.48 * s, y: 18.63 * s))
            green.addCurve(
                to:       CGPoint(x: 5.84 * s, y: 14.10 * s),
                control1: CGPoint(x:  9.14 * s, y: 18.63 * s),
                control2: CGPoint(x:  6.71 * s, y: 16.70 * s))
            green.addLine(to: CGPoint(x:  2.18 * s, y: 14.10 * s))
            green.addLine(to: CGPoint(x:  2.18 * s, y: 16.94 * s))
            green.addCurve(
                to:       CGPoint(x: 12.00 * s, y: 23.00 * s),
                control1: CGPoint(x:  3.99 * s, y: 20.53 * s),
                control2: CGPoint(x:  7.70 * s, y: 23.00 * s))
            green.closeSubpath()
            context.fill(green, with: .color(Color(hex: "34A853")))

            // Yellow — left arc (M5.84 14.09 c-.22-.66-.35-1.36-.35-2.09 s.13-1.43.35-2.09 V7.07 H2.18 C1.43 8.55 1 10.22 1 12 s.43 3.45 1.18 4.93 l3.66-2.84 z)
            var yellow = Path()
            yellow.move(to: CGPoint(x: 5.84 * s, y: 14.09 * s))
            yellow.addCurve(
                to:       CGPoint(x: 5.49 * s, y: 12.00 * s),
                control1: CGPoint(x: 5.62 * s, y: 13.43 * s),
                control2: CGPoint(x: 5.49 * s, y: 12.73 * s))
            // s command: reflected control1 = 2*(5.49,12)-(5.49,12.73) = (5.49, 11.27)
            yellow.addCurve(
                to:       CGPoint(x: 5.84 * s, y:  9.91 * s),
                control1: CGPoint(x: 5.49 * s, y: 11.27 * s),
                control2: CGPoint(x: 5.62 * s, y: 10.57 * s))
            yellow.addLine(to: CGPoint(x: 5.84 * s, y:  7.07 * s))
            yellow.addLine(to: CGPoint(x: 2.18 * s, y:  7.07 * s))
            yellow.addCurve(
                to:       CGPoint(x: 1.00 * s, y: 12.00 * s),
                control1: CGPoint(x: 1.43 * s, y:  8.55 * s),
                control2: CGPoint(x: 1.00 * s, y: 10.22 * s))
            // s command: reflected control1 = 2*(1,12)-(1,10.22) = (1, 13.78)
            yellow.addCurve(
                to:       CGPoint(x: 2.18 * s, y: 16.93 * s),
                control1: CGPoint(x: 1.00 * s, y: 13.78 * s),
                control2: CGPoint(x: 1.43 * s, y: 15.45 * s))
            yellow.addLine(to: CGPoint(x: 5.84 * s, y: 14.09 * s))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(hex: "FBBC05")))

            // Red — top arc (M12 5.38 c1.62 0 3.06.56 4.21 1.64 l3.15-3.15 C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07 l3.66 2.84 c.87-2.6 3.3-4.53 6.16-4.53 z)
            var red = Path()
            red.move(to: CGPoint(x: 12.00 * s, y:  5.38 * s))
            red.addCurve(
                to:       CGPoint(x: 16.21 * s, y:  7.02 * s),
                control1: CGPoint(x: 13.62 * s, y:  5.38 * s),
                control2: CGPoint(x: 15.06 * s, y:  5.94 * s))
            red.addLine(to: CGPoint(x: 19.36 * s, y:  3.87 * s))
            red.addCurve(
                to:       CGPoint(x: 12.00 * s, y:  1.00 * s),
                control1: CGPoint(x: 17.45 * s, y:  2.09 * s),
                control2: CGPoint(x: 14.97 * s, y:  1.00 * s))
            red.addCurve(
                to:       CGPoint(x:  2.18 * s, y:  7.07 * s),
                control1: CGPoint(x:  7.70 * s, y:  1.00 * s),
                control2: CGPoint(x:  3.99 * s, y:  3.47 * s))
            red.addLine(to: CGPoint(x:  5.84 * s, y:  9.91 * s))
            red.addCurve(
                to:       CGPoint(x: 12.00 * s, y:  5.38 * s),
                control1: CGPoint(x:  6.71 * s, y:  7.31 * s),
                control2: CGPoint(x:  9.14 * s, y:  5.38 * s))
            red.closeSubpath()
            context.fill(red, with: .color(Color(hex: "EA4335")))
        }
        .frame(width: 24, height: 24)
    }
}

#Preview {
    AuthView()
}
