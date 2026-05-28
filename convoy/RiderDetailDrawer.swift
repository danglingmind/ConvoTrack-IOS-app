import SwiftUI

struct RiderDetailDrawer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 0) {
            mapZone
                .frame(height: 180)

            riderPanel
        }
        .background(Color.surfaceContainerLowest.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Map Zone

    private var mapZone: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBoRQ-wb31D5DezR3d-hxi4TKw-SYcbLZSKc5jTFPTXmKBJdbUyVld2fevpj6NDVJhwY2-a_2lCt3kePE0WTpOalxGcnouVY1m0P9lGVXBVvWVna4I7gE8LgDoYmX2L-Afa7iSgliQyLOGBEwc9ao4g4C9_1_13zoWuZlm6HefS1-9WA0cvpXU6SUUJC_8TX-8MqhmjI6G_wU92wiAfe9V23qCIuF8T5auQBZJyNRy7hgpc0JWr0beArfMc55d6R_dgdQFcEuYTm9s")) { image in
                image.resizable().scaledToFill()
                    .grayscale(0.4).opacity(0.5)
            } placeholder: {
                Color.surfaceContainerLowest
            }
            .clipped()

            // fade into panel below
            LinearGradient(
                colors: [.clear, Color.surfaceContainerLowest],
                startPoint: .center,
                endPoint: .bottom
            )

            // rider pin
            riderPin

            // map controls — top-right
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        MapControlButton(icon: "plus") {}
                        MapControlButton(icon: "minus") {}
                        MapControlButton(icon: "location.fill") {}
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }

    private var riderPin: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.primaryFixed.opacity(0.15))
                    .frame(width: 68, height: 68)
                    .scaleEffect(pulsing ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }

                Circle()
                    .fill(Color.surfaceContainer)
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                    .overlay(
                        AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuA5o-oVxSXVQFysUI2yvq80g_78Ky5Npi1fueHocZHVsqHaYJyU8WxZsbskAhvMVXXPsn6KhniEYxhiZc9OEiGfI1cOoVqabWYKU5tAKQO0bTFd2EkdueY7hxFyPD40hBDqbfNM0OomS0qW_-AQRz9iyB73jvAiHNQ8Y8DQ14lZrvA0eBFFdqzN-SVxqoQd3DKrFlxbjQj1nnbRZZ8sS2R-v8qggxvFEHC4s4Q9amiSblPTufkxEO8OJBMXHAB8SZk1mI4KH9Y_0U0")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { Color.surfaceVariant }
                        .clipShape(Circle())
                    )
            }

            Text("#2 SAM")
                .font(.labelCaps)
                .foregroundColor(Color.onSurface)
                .tracking(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surfaceContainer.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Rider Panel

    private var riderPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                riderHeader
                    .padding(20)

                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                telemetryGrid
                    .padding(20)

                VStack(spacing: 12) {
                    Button(action: {}) {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .bold))
                            Text("FOCUS RIDER")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(0.5)
                        }
                        .modifier(LimePrimaryButton())
                    }

                    HStack(spacing: 12) {
                        SecondaryActionButton(
                            icon: "arrow.triangle.turn.up.right.circle",
                            label: "SEND ROUTE",
                            color: Color.onSurface
                        )
                        SecondaryActionButton(
                            icon: "exclamationmark.triangle",
                            label: "REPORT ISSUE",
                            color: Color.errorColor
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .background(Color.surfaceContainerLowest)
    }

    private var riderHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.surfaceContainer)
                .frame(width: 56, height: 56)
                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                .overlay(
                    AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBlmttXTE0DMZ6BI0povBo7xzU813jzXL1XHG-dsBPoXXG-lUy3hEobK63F01CeBrI3qU7ccatWJoZZqf3VZSyIRORTX_8WCufPD0m471Hl6ef3-Pnlmy2uNCz2DV_MNTqqYvCHHxXQpEjjpFtO6l4cRPoT__c308QFkNUaGHbVDeuUP3FUBIXbQymlu8UOr5ETXl1l6VTtDPFob4iSalAQQgAcHZc3TmI8s-fRjUHGYkuntrVbaqjUOmrSB8le-GRLmmOjK4RVMsQ")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color.surfaceVariant }
                    .clipShape(Circle())
                )

            // Name info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("RIDER #2")
                        .font(.labelCaps)
                        .foregroundColor(Color.primaryFixed)
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primaryFixed.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Circle()
                        .fill(Color.tertiaryFixed)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.tertiaryFixed.opacity(0.6), radius: 4)
                }

                Text("SAM")
                    .font(.headlineLg)
                    .foregroundColor(Color.onSurface)

                Text("BMW R 1250 GS")
                    .font(.dataMono)
                    .foregroundColor(Color.onSurfaceVariant)
            }

            Spacer()

            // Message button
            Button(action: {}) {
                Image(systemName: "message")
                    .font(.system(size: 18))
                    .foregroundColor(Color.onSurface)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant.opacity(0.5), lineWidth: 1))
            }
        }
    }

    private var telemetryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            TelemetryCard(label: "GAP DISTANCE", value: "+120", unit: "METERS", isPrimary: true)
            TelemetryCard(label: "CURRENT SPEED", value: "58", unit: "KM/H")
            TelemetryCard(label: "BATTERY", value: "76%", icon: "battery.75percent.bolt", iconColor: Color.primaryFixed)
            TelemetryCard(label: "SIGNAL", value: "STRONG", icon: "wifi", iconColor: Color.tertiaryFixed)
        }
    }
}

// MARK: - Supporting Views

struct MapControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.onSurface)
                .frame(width: 36, height: 36)
                .background(Color.surfaceContainerHigh.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.outline.opacity(0.3), lineWidth: 1))
        }
    }
}

struct TelemetryCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    var isPrimary: Bool = false
    var icon: String? = nil
    var iconColor: Color = Color.primaryFixed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)

            if let icon {
                HStack(alignment: .center) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurface)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(iconColor)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundColor(isPrimary ? Color.primaryFixed : Color.onSurface)
                    if let unit {
                        Text(unit)
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }
}

struct SecondaryActionButton: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                Text(label).font(.labelCaps).tracking(1)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(color.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        }
    }
}

#Preview {
    RiderDetailDrawer()
}
