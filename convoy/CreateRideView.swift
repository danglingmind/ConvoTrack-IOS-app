import SwiftUI

struct CreateRideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rideTitle = ""
    @State private var destination = ""
    @State private var leaderboardEnabled = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.surfaceDim.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: 8)

                        // Input Section
                        VStack(spacing: 16) {
                            FieldRow(label: "RIDE TITLE", placeholder: "e.g., Midnight Canyon Run", text: $rideTitle, icon: "pencil")
                            FieldRow(label: "DESTINATION", placeholder: "Search waypoints...", text: $destination, icon: "magnifyingglass", iconLeading: true, iconColor: Color.primaryFixed)
                        }

                        // Route Preview Map
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("GENERATED ROUTE")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(2)
                                Spacer()
                                Text("24.5 KM")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.primaryFixed)
                                    .tracking(2)
                            }

                            ZStack {
                                AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuCk7tJ-lGG9ZcKcpjepQzm84-AalllIlCGel_QjF_5Le7yvbwXH9UFd36JK1SM-hvx2_POPLWgWq8thyXZyFFvydzK5Atts8Bvil4p1mSFGSIsU6OzP0pdfF8yZ1E5iakwNkW_bZGyps1X2ztHkvQV7hF0njXd1x9EDcDtnbch0Zf3lr1WiEjpCNgAE6GXEJTzzHAzxMWJzsWUbb0Ka4fBZHmFCJOC14nb07EOHJA8QFwWKJKvbTTVxYh2c6qvQmU7FEO51xPWl8Ec")) { image in
                                    image.resizable().scaledToFill()
                                        .grayscale(0.4).opacity(0.6)
                                } placeholder: {
                                    Color.surfaceContainerLow
                                }
                                .clipped()

                                // Scan line animation overlay
                                ScanLineView()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))

                            HStack(spacing: 12) {
                                RouteStatCard(icon: "timer", label: "EST. TIME", value: "32m")
                                RouteStatCard(icon: "arrow.up.right", label: "ELEVATION", value: "412m")
                            }
                        }

                        // Leaderboard Toggle
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.primaryContainer.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color.primaryFixed)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Leaderboard").font(.bodyLg).foregroundColor(Color.onSurface)
                                Text("Sync telemetry and compare times").font(.system(size: 12)).foregroundColor(Color.onSurfaceVariant)
                            }
                            Spacer()
                            Toggle("", isOn: $leaderboardEnabled)
                                .tint(Color.primaryFixed)
                        }
                        .padding(16)
                        .background(Color.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))

                        // CTA Button
                        Button(action: { dismiss() }) {
                            HStack(spacing: 12) {
                                Text("CREATE RIDE")
                                    .font(.headlineMd)
                                    .tracking(4)
                                Image(systemName: "sportscourt.fill")
                                    .font(.system(size: 20))
                            }
                            .modifier(LimePrimaryButton())
                        }

                        Text("READY FOR DEPARTURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
                            .tracking(8)

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationTitle("CREATE RIDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color.primaryFixed)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct FieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var iconLeading: Bool = false
    var iconColor: Color = Color.outline.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
            ZStack(alignment: iconLeading ? .leading : .trailing) {
                TextField(placeholder, text: $text)
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)
                    .padding(.horizontal, iconLeading ? 48 : 16)
                    .padding(.trailing, iconLeading ? 16 : 48)
                    .frame(height: 56)
                    .background(Color.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
                    .tint(Color.primaryFixed)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .padding(iconLeading ? .leading : .trailing, 16)
            }
        }
    }
}

struct RouteStatCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color.primaryFixed)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
                Text(value).font(.headlineMd).foregroundColor(Color.onSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.1), lineWidth: 1))
    }
}

struct ScanLineView: View {
    @State private var scanOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.primaryFixed, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: scanOffset)
                .opacity(0.8)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        scanOffset = geo.size.height
                    }
                }
        }
    }
}

#Preview {
    CreateRideView()
}
