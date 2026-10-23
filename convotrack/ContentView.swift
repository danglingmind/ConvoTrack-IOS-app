import SwiftUI
import ClerkKit

/// Root flow: launch check → (splash → onboarding →) sign-in → (paywall →) app.
///
/// Returning, signed-in riders never see the splash or onboarding. Riders who arrive from a
/// join link go straight to sign-in; they already know why they're here.
struct ContentView: View {
    private enum Stage { case launch, splash, onboarding, auth, paywall, main, gallery }

    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var membershipStore: MembershipStore
    @State private var stage: Stage = .launch

    var body: some View {
        ZStack {
            DS.Background.base.ignoresSafeArea()

            switch stage {
            case .launch:
                LaunchPlaceholder()
            case .splash:
                SplashView { go(.onboarding) }
            case .onboarding:
                OnboardingFlowView { go(.auth) }
            case .auth:
                AuthView(onAuthenticated: authenticated)
            case .paywall:
                MembershipView(presentation: .onboarding, onFinish: { go(.main) })
            case .main:
                MainTabView()
            case .gallery:
                #if DEBUG
                DSGalleryView()
                #else
                EmptyView()
                #endif
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: stage)
        .task { await resolveLaunchStage() }
        // Ties this device's earlier anonymous events (onboarding, sign-in) to the rider once known.
        .task(id: clerk.user?.id) { if let id = clerk.user?.id { Analytics.identify(userId: id) } }
    }

    // MARK: Routing

    private func go(_ next: Stage) { stage = next }

    private func resolveLaunchStage() async {
        // Clerk restores its session asynchronously; routing before it finishes would send a
        // signed-in rider to the sign-in screen. Bounded so a dead network can't hang launch.
        #if DEBUG
        // `-resetUpsell YES` clears app-open / nudge / Home-card bookkeeping.
        if UserDefaults.standard.bool(forKey: "resetUpsell") { UpsellState.reset() }
        // `-onboardingStage splash|onboarding|auth|paywall` jumps straight to a stage for design review.
        if let raw = UserDefaults.standard.string(forKey: "onboardingStage") {
            switch raw {
            case "splash":     go(.splash);     return
            case "onboarding": go(.onboarding); return
            case "auth":       go(.auth);       return
            case "paywall":    go(.paywall);    return
            case "gallery":    go(.gallery);    return
            default: break
            }
        }
        #endif

        let deadline = Date().addingTimeInterval(3)
        while !clerk.isLoaded && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if clerk.user != nil {
            // Already signed in (includes everyone who installed before onboarding existed).
            OnboardingState.hasCompleted = true
            go(.main)
        } else if DeepLinkRouter.pendingJoinCode != nil || OnboardingState.hasCompleted {
            go(.auth)
        } else {
            go(.splash)
        }
    }

    /// Called as soon as sign-in succeeds. First-time riders see the paywall once; everyone else
    /// goes straight in. Never show it to someone who is already Pro.
    private func authenticated() {
        let firstTime = !OnboardingState.hasCompleted
        OnboardingState.hasCompleted = true
        if firstTime && !membershipStore.isPremium {
            UpsellState.recordOnboardingPaywall()
            go(.paywall)
        } else {
            go(.main)
        }
    }
}

/// Plain dark screen with the logo, shown only while Clerk restores the session.
private struct LaunchPlaceholder: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(MembershipStore())
}
