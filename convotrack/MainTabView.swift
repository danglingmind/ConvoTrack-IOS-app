import SwiftUI
import ClerkKit

struct MainTabView: View {
    @State private var activeTab: ConvoTrackBottomNav.Tab = .track
    @State private var showJoinRide = false
    @State private var deepLinkCode: String? = nil
    @StateObject private var appState = AppState()
    // Owns the ride's realtime socket for its whole lifetime, above both the lobby and the
    // navigation screen, so a reconnect self-heals and the lobby→navigation push never drops it.
    @StateObject private var rideSession = RideRealtimeSession()
    @Environment(Clerk.self) private var clerk

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch activeTab {
                case .flagged:
                    NavigationStack {
                        RideHistoryView()
                    }
                case .track:
                    HomeView(activeTab: $activeTab, showJoinRide: $showJoinRide)
                case .profile:
                    NavigationStack {
                        ProfileView(activeTab: $activeTab)
                    }
                }
            }

            if !appState.isRideActive {
                ConvoTrackBottomNav(activeTab: $activeTab)
            }
        }
        .environmentObject(appState)
        .environmentObject(rideSession)
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showJoinRide, onDismiss: { deepLinkCode = nil }) {
            JoinRideView(prefillCode: deepLinkCode)
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .convotrackJoinRide)) { note in
            guard let code = note.userInfo?["code"] as? String else { return }
            deepLinkCode = code
            showJoinRide = true
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
}
