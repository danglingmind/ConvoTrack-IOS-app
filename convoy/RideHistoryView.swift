import SwiftUI

struct RideHistoryView: View {
    @State private var rides: [HistoryRide] = []
    @State private var isLoading = true
    @State private var selectedRide: HistoryRide? = nil
    @State private var showSummary = false

    private var totalDistanceKm: Double {
        rides.reduce(0) { $0 + $1.distanceMeters / 1000 }
    }
    private var avgSpeedKmh: Double {
        let speeds = rides.compactMap { $0.avgSpeedKmh }
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
                            HStack(spacing: 8) {
                                FloatingStatPill(
                                    label: "DISTANCE",
                                    value: String(format: "%.0f", totalDistanceKm),
                                    unit: "KM"
                                )
                                FloatingStatPill(
                                    label: "COMPLETED",
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

                            if rides.isEmpty {
                                emptyState
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(rides) { ride in
                                        Button(action: {
                                            selectedRide = ride
                                            showSummary = true
                                        }) {
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

            ConvoyTopBar(title: "RIDE HISTORY")
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSummary) {
            RideSummaryView(rideId: selectedRide?.rideId, rideTitle: selectedRide?.title, fallback: selectedRide)
        }
        .task { await loadHistory() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.slash")
                .font(.system(size: 48))
                .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
            Text("No completed rides yet")
                .font(.headlineMd)
                .foregroundColor(Color.onSurfaceVariant)
            Text("Your ride history will appear here after you complete your first convoy.")
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }

    private func loadHistory() async {
        rides = (try? await APIClient.shared.getMyRides()) ?? []
        isLoading = false
    }
}

struct RideHistoryCard: View {
    let ride: HistoryRide

    var dateLabel: String {
        guard let iso = ride.endedAt,
              let date = ISO8601DateFormatter().date(from: iso) else { return "--" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: date).uppercased()
    }

    var timeLabel: String {
        guard let iso = ride.startedAt,
              let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: date)
    }

    var distanceLabel: String {
        String(format: "%.1f KM", ride.distanceMeters / 1000)
    }

    var durationLabel: String {
        guard let s = ride.durationSeconds else { return "--" }
        let h = s / 3600; let m = (s % 3600) / 60
        return String(format: "%d:%02d HRS", h, m)
    }

    var speedLabel: String {
        ride.avgSpeedKmh.map { String(format: "%.0f KM/H", $0) } ?? "--"
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

                Text("COMPLETED")
                    .font(.labelCaps)
                    .foregroundColor(Color.tertiaryFixedDim)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.onTertiaryContainer.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.tertiaryFixedDim.opacity(0.3), lineWidth: 1))
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
                    }
                    Text(ride.title).font(.headlineMd).foregroundColor(Color.onSurface)
                    HStack(spacing: 20) {
                        MetricSmall(label: "DISTANCE", value: distanceLabel)
                        MetricSmall(label: "DURATION", value: durationLabel)
                        MetricSmall(label: "AVG SPEED", value: speedLabel)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(Color.outline)
            }
            .padding(16)
        }
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
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
}
