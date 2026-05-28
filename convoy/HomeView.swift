import SwiftUI

struct HomeView: View {
    @Binding var showJoinRide: Bool
    @State private var showCreateRide = false
    @State private var showLobby = false
    @State private var showSummary = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72)

                    VStack(spacing: 32) {
                        // Greeting
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("STATUS: READY TO RIDE")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(4)
                                Text("Good Morning, Yash")
                                    .font(.headlineLg)
                                    .foregroundColor(Color.onSurface)
                            }
                            Spacer()
                            ZStack(alignment: .bottomTrailing) {
                                AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDZPbGMUietTU8vTKMiMrZURdftPeVXwBal64HbaxnuPTrbhm3VeCUV2QWIqgaZwBQpcjl9EK5m9ZJO48JerTdaH814KROSLqUcy8et1yq5qoa1QqJ8MY-b3HNZJZeAGX2GKKivgzlSmsPOpJJVv8kfBbKFpXwa55Wu59qhYSq25YV0uUvBKyqPQ8sCIS413OOCyHNkQzol5B8zksBCJaL62MwKxK3hyKn3dKsQ71V9lZaFXdP40IP8O6Q16D2ioN5sTL9A7_w4dpw")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color.surfaceVariant)
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))

                                Circle()
                                    .fill(Color.primaryFixed)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: Color.primaryFixed, radius: 4)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Action Grid
                        HStack(spacing: 12) {
                            Button(action: { showCreateRide = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                                    Text("CREATE RIDE").font(.labelCaps).tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.primaryFixed)
                                .foregroundColor(Color.onPrimaryFixed)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button(action: { showJoinRide = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.badge.plus").font(.system(size: 20))
                                    Text("JOIN RIDE").font(.labelCaps).tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.surfaceContainerHighest)
                                .foregroundColor(Color.onSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 20)

                        // Active Ride Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("ACTIVE RIDE")
                                    .font(.headlineMd)
                                    .foregroundColor(Color.onSurface)
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle().fill(Color.primaryFixed).frame(width: 8, height: 8)
                                    Text("LIVE NOW").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                                }
                            }
                            .padding(.horizontal, 20)

                            // Active Ride Card
                            Button(action: { showLobby = true }) {
                                VStack(spacing: 0) {
                                    // Map preview
                                    ZStack(alignment: .topLeading) {
                                        AsyncImage(url: URL(string: "https://images.unsplash.com/photo-1524661135-423995f22d0b?q=80&w=800")) { image in
                                            image.resizable().scaledToFill()
                                                .overlay(LinearGradient(colors: [.clear, Color.surfaceContainerHigh], startPoint: .top, endPoint: .bottom))
                                        } placeholder: {
                                            Color.surfaceDim
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 180)
                                        .clipped()

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("DESTINATION").font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                                            Text("Mandalpatti Peak").font(.bodyLg).foregroundColor(Color.onSurface).fontWeight(.bold)
                                        }
                                        .padding(12)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .padding(12)
                                    }

                                    // Ride info
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Coorg Morning Ride").font(.headlineMd).foregroundColor(Color.onSurface)
                                            HStack(spacing: 8) {
                                                HStack(spacing: -6) {
                                                    ForEach(0..<3) { _ in
                                                        Circle().fill(Color.surfaceVariant).frame(width: 24, height: 24)
                                                            .overlay(Circle().stroke(Color.surfaceContainerHigh, lineWidth: 2))
                                                    }
                                                }
                                                Text("8 Riders • ACTIVE").font(.dataMono).foregroundColor(Color.onSurfaceVariant)
                                            }
                                        }
                                        Spacer()
                                        Text("RESUME RIDE")
                                            .font(.labelCaps)
                                            .foregroundColor(Color.onPrimaryContainer)
                                            .tracking(1)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color.primaryContainer)
                                            .clipShape(Capsule())
                                            .shadow(color: Color.primaryFixed.opacity(0.3), radius: 12)
                                    }
                                    .padding(16)
                                }
                                .background(Color.surfaceContainerHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.5), lineWidth: 1))
                                .padding(.horizontal, 20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Recent Rides
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("RECENT RIDES").font(.headlineMd).foregroundColor(Color.onSurface)
                                Spacer()
                                Text("VIEW ALL").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                            }
                            .padding(.horizontal, 20)

                            VStack(spacing: 12) {
                                Button(action: { showSummary = true }) {
                                    RecentRideRow(icon: "road.lanes", title: "Coorg Sunrise Ride", subtitle: "12 OCT • 142 KM • 4.5 HRS")
                                }
                                .buttonStyle(.plain)
                                Button(action: { showSummary = true }) {
                                    RecentRideRow(icon: "cup.and.saucer.fill", title: "Sunday Breakfast Ride", subtitle: "08 OCT • 68 KM • 2.1 HRS")
                                }
                                .buttonStyle(.plain)
                                Button(action: { showSummary = true }) {
                                    RecentRideRow(icon: "waveform.path", title: "Western Ghats Trail", subtitle: "01 OCT • 310 KM • 8.2 HRS")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 100)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "APEX CONVOY")
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showCreateRide) {
            CreateRideView()
        }
        .navigationDestination(isPresented: $showLobby) {
            RideLobbyView()
        }
        .navigationDestination(isPresented: $showSummary) {
            RideSummaryView()
        }
    }
}

struct RecentRideRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.surfaceVariant).frame(width: 56, height: 56)
                Image(systemName: icon).font(.system(size: 22)).foregroundColor(Color.primaryFixed)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.bodyLg).foregroundColor(Color.onSurface).fontWeight(.bold)
                Text(subtitle).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(Color.onSurfaceVariant)
        }
        .padding(16)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    HomeView(showJoinRide: .constant(false))
}
