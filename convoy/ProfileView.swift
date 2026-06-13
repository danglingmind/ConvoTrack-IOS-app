import SwiftUI
import ClerkKit

struct ProfileView: View {
    @Binding var activeTab: ConvoyBottomNav.Tab
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsEnabled = true
    @State private var units = "Metric"
    @State private var mapStyle = "Dark"
    @State private var recentRides: [HistoryRide] = []
    @State private var isSigningOut = false

    private var displayName: String {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? (clerk.user?.username ?? "Rider") : name
    }

    private var avatarUrl: URL? {
        guard let str = clerk.user?.imageUrl, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            Color.clear
                .background(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.primaryFixed.opacity(0.08), .clear]),
                        center: .top,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 72)

                    // Profile Hero
                    HStack(spacing: 20) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(Color.surfaceContainer)
                                .frame(width: 88, height: 88)
                                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                                .overlay(
                                    AsyncImage(url: avatarUrl) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Text(String(displayName.prefix(1)).uppercased())
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(Color.primaryFixed)
                                    }
                                    .clipShape(Circle())
                                )

                            ZStack {
                                Circle().fill(Color.primaryFixed).frame(width: 24, height: 24)
                                Circle().fill(Color.onPrimaryContainer).frame(width: 8, height: 8)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayName)
                                .font(.headlineLg)
                                .foregroundColor(Color.onSurface)
                            HStack(spacing: 8) {
                                Image(systemName: "motorcycle")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.primaryFixed)
                                Text("Convoy Rider")
                                    .font(.bodyLg)
                                    .foregroundColor(Color.onSurfaceVariant)
                            }
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(Color.surfaceContainerHigh.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
                    .padding(.horizontal, 20)

                    // Preferences
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREFERENCES")
                            .font(.labelCaps)
                            .foregroundColor(Color.primaryFixed)
                            .tracking(4)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            PrefCard(icon: "ruler", label: "UNITS", value: units) { units = units == "Metric" ? "Imperial" : "Metric" }
                            PrefCard(icon: "map", label: "MAP STYLE", value: mapStyle) { mapStyle = mapStyle == "Dark" ? "Satellite" : "Dark" }
                        }

                        HStack(spacing: 16) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.primaryFixed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NOTIFICATIONS").font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                                Text(notificationsEnabled ? "Enabled" : "Disabled").font(.bodyLg).foregroundColor(Color.onSurface)
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .tint(Color.primaryFixed)
                        }
                        .padding(16)
                        .background(Color.surfaceContainerHigh.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)

                    // Ride History
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RIDE HISTORY").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(4)
                            Spacer()
                            Button(action: { activeTab = .flagged }) {
                                Text("VIEW ALL").font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                            }
                        }
                        .padding(.horizontal, 4)

                        if recentRides.isEmpty {
                            Text("No completed rides yet")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(recentRides.prefix(2)) { ride in
                                    ProfileRideRow(ride: ride)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Logout
                    Button(action: {
                        Task {
                            isSigningOut = true
                            appState.currentRideId = nil
                            appState.inviteCode = nil
                            appState.currentRide = nil
                            try? await Clerk.shared.auth.signOut()
                            dismiss()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isSigningOut {
                                ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text(isSigningOut ? "SIGNING OUT..." : "LOGOUT").font(.bodyLg)
                        }
                        .foregroundColor(Color.errorColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.3), lineWidth: 1))
                    }
                    .disabled(isSigningOut)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Color.clear.frame(height: 120)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "PROFILE")
        }
        .task { recentRides = (try? await APIClient.shared.getMyRides()) ?? [] }
    }
}

// MARK: - Profile Ride Row

struct ProfileRideRow: View {
    let ride: HistoryRide

    var subtitleLabel: String {
        var parts: [String] = []
        if ride.distanceMeters > 0 {
            parts.append(String(format: "%.0f KM", ride.distanceMeters / 1000))
        }
        if let iso = ride.endedAt,
           let date = ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter()
            f.dateFormat = "dd MMM yyyy"
            parts.append(f.string(from: date).uppercased())
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.surfaceContainerLow)
                    .frame(width: 48, height: 48)
                Image(systemName: "road.lanes")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primaryFixed.opacity(0.6))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title).font(.bodyLg).foregroundColor(Color.onSurface)
                Text(subtitleLabel).font(.dataMono).foregroundColor(Color.onSurfaceVariant)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(Color.tertiaryFixedDim).frame(width: 6, height: 6)
                Text("Completed").font(.labelCaps).foregroundColor(Color.tertiaryFixedDim).tracking(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.onTertiaryContainer.opacity(0.2))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.tertiaryContainer.opacity(0.3), lineWidth: 1))
        }
        .padding(16)
        .background(Color.surfaceContainerHigh.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Pref Card

struct PrefCard: View {
    let icon: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(Color.primaryFixed)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                    Text(value).font(.headlineMd).foregroundColor(Color.onSurface)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 120)
            .padding(16)
            .background(Color.surfaceContainerHigh.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ProfileView(activeTab: .constant(.profile))
        .environmentObject(AppState())
}
