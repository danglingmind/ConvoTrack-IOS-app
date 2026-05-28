import SwiftUI

struct RideSummaryView: View {
    @Environment(\.dismiss) private var dismiss

    private let leaderboard: [(rank: String, name: String, role: String, sync: String, imgUrl: String)] = [
        ("01", "Ghost Rider 01", "SQUAD LEADER • 100% SYNC", "100%",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuAx6XWZwwLVdo1d8NlDDCir4bF88KWjOAWF8BsFU7TPui59Wy9CHNT01cPH2sG5DbiJ2vgR-D6isYhTHQEqg2xujV2bPa9_b1GXdkWyMnjMmHB9t1fkFWI7FC4PN5ONuHVx2DpEuRBz8DJup61XEkm9ISyTWE2Lw0tzBY811A5ttFMOH7eczMPpB9HWOSU-fiBRSBhZDiFUthvaXKhGnx3MSb3hGzX--S70uTEJA7xbWNpZtPMpRI6z6zs-rWtynmybwSj_zrzi-Ak"),
        ("02", "NightHawk", "WINGMAN • 94% SYNC", "94%",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuC992f9Cm7jTCvt3mfOSge5BkbqYGv4uOxpnhjH_JbSzonkeayM42n912CpuKKsDWDo68jSgPmL1LrDWcCDXj3t_Exrt0mXfpz9GM_Hd2MNr98snCoqN0w2v6v7ZmJGeAJhzPp4M0wO26X2cMJXJowCeaY33B0sV1wNHqcwGQ3awcuuxgvONLN_2WBMTWQ8ktHT3iz-6yJ9GQdO0dN-ZH8AO_7CHrmVd7U0N21WDH71s_HTnMFJhH43-JitVbsu9Bu3AsoLPW_31XY"),
        ("03", "Valkyrie", "SWEEP • 88% SYNC", "88%",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuDTealI-uVMH5912keenzHV7rQcE7Bf20M3iQDQqN046qi9YuWovLHScoClfiGymfH5LDnCrapyYP3jhTOT5AxPlF4_KchhrahgvPylfZkm09sDR0yPLkVEmNobRRKAX7rShT2_9mVow5BoJEMyvRgPzrWSYFo7HKgdiFqwD_A_ecwXTv-sJB0WP9yP53grYNvuqXt97-a1r9YO9hmISgaMeBosTOrDbjmTBnw2vI0tqZf6PsmIHl1sf0Il9TUpaXUl5J7IcJCm76g")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero Map
                    ZStack(alignment: .bottom) {
                        AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuAxRqawlKN57lkRTs_AuMAPH1-yiWEo2PS5Bc5oMQ6kuOdZfK-UjWhVddxyLFYE5bENdX-iOCXmgzgiCl-bqTWofd9tqZuau_Qd3SEyj378BCc7tN1T9kUVuVGPfmvewN5dhX0VDENVciUqQnFojqmFYZgHaZxYOOfKzrOq64xp_wXEuDap4dbZ6BRX3bA6BhGD31zGO5iorHwYm6iNFyiQ3cQ2lkpk15EFl3vzMCuPM9t8aNWLCz_LD9IqZAa7NcbZf-acs7YB3Ys")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.surfaceContainerLow
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .clipped()

                        LinearGradient(
                            colors: [.clear, Color.surfaceDim.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 360)

                        VStack(alignment: .leading, spacing: 4) {
                            // Completed route label
                            HStack(spacing: 6) {
                                Image(systemName: "road.lanes")
                                    .font(.system(size: 12))
                                Text("COMPLETED ROUTE")
                                    .font(.labelCaps)
                                    .tracking(2)
                            }
                            .foregroundColor(Color.onSurface)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.surfaceContainerHighest.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.leading, 20)
                            .padding(.bottom, 4)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ride Completed")
                                        .font(.headlineLg)
                                        .foregroundColor(.white)
                                        .fontWeight(.bold)
                                    Text("Stelvio Serpent Run • Group Alpha")
                                        .font(.bodyMd)
                                        .foregroundColor(Color.onSurfaceVariant)
                                }
                                .padding(.horizontal, 20)
                                Spacer()
                            }
                        }
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 360)

                    VStack(spacing: 16) {
                        // Metrics Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricCard(label: "TOTAL DISTANCE", value: "182", unit: "KM", isPrimary: true)
                            MetricCard(label: "DURATION", value: "4:42", unit: "HRS", isPrimary: false)
                            MetricCard(label: "AVG SPEED", value: "61", unit: "KM/H", isPrimary: false)
                            MetricCard(label: "MAX GROUP SPLIT", value: "3.1", unit: "KM", isPrimary: false, isError: true)
                        }
                        .padding(.horizontal, 20)

                        // Final Order Leaderboard
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("FINAL ORDER")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.primaryFixed)
                                    .tracking(4)
                                Spacer()
                                Text("CONSISTENCY RANKING")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(1)
                            }

                            VStack(spacing: 12) {
                                ForEach(leaderboard, id: \.rank) { entry in
                                    LeaderboardRow(entry: entry)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
                        .padding(.horizontal, 20)

                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: {}) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("SHARE SUMMARY").font(.bodyLg).fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.primaryContainer)
                                .foregroundColor(Color.onPrimaryContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button(action: { dismiss() }) {
                                Text("DONE")
                                    .font(.bodyLg)
                                    .foregroundColor(Color.onSurface)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant.opacity(0.5), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 20)

                        Color.clear.frame(height: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("RIDE SUMMARY")
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
}

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let isPrimary: Bool
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.displayMetrics)
                    .foregroundColor(isError ? Color.errorColor : (isPrimary ? Color.primaryFixed : Color.onSurface))
                Text(unit).font(.labelCaps).foregroundColor(Color.onSurfaceVariant.opacity(isError ? 0.7 : 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        .shadow(color: isPrimary ? Color.primaryFixed.opacity(0.1) : .clear, radius: 8)
    }
}

struct LeaderboardRow: View {
    let entry: (rank: String, name: String, role: String, sync: String, imgUrl: String)

    var isFirst: Bool { entry.rank == "01" }

    var body: some View {
        HStack(spacing: 16) {
            Text(entry.rank)
                .font(.system(size: 24, weight: .bold))
                .italic()
                .foregroundColor(isFirst ? Color.primaryFixed : Color.onSurfaceVariant)
                .frame(width: 32)

            AsyncImage(url: URL(string: entry.imgUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.surfaceVariant)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().stroke(isFirst ? Color.primaryFixed : Color.outlineVariant, lineWidth: 1))
            .opacity(isFirst ? 1 : 0.8)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.bodyLg).foregroundColor(Color.onSurface)
                Text(entry.role).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
            }

            Spacer()

            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primaryFixed)
            }
        }
        .padding(12)
        .background(isFirst ? Color.surfaceContainerHigh : Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            HStack {
                Rectangle()
                    .fill(isFirst ? Color.primaryFixed : Color.outlineVariant.opacity(0.5))
                    .frame(width: 4)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }
}

#Preview {
    RideSummaryView()
}
