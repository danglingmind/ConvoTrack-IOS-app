import SwiftUI
import MapKit

// MARK: - Data Model

struct RiderOnMap: Identifiable {
    let id: Int
    let name: String
    let rank: Int
    let distanceToGoal: Double
    let speed: Int
    let imgUrl: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Main View

struct RideNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12.3800, longitude: 75.7750),
            span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22)
        )
    )
    @State private var selectedRider: RiderOnMap? = nil
    @State private var showRegroup = false
    @State private var regroupReason: CoordinationOverlayView.RegroupReason? = nil
    @State private var isPTTActive = false

    private let destination = "Mandalpatti Peak"

    private let riders: [RiderOnMap] = [
        RiderOnMap(id: 0, name: "Alex", rank: 1, distanceToGoal: 12.4, speed: 78,
                   imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuBQNuWhOtF3DXKKQ0DmErPqLF0oWDEa_-eO_fw2AexTNja0nmY07Crqv4TCZJawBTn6os3ACLTv3mZTFhDslWlfmm2OF0AgcFr-KOQhPjchRckoWnqjcsVN2-m3S21KpfeytbD7v63RnTqD3SO3RU9s3t3mlBVanN5ZatrrH4QuHdipl3aKe01_73ao6RBFd8A49aHQzsR__L8HmO1wfsZUemj_waCy5WqREtcvUG0Q6ZLjKUGliBZrcE28kioiP8cgYeAipweSYSg",
                   coordinate: CLLocationCoordinate2D(latitude: 12.4350, longitude: 75.7220)),
        RiderOnMap(id: 1, name: "Sam", rank: 2, distanceToGoal: 18.1, speed: 82,
                   imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuC0FnjMnOzopKSx-C6lRFSxZB2IDrZQfCAB7FkhPazac9ff8lLnRu_YfTbe5Uh9efwQ-LAuzMBi36kfb6tMjbCkObZgTPHzutgzCb4M1EI1u7sU7Dp4nWFQ_GKZuU0xKTnsK2QsQ8BNxqDx37boXDA04tWO1xgsvrV2v7EWL8rtwialXEjze2pI-vtQvi-VKlIgMoMW7KSVcNFGqHbnvU2iDfPdQxXdCr93DDPaHfK6cKZ_eFfbJs5hxL-6A5mFdkZ-JdwFrNMGQjU",
                   coordinate: CLLocationCoordinate2D(latitude: 12.4100, longitude: 75.7480)),
        RiderOnMap(id: 2, name: "Rahul", rank: 3, distanceToGoal: 24.7, speed: 71,
                   imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDmmB6IbIMz2C0QhSGsvfXl8savmkcfxNSmLZI6rgxq7PlCnBGef1D6-S5QJtzfePXR70mpXdxDchrfvxQFaqk8iLFh9QsdXA4AlbYdlSIkEVxfQinHlQ4pM_W3jo2UbXqjIGv575AdAwq5iLd8E60x-PKS-WuJ1sYx9tMCv_4kwlhAR-nlKIECtDYhdZXnSiBTuTwS53qExqViWRZ6Fbm9SrtAEPGpyGWIXZl4GqGzb21KQl__8ID34SnzCZWLhBb5VrUvidAJRT8",
                   coordinate: CLLocationCoordinate2D(latitude: 12.3700, longitude: 75.7880)),
        RiderOnMap(id: 3, name: "Yash", rank: 4, distanceToGoal: 31.2, speed: 69,
                   imgUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuDZPbGMUietTU8vTKMiMrZURdftPeVXwBal64HbaxnuPTrbhm3VeCUV2QWIqgaZwBQpcjl9EK5m9ZJO48JerTdaH814KROSLqUcy8et1yq5qoa1QqJ8MY-b3HNZJZeAGX2GKKivgzlSmsPOpJJVv8kfBbKFpXwa55Wu59qhYSq25YV0uUvBKyqPQ8sCIS413OOCyHNkQzol5B8zksBCJaL62MwKxK3hyKn3dKsQ71V9lZaFXdP40IP8O6Q16D2ioN5sTL9A7_w4dpw",
                   coordinate: CLLocationCoordinate2D(latitude: 12.3300, longitude: 75.8300)),
    ]

    var body: some View {
        ZStack {
            mapLayer
            hudLayer
            rightStatPills
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { appState.isRideActive = true }
        .onDisappear { appState.isRideActive = false }
        .sheet(isPresented: $showRegroup) {
            RegroupBottomSheet(selectedReason: $regroupReason, onBroadcast: {
                showRegroup = false
            }, isBroadcasting: false)
            .presentationDetents([.large])
        }
    }

    // MARK: - Layers

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            ForEach(riders) { rider in
                Annotation(rider.name, coordinate: rider.coordinate, anchor: .bottom) {
                    RiderMapPin(rider: rider, isSelected: selectedRider?.id == rider.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedRider = (selectedRider?.id == rider.id) ? nil : rider
                            }
                        }
                }
            }

            Annotation("", coordinate: CLLocationCoordinate2D(latitude: 12.4600, longitude: 75.7050), anchor: .bottom) {
                DestinationPin(name: destination)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    private var hudLayer: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomControls
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                }

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.primaryFixed)
                        Text("RANK 4")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))

                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.primaryFixed)
                            .frame(width: 7, height: 7)
                            .shadow(color: Color.primaryFixed, radius: 5)
                        Text("8 RIDERS LIVE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)

            leaderboardStrip
        }
        .padding(.top, 8)
    }

    private var leaderboardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(riders.sorted(by: { $0.rank < $1.rank })) { rider in
                        LeaderboardCard(rider: rider, isSelected: selectedRider?.id == rider.id)
                            .id(rider.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedRider?.id) { _, id in
                if let id {
                    withAnimation(.spring(response: 0.4)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 14) {
            navInstructionBanner

            HStack(spacing: 10) {
                regroupButton
                pttButton
                endRideButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.surfaceDim.opacity(0.65), Color.surfaceDim.opacity(0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var navInstructionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.onPrimaryFixed)
                .frame(width: 52, height: 52)
                .background(Color.primaryFixed)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("IN 2.4 KM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.primaryFixed)
                    .tracking(2)
                Text("Turn right onto Madikeri Road")
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)
                    .fontWeight(.semibold)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("31.2 km")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(Color.onSurface)
                Text("TO DEST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(1)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private var regroupButton: some View {
        Button(action: { showRegroup = true }) {
            VStack(spacing: 5) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 19))
                Text("REGROUP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(Color.onSurface)
            .frame(width: 76, height: 72)
            .background(Color.surfaceContainerHigh.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        }
    }

    private var pttButton: some View {
        Button(action: { withAnimation(.spring(response: 0.2)) { isPTTActive.toggle() } }) {
            VStack(spacing: 5) {
                Image(systemName: isPTTActive ? "mic.fill" : "mic")
                    .font(.system(size: 26, weight: .bold))
                Text(isPTTActive ? "TALKING" : "HOLD TALK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(isPTTActive ? Color.onPrimaryFixed : Color.onPrimaryFixed)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isPTTActive ? Color.tertiaryFixed : Color.primaryFixed)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: (isPTTActive ? Color.tertiaryFixed : Color.primaryFixed).opacity(0.45), radius: 14)
            .scaleEffect(isPTTActive ? 1.04 : 1)
        }
    }

    private var endRideButton: some View {
        Button(action: { dismiss() }) {
            VStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19))
                Text("END RIDE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(Color.errorColor)
            .frame(width: 76, height: 72)
            .background(Color.errorContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: - Right Stat Pills

    private var rightStatPills: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 9) {
                    NavStatPill(label: "SPEED", value: "69", unit: "KM/H")
                    NavStatPill(label: "ETA", value: "14:32", unit: nil)
                    NavStatPill(label: "DIST", value: "31.2", unit: "KM")
                }
                .padding(.trailing, 14)
            }
            Spacer()
        }
        .padding(.top, 180)
        .padding(.bottom, 220)
    }

    // MARK: - Route

    private var routeCoordinates: [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: 12.3100, longitude: 75.8600),
            CLLocationCoordinate2D(latitude: 12.3300, longitude: 75.8300),
            CLLocationCoordinate2D(latitude: 12.3500, longitude: 75.8100),
            CLLocationCoordinate2D(latitude: 12.3700, longitude: 75.7880),
            CLLocationCoordinate2D(latitude: 12.3900, longitude: 75.7700),
            CLLocationCoordinate2D(latitude: 12.4100, longitude: 75.7480),
            CLLocationCoordinate2D(latitude: 12.4350, longitude: 75.7220),
            CLLocationCoordinate2D(latitude: 12.4600, longitude: 75.7050),
        ]
    }
}

// MARK: - Rider Map Pin

struct RiderMapPin: View {
    let rider: RiderOnMap
    let isSelected: Bool

    private var size: CGFloat { isSelected ? 52 : 42 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.surfaceContainerHigh)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(
                            isSelected ? Color.primaryFixed : Color.outlineVariant.opacity(0.6),
                            lineWidth: isSelected ? 3 : 2
                        )
                    )
                    .shadow(color: Color.primaryFixed.opacity(isSelected ? 0.6 : 0.2), radius: isSelected ? 14 : 5)

                AsyncImage(url: URL(string: rider.imgUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.surfaceVariant)
                }
                .frame(width: size - 8, height: size - 8)
                .clipShape(Circle())

                // Rank badge
                Text("\(rider.rank)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(Color.onPrimaryFixed)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(rider.rank == 1 ? Color.primaryFixed : Color.surfaceContainerHighest)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 5, y: 5)
                    .frame(width: size, height: size)
            }

            // Small triangle pointer
            Triangle()
                .fill(isSelected ? Color.primaryFixed : Color.outlineVariant.opacity(0.6))
                .frame(width: 10, height: 6)
                .offset(y: -1)

            // Name tag
            if isSelected {
                Text(rider.name.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(Color.onSurface)
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceContainerHigh.opacity(0.92))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Destination Pin

struct DestinationPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.primaryFixed)
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.primaryFixed.opacity(0.7), radius: 12)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }
            Triangle()
                .fill(Color.primaryFixed)
                .frame(width: 10, height: 6)
                .offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Leaderboard Card

struct LeaderboardCard: View {
    let rider: RiderOnMap
    var isSelected: Bool = false

    private var isLeader: Bool { rider.rank == 1 }
    private var isHighlighted: Bool { isLeader || isSelected }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rider.rank)")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurfaceVariant)
                .frame(width: 26)

            AsyncImage(url: URL(string: rider.imgUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.surfaceVariant)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.4),
                    lineWidth: isHighlighted ? 2 : 1
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(rider.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.onSurface)
                HStack(spacing: 3) {
                    Text(String(format: "%.1f", rider.distanceToGoal))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurfaceVariant)
                    Text("KM TO GO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHighlighted ? Color.primaryFixed.opacity(0.12) : Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.3),
                    lineWidth: isHighlighted ? 1.5 : 1
                )
        )
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Nav Stat Pill

struct NavStatPill: View {
    let label: String
    let value: String
    let unit: String?
    var accentColor: Color? = nil

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(1)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(accentColor ?? Color.onSurface)
            if let unit {
                Text(unit)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.onSurfaceVariant)
            } else {
                Text(" ")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    NavigationStack {
        RideNavigationView()
    }
}
