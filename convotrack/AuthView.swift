import SwiftUI
import ClerkKit

struct AuthView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var membershipStore: MembershipStore
    @State private var navigateToMain = false
    @State private var appeared = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            heroBackground

            // All content within a single padded column — mirrors `main px-margin-mobile`
            VStack(spacing: 0) {
                brandHeader.padding(.top, 24)
                Spacer()
                authButtons
                Spacer()
                footerSection.padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if clerk.user != nil { navigateToMain = true }
            withAnimation(.easeIn(duration: 0.8)) { appeared = true }
        }
        .fullScreenCover(isPresented: $navigateToMain) {
            MainTabView()
                .environmentObject(membershipStore)
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Hero Background

    private var heroBackground: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDFAix39kXUcp78oqWlesjF3LCKq1VTeD9el_pMmGyuukwkTDIarfnJS3dQ3CcZCX7npcCHxySC-YVsFOIUbePy1AQi6sYoO2w737m_KxJ3O0zPw-IC7ZDFXWYUn_l2eCr4iNZJw7wGkbPSX0lmqTBeVn7sorLf3Xb9bUc9VAeXshZ8-OmWKRQ5R4XO8USOX6-7EDLmuel4-BeYuZyjw9e_oaLbpJmT1FqNidwmswNbqkLGzKVNClsQIyUjkhuP3dMCvOjMnUloytQ")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.surfaceContainerLow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .grayscale(0.3)
            .opacity(0.4)
            .ignoresSafeArea()

            // hero-gradient: transparent → 80% at 60% → opaque at 100%
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(hex: "131313").opacity(0.8), location: 0.6),
                    .init(color: Color(hex: "131313"), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding(.bottom, 16)

            // font-display-metrics 48px tracking-[0.2em]
            Text("CONVOTRACK")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(Color.primaryFixed)
                .tracking(9.6)

            // border-t border-outline-variant/30 pt-2 w-max tracking-[0.3em]
            // `w-max` = content-hugging width → no frame(maxWidth:) needed
            Text("RIDE TOGETHER IN REAL TIME")
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(3.6)
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.outlineVariant.opacity(0.3))
                        .frame(height: 1)
                }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Auth Buttons

    private var authButtons: some View {
        VStack(spacing: 16) {
            // Google — bg-primary-fixed, border-2 border-primary-fixed, btn-glow
            signInButton(
                label: "Continue with Google",
                icon: AnyView(GoogleGIcon()),
                foreground: Color.onPrimaryFixed,
                background: Color.primaryFixed,
                border: Color.primaryFixed,
                borderWidth: 2,
                glowColor: Color.primaryFixed.opacity(0.35),
                isLoading: isSigningIn,
                action: signInWithGoogle
            )

            // Apple — bg-surface-container-highest, text-primary (#fff), border-outline/30
            signInButton(
                label: "Continue with Apple",
                icon: AnyView(
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .medium))
                ),
                foreground: .white,
                background: Color.surfaceContainerHighest,
                border: Color.outline.opacity(0.3),
                borderWidth: 1,
                glowColor: .clear,
                isLoading: false,
                action: signInWithApple
            )

        }
    }

    // Icon pinned to left-4, label centered — matches Stitch `absolute left-4` + flex justify-center
    private func signInButton(
        label: String,
        icon: AnyView,
        foreground: Color,
        background: Color,
        border: Color,
        borderWidth: CGFloat,
        glowColor: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else {
                    // Text centered across the full width
                    Text(label)
                        .font(.system(size: 15, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(-0.5)
                        .foregroundColor(foreground)

                    // Icon pinned to leading edge at 16pt
                    HStack(spacing: 0) {
                        icon
                            .frame(width: 24, height: 24)
                            .foregroundColor(foreground)
                        Spacer()
                    }
                    .padding(.leading, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border, lineWidth: borderWidth))
            .shadow(color: glowColor, radius: 16)
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        .frame(width: 350)
    }

    // MARK: - Auth Actions

    private func signInWithGoogle() {
        isSigningIn = true
        Task {
            do {
                try await clerk.auth.signInWithOAuth(provider: .google)
                navigateToMain = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSigningIn = false
        }
    }

    private func signInWithApple() {
        isSigningIn = true
        Task {
            do {
                try await clerk.auth.signInWithApple()
                navigateToMain = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSigningIn = false
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 20) {
            // TERMS • PRIVACY — naturally centered, no Spacers
            HStack(spacing: 24) {
                Button("TERMS") {
                    openURL(URL(string: AppURLs.termsOfService)!)
                }
                    .font(.labelCaps)
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(4)
                Circle()
                    .fill(Color.primaryFixed.opacity(0.5))
                    .frame(width: 5, height: 5)
                Button("PRIVACY") {
                    openURL(URL(string: AppURLs.privacyPolicy)!)
                }
                    .font(.labelCaps)
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(4)
            }

            HStack(spacing: 8) {
                StatusPill(dotColor: Color.tertiaryFixedDim, label: "SERVER ONLINE")
                StatusPill(icon: "lock.shield", label: "SSL ENCRYPTED")
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

// MARK: - Status Pill

struct StatusPill: View {
    var icon: String? = nil
    var dotColor: Color? = nil
    let label: String
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
            }
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(Color.onSurfaceVariant)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.surfaceContainerLow)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
    }
}

#Preview {
    AuthView()
}
