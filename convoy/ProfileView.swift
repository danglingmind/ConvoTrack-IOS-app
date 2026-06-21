import SwiftUI
import ClerkKit

struct ProfileView: View {
    @Binding var activeTab: ConvoyBottomNav.Tab
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
@State private var units = "Metric"
    @State private var mapStyle = "Dark"
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

            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: avatarUrl) { img in
                        img.resizable().scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                    } placeholder: {
                        Circle()
                            .fill(Color.surfaceVariant)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                            .overlay(
                                Text(String(displayName.prefix(1)).uppercased())
                                    .font(.bodyMd).foregroundColor(Color.primaryFixed)
                            )
                    }
                    ZStack {
                        Circle().fill(Color.primaryFixed).frame(width: 11, height: 11)
                        Circle().fill(Color.onPrimaryContainer).frame(width: 5, height: 5)
                    }
                }
                Text(displayName)
                    .font(.headlineMd)
                    .foregroundColor(Color.onSurface)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primaryFixed)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
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
