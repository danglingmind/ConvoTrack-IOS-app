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
        .onReceive(NotificationCenter.default.publisher(for: .convotrackJoinRide)) { note in
            guard let code = note.userInfo?["code"] as? String else { return }
            DeepLinkRouter.pendingJoinCode = nil   // consumed live; don't let onAppear replay it
            // New identity each time so a repeat tap re-presents even if a sheet is already up.
            joinSheet = JoinSheetContext(code: code)
        }
        .onAppear {
            // Cold-launch deep link: MainTabView wasn't listening when the link arrived, so drain
            // the buffered code now that we're on screen. MainTabView is presented via a
            // fullScreenCover (Splash → Auth → Main); presenting a sheet while that cover is still
            // animating is silently dropped, so defer until the transition settles.
            if let code = DeepLinkRouter.pendingJoinCode {
                DeepLinkRouter.pendingJoinCode = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    joinSheet = JoinSheetContext(code: code)
                }
            }
        }
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
}

#Preview {
    MainTabView()
        .environmentObject(MembershipStore())
}
