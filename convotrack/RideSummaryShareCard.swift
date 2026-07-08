import SwiftUI

struct RideSummaryShareCard: View {
    let rideTitle: String
    let mapImage: UIImage?
    let distanceKm: String
    let durationFormatted: String
    let durationUnit: String
    let avgSpeedKmh: String
    let riderCount: Int
    let qrImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            mapBackground
            gradientOverlay
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                floatingStats
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                rideInfo
                    .padding(.horizontal, 20)
                    .padding(.bottom, 0)
                footer
            }
        }
        .frame(width: 390, height: 700)
        .colorScheme(.dark)
    }

    // MARK: - Map background

    private var mapBackground: some View {
        Group {
            if let img = mapImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 390, height: 700)
                    .clipped()
            } else {
                Color(hex: "131313")
                    .frame(width: 390, height: 700)
                    .overlay(
                        Image(systemName: "map.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Color.primaryFixed.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Gradient

    private var gradientOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(hex: "131313").opacity(0.15), location: 0.38),
                .init(color: Color(hex: "131313").opacity(0.88), location: 0.68),
                .init(color: Color(hex: "131313"), location: 0.78)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Floating stats

    private var floatingStats: some View {
        HStack(alignment: .bottom, spacing: 24) {
            statItem(value: distanceKm, unit: "KM", label: "DISTANCE", accent: true)
            statItem(value: durationFormatted, unit: durationUnit, label: "DURATION", accent: false)
            statItem(value: avgSpeedKmh, unit: "KMH", label: "AVG SPEED", accent: false)
            if riderCount > 0 {
                statItem(value: "\(riderCount)", unit: "", label: "RIDERS", accent: false)
            }
        }
    }

    private func statItem(value: String, unit: String, label: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(accent ? Color.primaryFixed : .white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurfaceVariant)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(0.5)
        }
    }

    // MARK: - Ride info

    private var rideInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("RIDE COMPLETED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
            }
            .foregroundColor(Color.tertiaryFixed)

            Text(rideTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text("CONVOTRACK")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(Color.primaryFixed)
                    .tracking(3)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let qr = qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .padding(5)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("DOWNLOAD APP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(1.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .background(
            Color(hex: "131313")
                .overlay(
                    Rectangle()
                        .fill(Color.primaryFixed.opacity(0.5))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
}
