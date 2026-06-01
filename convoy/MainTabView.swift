import SwiftUI

struct MainTabView: View {
    @State private var activeTab: ConvoyBottomNav.Tab = .track
    @State private var showJoinRide = false
    @StateObject private var appState = AppState()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch activeTab {
                case .flagged:
                    NavigationStack {
                        RideHistoryView()
                    }
                case .track:
                    NavigationStack {
                        HomeView(activeTab: $activeTab, showJoinRide: $showJoinRide)
                    }
                case .profile:
                    ProfileView()
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
        }
    }
}

#Preview {
    MainTabView()
}
