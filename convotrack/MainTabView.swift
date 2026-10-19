import SwiftUI
import ClerkKit

/// Drives the join sheet. Carrying the prefill code as part of the presented item (instead of a
/// separate `@State` read inside a `.sheet(isPresented:)` closure) makes presentation atomic — the
/// sheet ALWAYS receives the code that opened it, with no one-render-cycle lag where a deep-link
/// sheet could appear before its code propagated.
private struct JoinSheetContext: Identifiable {
    let id = UUID()
    let code: String?     // nil = opened manually (user enters the code); non-nil = deep link / QR
}

enum AppTab: Hashable {
    case history, home, profile
}

struct MainTabView: View {
    @State private var activeTab: AppTab = .home
    @State private var joinSheet: JoinSheetContext? = nil
    @StateObject private var appState = AppState()
    // Owns the ride's realtime socket for its whole lifetime, above both the lobby and the
    // navigation screen, so a reconnect self-heals and the lobby→navigation push never drops it.
    @StateObject private var rideSession = RideRealtimeSession()
    @StateObject private var paywall = PaywallPresenter()
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNudge = false
    /// Set by the nudge's "See plans"; read when the nudge finishes dismissing.
    @State private var nudgeWantsPlans = false
    @Environment(Clerk.self) private var clerk

    var body: some View {
        // Native iOS 26 tab bar (floating Liquid Glass). Every tab keeps its own NavigationStack
        // alive, so switching tabs no longer rebuilds them. The ride Lobby is pushed inside the
        // Home stack, so Home stays selected there. Navigation / Create / Edit / Summary hide the
        // bar with `.toolbar(.hidden, for: .tabBar)`.
        TabView(selection: $activeTab) {
            Tab("History", systemImage: "flag.fill", value: AppTab.history) {
                NavigationStack {
                    RideHistoryView()
                }
            }
            Tab("Home", systemImage: "location.north.fill", value: AppTab.home) {
                // HomeView's "Join Ride" button just opens the sheet with no prefilled code.
                HomeView(activeTab: $activeTab, showJoinRide: Binding(
                    get: { joinSheet != nil },
                    set: { open in joinSheet = open ? JoinSheetContext(code: nil) : nil }
                ))
            }
            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(DS.Accent.base)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(appState)
        .environmentObject(rideSession)
        .environmentObject(paywall)
        .preferredColorScheme(.dark)
        .sheet(item: $joinSheet) { ctx in
            JoinRideView(prefillCode: ctx.code)
                .environmentObject(appState)
        }
        // The one paywall sheet for every screen under the tabs (see `PaywallPresenter`).
        .sheet(item: $paywall.request) { request in
            MembershipView(source: request.source)
                .environmentObject(membershipStore)
        }
        .sheet(isPresented: $showNudge, onDismiss: nudgeDismissed) {
            ProNudgeSheet { wantsPlans in nudgeWantsPlans = wantsPlans }
                .environmentObject(membershipStore)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: handleForeground()
            case .background: UpsellState.recordBackground()
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .convotrackJoinRide)) { note in
            guard let code = note.userInfo?["code"] as? String else { return }
            DeepLinkRouter.pendingJoinCode = nil   // consumed live; don't let onAppear replay it
            openJoin(code: code)
        }
        // A rider who went Pro from a blocked invite link carries straight on into that ride.
        .onChange(of: membershipStore.isPremium) { _, isPremium in
            guard isPremium, let code = paywall.joinAfterUpgradeCode else { return }
            paywall.joinAfterUpgradeCode = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                joinSheet = JoinSheetContext(code: code)
            }
        }
        .onAppear {
            // Cold-launch deep link: MainTabView wasn't listening when the link arrived, so drain
            // the buffered code now that we're on screen. MainTabView is presented via a
            // fullScreenCover (Splash → Auth → Main); presenting a sheet while that cover is still
            // animating is silently dropped, so defer until the transition settles.
            if let code = DeepLinkRouter.pendingJoinCode {
                DeepLinkRouter.pendingJoinCode = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    openJoin(code: code)
                }
            }
        }
        // `scenePhase` doesn't report the launch itself, so the first foreground is handled here.
        .task { handleForeground() }
        .task {
            guard let user = clerk.user else { return }
            let name = [user.firstName, user.lastName]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let displayName = name.isEmpty ? (user.username ?? "Rider") : name
            try? await APIClient.shared.syncProfile(name: displayName, avatarUrl: user.imageUrl.isEmpty ? nil : user.imageUrl)
        }
    }

    // MARK: - App-open nudge

    /// Refreshes plan/trial state on every foreground; on a real app open (not a quick hop out and
    /// back) it then considers the nudge, once the tab view and any deep link have settled.
    private func handleForeground() {
        let isAppOpen = UpsellState.recordForeground()
        Task {
            await membershipStore.refreshServerState()
            guard isAppOpen else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            maybeShowNudge()
        }
    }

    private func maybeShowNudge() {
        // Never over something the rider is doing: another sheet, a pending deep link, a ride.
        guard !showNudge, joinSheet == nil, paywall.request == nil,
              DeepLinkRouter.pendingJoinCode == nil, DeepLinkRouter.pendingOpenRideId == nil else { return }
        #if DEBUG
        // `-forceNudge YES` shows it on every open for design review (sheets/deep links still win).
        let forced = UserDefaults.standard.bool(forKey: "forceNudge")
        #else
        let forced = false
        #endif
        if !forced {
            guard appState.currentRideId == nil else { return }
            let inputs = UpsellPolicy.Inputs(
                access: membershipStore.access,
                now: Date(),
                appOpenCount: UpsellState.appOpenCount,
                firstOpenAt: UpsellState.firstOpenAt,
                lastNudgeAt: UpsellState.lastNudgeAt,
                nudgeDismissCount: UpsellState.nudgeDismissCount,
                onboardingPaywallAt: UpsellState.onboardingPaywallAt,
                rideCompletedAt: UpsellState.rideCompletedAt
            )
            guard UpsellPolicy.shouldShowAppOpenNudge(inputs) else { return }
        } else if membershipStore.access == .pro {
            return
        }
        UpsellState.recordNudgeShown()
        PaywallAnalytics.log(.nudgeShown, source: .appOpen, access: membershipStore.access)
        nudgeWantsPlans = false
        showNudge = true
    }

    private func nudgeDismissed() {
        if nudgeWantsPlans {
            // Same reason as the join sheet: one sheet has to finish leaving before the next.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { paywall.present(.appOpen) }
        } else {
            UpsellState.recordNudgeDismissed()
            PaywallAnalytics.log(.nudgeDismissed, source: .appOpen, access: membershipStore.access)
        }
    }

    /// Invite link / QR entry point. Once the trial is over the paywall comes first; the code is
    /// kept so buying Pro drops the rider straight into the join sheet.
    private func openJoin(code: String) {
        if membershipStore.mustUpgradeToRide {
            paywall.joinAfterUpgradeCode = code
            paywall.present(.joinBlocked)
        } else {
            // New identity each time so a repeat tap re-presents even if a sheet is already up.
            joinSheet = JoinSheetContext(code: code)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(MembershipStore())
}
