import SwiftUI

struct RideHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rides: [HistoryRide] = []
    @State private var isLoading = true
    @State private var selectedRide: HistoryRide? = nil
    @State private var showSummary = false
    @State private var showLobby = false

    private var completedRides: [HistoryRide] { rides.filter { $0.status == "COMPLETED" } }

    private var totalDistanceKm: Double {
        completedRides.reduce(0) { $0 + $1.distanceMeters / 1000 }
    }
    private var avgSpeedKmh: Double {
        let speeds = completedRides.compactMap { $0.avgSpeedKmh }
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72)

                    VStack(spacing: 24) {
                        if isLoading {
                            ProgressView()
                                .tint(Color.primaryFixed)
                                .padding(.top, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("LIFETIME STATS")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(1)
                                    .padding(.horizontal, 20)

                                HStack(spacing: 8) {
                                    FloatingStatPill(
                                        label: "DISTANCE",
                                        value: String(format: "%.0f", totalDistanceKm),
                                        unit: "KM"
                                    )
                                    FloatingStatPill(
                                        label: "TOTAL RIDES",
                                        value: "\(rides.count)",
                                        unit: nil
                                    )
                                    FloatingStatPill(
                                        label: "AVG SPEED",
                                        value: avgSpeedKmh > 0 ? String(format: "%.0f", avgSpeedKmh) : "--",
                                        unit: "km/h"
                                    )
                                }
                                .padding(.horizontal, 20)
                            }

                            if rides.isEmpty {
                                emptyState
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(rides) { ride in
                                        Button(action: { handleTap(ride) }) {
                                            RideHistoryCard(ride: ride)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        Color.clear.frame(height: 120)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "RIDE HISTORY", transparent: true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSummary) {
            if let ride = selectedRide {
                RideSummaryView(rideId: ride.rideId, rideTitle: ride.title, fallback: ride)
            }
        }
        .navigationDestination(isPresented: $showLobby) {
            RideLobbyView()
        }
        .onChange(of: appState.popToRoot) { _, shouldPop in
            if shouldPop { showLobby = false }
        }
        .task { await loadHistory() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.slash")
                .font(.system(size: 48))
                .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
            Text("No rides yet")
                .font(.headlineMd)
                .foregroundColor(Color.onSurfaceVariant)
            Text("Your ride history will appear here after you create or join your first convoy.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }

    private func handleTap(_ ride: HistoryRide) {
        selectedRide = ride
        if ride.status == "COMPLETED" {
            showSummary = true
        } else {
            appState.currentRideId = ride.rideId
            if let code = ride.inviteCode { appState.inviteCode = code }
            showLobby = true
        }
    }

    private func loadHistory() async {
        rides = (try? await APIClient.shared.getMyRides()) ?? []
        isLoading = false
    }
}

struct RideHistoryCard: View {
    let ride: HistoryRide

    var dateLabel: String {
        let iso = ride.endedAt ?? ride.startedAt ?? ride.createdAt
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "--" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: date).uppercased()
    }

    var timeLabel: String {
        let iso = ride.startedAt ?? ride.createdAt
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: date)
    }

    var distanceLabel: String {
        guard ride.distanceMeters > 0 else { return "--" }
        return String(format: "%.1f KM", ride.distanceMeters / 1000)
    }

    var durationLabel: String {
        guard let s = ride.durationSeconds else { return "--" }
        let h = s / 3600; let m = (s % 3600) / 60
        return String(format: "%d:%02d HRS", h, m)
    }

    var speedLabel: String {
        ride.avgSpeedKmh.map { String(format: "%.0f KM/H", $0) } ?? "--"
    }

    var statusColor: Color {
        switch ride.status {
        case "LOBBY":           return Color.primaryFixed
        case "ACTIVE", "PAUSED": return Color.tertiaryFixed
        default:                return Color.tertiaryFixedDim
        }
    }

    var statusBgColor: Color {
        switch ride.status {
        case "LOBBY":           return Color.onPrimaryContainer
        default:                return Color.onTertiaryContainer
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.surfaceContainerLow
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "road.lanes")
                            .font(.system(size: 40))
                            .foregroundColor(Color.primaryFixed.opacity(0.08))
                    )
                    .overlay(LinearGradient(colors: [.clear, Color.surfaceDim], startPoint: .top, endPoint: .bottom))

                Text(ride.status)
                    .font(.labelCaps)
                    .foregroundColor(statusColor)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusBgColor.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(statusColor.opacity(0.3), lineWidth: 1))
                    .padding(12)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(dateLabel).font(.labelCaps).foregroundColor(Color.primaryFixedDim)
                        if !timeLabel.isEmpty {
                            Circle().fill(Color.outlineVariant).frame(width: 4, height: 4)
                            Text(timeLabel).font(.labelCaps).foregroundColor(Color.onSurfaceVariant)
                        }
                        if ride.isLeader == true {
                            Circle().fill(Color.outlineVariant).frame(width: 4, height: 4)
                            Text("LEADER").font(.labelCaps).foregroundColor(Color.primaryFixed)
                        }
                    }
                    Text(ride.title).font(.headlineMd).foregroundColor(Color.onSurface)
                    HStack(spacing: 20) {
                        MetricSmall(label: "DISTANCE", value: distanceLabel)
                        if ride.status == "COMPLETED" {
                            MetricSmall(label: "DURATION", value: durationLabel)
                            MetricSmall(label: "AVG SPEED", value: speedLabel)
                        }
                    }
                }
                Spacer()
                Image(systemName: ride.status == "COMPLETED" ? "chevron.right" : "arrow.right.circle")
                    .foregroundColor(ride.status == "COMPLETED" ? Color.outline : statusColor)
            }
            .padding(16)
        }
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            ride.status == "COMPLETED" ? Color.outlineVariant.opacity(0.4) : statusColor.opacity(0.25),
            lineWidth: 1
        ))
    }
}

struct MetricSmall: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            Text(value).font(.dataMono).foregroundColor(Color.onSurface)
        }
    }
}

#Preview {
    RideHistoryView()
        .environmentObject(AppState())
}
