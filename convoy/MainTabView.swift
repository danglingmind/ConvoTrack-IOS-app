import SwiftUI

struct MainTabView: View {
    @State private var activeTab: ConvoyBottomNav.Tab = .track
    @State private var showJoinRide = false

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
                        HomeView(showJoinRide: $showJoinRide)
                    }
                case .profile:
                    ProfileView()
                }
            }

            ConvoyBottomNav(activeTab: $activeTab)
        }
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
