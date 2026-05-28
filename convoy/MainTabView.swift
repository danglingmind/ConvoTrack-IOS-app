import SwiftUI

struct MainTabView: View {
    @State private var activeTab: ConvoyBottomNav.Tab = .track
    @State private var showCreateRide = false
    @State private var showJoinRide = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch activeTab {
                case .garage:
                    RideHistoryView()
                case .track:
                    NavigationStack {
                        HomeView(showCreateRide: $showCreateRide, showJoinRide: $showJoinRide)
                    }
                case .profile:
                    ProfileView()
                }
            }

            ConvoyBottomNav(activeTab: $activeTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreateRide) {
            CreateRideView()
        }
        .sheet(isPresented: $showJoinRide) {
            JoinRideView()
        }
    }
}

#Preview {
    MainTabView()
}
