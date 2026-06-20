import SwiftUI
import ClerkKit

struct MainTabView: View {
    @State private var activeTab: ConvoyBottomNav.Tab = .track
    @State private var showJoinRide = false
    @StateObject private var appState = AppState()
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
                ConvoyBottomNav(activeTab: $activeTab)
            }
        }
        .environmentObject(appState)
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showJoinRide) {
            JoinRideView()
                .environmentObject(appState)
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
