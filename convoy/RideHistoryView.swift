import SwiftUI

struct RideHistoryView: View {
    private let rides: [(title: String, date: String, time: String, distance: String, duration: String, speed: String, imgUrl: String)] = [
        ("Coorg Sunrise Ride", "12 OCT 2023", "06:15 AM", "142.5 KM", "4.5 HRS", "31 KM/H",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuC0i4WtNFxs0Mo3sY3EX3Pq0fp028lBLh5SXL2aHJIj0G2sESnBQPco5x2jd29o6yb8jbGJuS6wf6C6MXpIDxDZym2Cgfqv3nc3i2mqvfTvBhHQrbLhPeOLqjGQpiJPDh0ahT-PUvh8eAmkIEuJ6IBQ-DW7PTQbHLSntEtF1aV6hidLaLxbgfRY_8EDEx9bHng53gMm4DSHujWirh53vXmQbA70QQjSsEEBYnMdBMUnCWPDVO1T7WqVw2BK8AdKy7G_eAzpPWegxGw"),
        ("Western Ghats Express", "08 OCT 2023", "04:30 PM", "210.2 KM", "6.2 HRS", "48 KM/H",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuDW7JjRvd9n97zaru5PsZFg2f9C6BVWvK-DH09BTiVPOBwlJXVQvqvbYC_N53e-U2NpH_fVj5pAI9o9vkS5j-uktzwgIlzV4HFvsFn4P6tLQ98Khq_48GH2vggUM8_IDgROrpsbFIb0mfMNqseDkDRJcfUgoh6OQdla0EFa1EiHhd2XTWjMEXwPy5IpZM8Xa7xJ4nYU0fkw9oVBPMPGvgzI270k1JjObsgGAzP2iLDwVmSkKY3Zd3MO546jHBQBnEb4FLYWDMhzYUI"),
        ("Nandi Hills Loop", "30 SEP 2023", "10:00 AM", "88.4 KM", "2.8 HRS", "35 KM/H",
         "https://lh3.googleusercontent.com/aida-public/AB6AXuAb7a0IqjYOoVF7Sb7klK9L4XWraABuuk2vcOO-c2-61iWBomjNjpM3cacIGzQ43FkbB7jk9LyolFZah9nnlrl0FencvHPexB2y8qegnbHQdla1rguX72gQti0FuRKIBEetw18pWAIjSGZvVOCZjlao1L2_61xCfkHaKuxRdZewG9XdVEPC_4_bO2VBTPEBcl5ubsDp4kXGPYAJm1xv4TOqrR5Jm6vfUi6FuwW03V9I34b8xqmKIm_XMkDM56cTo1fvltKRCb1Wd6A")
    ]

    @State private var showSummary = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72)

                    VStack(spacing: 24) {
                        // Summary dashboard
                        HStack(spacing: 8) {
                            FloatingStatPill(label: "DISTANCE", value: "2,481", unit: "KM")
                            FloatingStatPill(label: "COMPLETED", value: "42", unit: nil)
                            FloatingStatPill(label: "AVG SPEED", value: "38", unit: "km/h")
                        }
                        .padding(.horizontal, 20)

                        // Ride cards
                        VStack(spacing: 16) {
                            ForEach(rides, id: \.title) { ride in
                                Button(action: { showSummary = true }) {
                                    RideHistoryCard(
                                        title: ride.title,
                                        date: ride.date,
                                        time: ride.time,
                                        distance: ride.distance,
                                        duration: ride.duration,
                                        speed: ride.speed,
                                        imgUrl: ride.imgUrl
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)

                        Color.clear.frame(height: 120)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "RIDE HISTORY")
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSummary) {
            RideSummaryView()
        }
    }
}


struct RideHistoryCard: View {
    let title: String
    let date: String
    let time: String
    let distance: String
    let duration: String
    let speed: String
    let imgUrl: String

    var body: some View {
        VStack(spacing: 0) {
            // Map image
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: imgUrl)) { image in
                    image.resizable().scaledToFill()
                        .grayscale(0.4)
                        .opacity(0.6)
                } placeholder: {
                    Color.surfaceContainerLow
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
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

            // Details
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(date).font(.labelCaps).foregroundColor(Color.primaryFixedDim)
                        Circle().fill(Color.outlineVariant).frame(width: 4, height: 4)
                        Text(time).font(.labelCaps).foregroundColor(Color.onSurfaceVariant)
                    }
                    Text(title).font(.headlineMd).foregroundColor(Color.onSurface)
                    HStack(spacing: 20) {
                        MetricSmall(label: "DISTANCE", value: distance)
                        MetricSmall(label: "DURATION", value: duration)
                        MetricSmall(label: "AVG SPEED", value: speed)
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
