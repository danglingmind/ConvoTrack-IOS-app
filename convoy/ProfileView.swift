import SwiftUI

struct ProfileView: View {
    @State private var notificationsEnabled = true
    @State private var units = "Metric"
    @State private var mapStyle = "Dark"

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            // Radial glow at top
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
                                    AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDJ_bNMdnimNgQ1C4e8XScHlGyOw8a_2vv0F4QRb-qp9ZXZtnNs7V6D5UqCZ-B1C4dsDow3M3FFWPkfsJBUm1ktfybXwEOCv8VaO9UZ6tLQNfep5lo65CgFw28slMBGcYmI6ZJ3XD-D9Cq8a05tosRlznts1wMXP2IUCzNXkH30wkXskK3UbyYJf4a7OMeCbEnFq-b3kntl7PGvfCHZwWPAYgcTZfwga6T4j0nclVMLPbCPiHbdV20Tj58F9qiU0oc2qxrRr8lpMj8")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { Color.clear }
                                        .clipShape(Circle())
                                )

                            ZStack {
                                Circle().fill(Color.primaryFixed).frame(width: 24, height: 24)
                                Circle().fill(Color.onPrimaryContainer).frame(width: 8, height: 8)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Yash")
                                .font(.headlineLg)
                                .foregroundColor(Color.onSurface)
                            HStack(spacing: 8) {
                                Image(systemName: "motorcycle")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.primaryFixed)
                                Text("Continental GT")
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

                    // Preferences Section
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

                        // Notifications toggle
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
                            Text("VIEW ALL").font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            ProfileRideCard(
                                title: "Coorg Ride",
                                subtitle: "420 KM • 12 JAN 2024",
                                imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDzcyXuFLtMMlKNikcVIMxeEfjOnrqTdZ93Gkt996PV2wtl4ZYtubmuedU0q5P4QAImZb2nidQ0blXENb7-HuvS9vtZnQpDMPUU7iWn2Jsbk_n5itcvAt40j5fNAex8jOGY_BDAzKT363Dn5_Xo_gIDaqJdFCWba3NCKIP8sAnG9YmpxfyjpQCar7Ewq_hhfWKLh-qbtuAXiPR-Omt9mYkXR3T0OFTLBAL6aT471SRM_V_22ZHsv7etXRuUL_raiAnkoOcnKY-3e8w"
                            )
                            ProfileRideCard(
                                title: "Ooty Ride",
                                subtitle: "280 KM • 24 DEC 2023",
                                imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuAIj9nHImxYrunvxwkRZU4C6cssjo5-JBt6GN1DSI3p-CMBs0sTNMhT3LZltQdVPs6pOVyKlKkBNxTqjSQBmuJ_kG5VS093AjbTC5LVbBhT-SxaynXZTouj6tEq8hmmsc_pc8pOMGUR3P0lonY5wg5k9lO2Wzc_gZ7FWnx04BYaPPw5MImpa3oyHDOZ0jVVsy3LbRjOlhpd-J1_LA3ZUT54nVH2umSMrJyjXVV10l60aQzGkzkLIF0g7g4M7p0PHPoyrtx_9hvbvM4"
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    // Logout
                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("LOGOUT").font(.bodyLg)
                        }
                        .foregroundColor(Color.errorColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Color.clear.frame(height: 100)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "APEX CONVOY")
        }
    }
}

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

struct ProfileRideCard: View {
    let title: String
    let subtitle: String
    let imgUrl: String

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: imgUrl)) { image in
                image.resizable().scaledToFill()
                    .opacity(0.6)
            } placeholder: {
                Color.surfaceContainerLow
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.bodyLg).foregroundColor(Color.onSurface)
                Text(subtitle).font(.dataMono).foregroundColor(Color.onSurfaceVariant)
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

#Preview {
    ProfileView()
}
