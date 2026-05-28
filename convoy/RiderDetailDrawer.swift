import SwiftUI

struct RiderDetailDrawer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            // Map background
            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBoRQ-wb31D5DezR3d-hxi4TKw-SYcbLZSKc5jTFPTXmKBJdbUyVld2fevpj6NDVJhwY2-a_2lCt3kePE0WTpOalxGcnouVY1m0P9lGVXBVvWVna4I7gE8LgDoYmX2L-Afa7iSgliQyLOGBEwc9ao4g4C9_1_13zoWuZlm6HefS1-9WA0cvpXU6SUUJC_8TX-8MqhmjI6G_wU92wiAfe9V23qCIuF8T5auQBZJyNRy7hgpc0JWr0beArfMc55d6R_dgdQFcEuYTm9s")) { image in
                image.resizable().scaledToFill()
                    .grayscale(0.4).opacity(0.4)
            } placeholder: {
                Color.surfaceContainerLowest
            }
            .ignoresSafeArea()
            .clipped()

            // Rider marker on map
            VStack {
                Spacer().frame(height: 120)
                ZStack {
                    Circle()
                        .fill(Color.primaryFixed.opacity(0.15))
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.3)
                        .animation(.easeInOut(duration: 1.5).repeatForever(), value: true)

                    Circle()
                        .fill(Color.surfaceContainer)
                        .frame(width: 52, height: 52)
                        .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                        .overlay(
                            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuA5o-oVxSXVQFysUI2yvq80g_78Ky5Npi1fueHocZHVsqHaYJyU8WxZsbskAhvMVXXPsn6KhniEYxhiZc9OEiGfI1cOoVqabWYKU5tAKQO0bTFd2EkdueY7hxFyPD40hBDqbfNM0OomS0qW_-AQRz9iyB73jvAiHNQ8Y8DQ14lZrvA0eBFFdqzN-SVxqoQd3DKrFlxbjQj1nnbRZZ8sS2R-v8qggxvFEHC4s4Q9amiSblPTufkxEO8OJBMXHAB8SZk1mI4KH9Y_0U0")) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { Color.clear }
                                .clipShape(Circle())
                        )
                }

                Text("#2 SAM")
                    .font(.labelCaps)
                    .foregroundColor(Color.onSurface)
                    .tracking(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                    .padding(.top, 8)

                Spacer()
            }

            // Map zoom controls
            VStack {
                Color.clear.frame(height: 100)
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        MapControlButton(icon: "plus") {}
                        MapControlButton(icon: "minus") {}
                        MapControlButton(icon: "location.fill") {}
                    }
                    .padding(.trailing, 20)
                }
                Spacer()
            }

            // Drawer
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.outlineVariant.opacity(0.5))
                        .frame(width: 48, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    // Rider header
                    HStack(alignment: .top) {
                        HStack(spacing: 16) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.surfaceContainer)
                                    .frame(width: 64, height: 64)
                                    .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                                    .overlay(
                                        AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuBlmttXTE0DMZ6BI0povBo7xzU813jzXL1XHG-dsBPoXXG-lUy3hEobK63F01CeBrI3qU7ccatWJoZZqf3VZSyIRORTX_8WCufPD0m471Hl6ef3-Pnlmy2uNCz2DV_MNTqqYvCHHxXQpEjjpFtO6l4cRPoT__c308QFkNUaGHbVDeuUP3FUBIXbQymlu8UOr5ETXl1l6VTtDPFob4iSalAQQgAcHZc3TmI8s-fRjUHGYkuntrVbaqjUOmrSB8le-GRLmmOjK4RVMsQ")) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: { Color.clear }
                                            .clipShape(Circle())
                                    )

                                Circle().fill(Color.tertiaryFixed).frame(width: 10, height: 10)
                                    .shadow(color: Color.tertiaryFixed.opacity(0.5), radius: 4)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("RIDER #2")
                                        .font(.labelCaps)
                                        .foregroundColor(Color.primaryFixed)
                                        .tracking(2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.primaryFixed.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Circle().fill(Color.tertiaryFixed).frame(width: 8, height: 8)
                                        .shadow(color: Color.tertiaryFixed, radius: 4)
                                }
                                Text("Sam")
                                    .font(.headlineLg)
                                    .foregroundColor(Color.onSurface)
                                    .textCase(.uppercase)
                                Text("BMW R 1250 GS")
                                    .font(.bodyMd)
                                    .foregroundColor(Color.onSurfaceVariant)
                            }
                        }

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "message")
                                .font(.system(size: 20))
                                .foregroundColor(Color.onSurface)
                                .frame(width: 48, height: 48)
                                .overlay(Circle().stroke(Color.outlineVariant, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Telemetry Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        TelemetryCard(label: "Gap Distance", value: "+120", unit: "METERS", isPrimary: true)
                        TelemetryCard(label: "Current Speed", value: "58", unit: "KM/H", isPrimary: false)
                        TelemetryCard(label: "Battery", value: "76%", unit: nil, icon: "battery.75percent.bolt", iconColor: Color.primaryFixed)
                        TelemetryCard(label: "Signal", value: "STRONG", unit: nil, icon: "wifi", iconColor: Color.tertiaryFixed)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Primary Action
                    Button(action: {}) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                            Text("FOCUS RIDER")
                                .font(.headlineMd)
                                .tracking(-0.5)
                        }
                        .modifier(LimePrimaryButton())
                    }
                    .padding(.horizontal, 24)

                    // Secondary Actions
                    HStack(spacing: 12) {
                        SecondaryActionButton(icon: "arrow.triangle.turn.up.right.circle", label: "SEND ROUTE", color: Color.onSurface)
                        SecondaryActionButton(icon: "exclamationmark.triangle", label: "REPORT ISSUE", color: Color.errorColor)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .background(
                    Color.surfaceContainerLowest.opacity(0.92)
                        .background(.ultraThinMaterial)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1)
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .preferredColorScheme(.dark)
    }
}

struct MapControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color.onSurface)
                .frame(width: 48, height: 48)
                .background(Color.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.outline.opacity(0.3), lineWidth: 1))
        }
    }
}

struct TelemetryCard: View {
    let label: String
    let value: String
    let unit: String?
    var isPrimary: Bool = false
    var icon: String? = nil
    var iconColor: Color = Color.primaryFixed

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            if let icon {
                HStack {
                    Text(value).font(.headlineMd).foregroundColor(Color.onSurface).fontWeight(.bold)
                    Spacer()
                    Image(systemName: icon).font(.system(size: 22)).foregroundColor(iconColor)
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.displayMetrics)
                        .foregroundColor(isPrimary ? Color.primaryFixed : Color.onSurface)
                    if let unit {
                        Text(unit).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.labelCaps).tracking(1)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant, lineWidth: 1))
        }
    }
}

#Preview {
    RiderDetailDrawer()
}
