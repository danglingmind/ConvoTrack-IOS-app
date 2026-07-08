import SwiftUI

// Exact SVG path from Stitch: M10,80 Q50,10 120,50 T250,20 T390,70
// ViewBox: "0 -20 400 120" — coordinate range x:[0,400] y:[-20,100]
private struct RoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 400.0
        let sy = rect.height / 120.0
        // Shift y by +20 to map SVG's -20 origin to SwiftUI's 0 origin
        return Path { p in
            p.move(to: CGPoint(x: 10 * sx, y: (80 + 20) * sy))
            // Q50,10 → 120,50
            p.addQuadCurve(
                to:      CGPoint(x: 120 * sx, y: (50 + 20) * sy),
                control: CGPoint(x:  50 * sx, y: (10 + 20) * sy)
            )
            // T250,20 — smooth quad, reflected control: (190, 90)
            p.addQuadCurve(
                to:      CGPoint(x: 250 * sx, y: (20 + 20) * sy),
                control: CGPoint(x: 190 * sx, y: (90 + 20) * sy)
            )
            // T390,70 — smooth quad, reflected control: (310, -50)
            p.addQuadCurve(
                to:      CGPoint(x: 390 * sx, y: (70 + 20) * sy),
                control: CGPoint(x: 310 * sx, y: (-50 + 20) * sy)
            )
        }
    }
}

struct SplashView: View {
    @State private var loadingText = "INITIALIZING GPS..."
    @State private var glowPulse = false
    @State private var trimProgress: CGFloat = 0
    @State private var navigateToAuth = false

    private let stages = ["INITIALIZING GPS...", "SYNCING SQUAD...", "CACHING MAPS...", "PREPARING HUD..."]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "0e0e0e").ignoresSafeArea()

                // Route line — vertically centered in screen (like flex-grow container)
                VStack {
                    Spacer()
                    routeLine
                    Spacer()
                }

                // Logo — top 15% absolute (like `absolute top-[15%]`)
                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.15)
                    logoSection
                    Spacer()
                }

                // Title + loading — bottom edge at 20% from bottom (like `fixed bottom-[20%]`)
                VStack {
                    Spacer()
                    titleSection
                    Spacer().frame(height: geo.size.height * 0.20)
                }

                // Footer — pinned to very bottom (like `fixed bottom-gutter`)
                VStack {
                    Spacer()
                    Text("EST. 2024 — CONVOTRACK PROTOCOL V4.2")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.3))
                        .tracking(1)
                        .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            glowPulse = true
            // Matches: animation: dash 3s cubic-bezier(0.4, 0, 0.2, 1) infinite
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 3).repeatForever(autoreverses: false)) {
                trimProgress = 1
            }
            startLoadingCycle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                navigateToAuth = true
            }
        }
        .fullScreenCover(isPresented: $navigateToAuth) {
            AuthView()
        }
    }

    private var logoSection: some View {
        ZStack {
            Circle()
                .fill(Color.primaryFixed.opacity(0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 40)
                .scaleEffect(glowPulse ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowPulse)

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
        }
    }

    // Matches: SVG w-full max-w-[360px] h-48 overflow-visible viewBox="0 -20 400 120"
    private var routeLine: some View {
        ZStack {
            // Background track: stroke="#353535"
            RoutePath()
                .stroke(Color.surfaceContainerHighest, style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Animated lime path with glow: stroke-dashoffset animation + drop-shadow(0 0 12px ...)
            RoutePath()
                .trim(from: 0, to: trimProgress)
                .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .shadow(color: Color.primaryFixed.opacity(0.7), radius: 12)
        }
        .frame(maxWidth: 360)
        .frame(height: 120)
        .padding(.horizontal, 20)
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            // font-display-metrics text-display-metrics: 48px bold tracking-tighter uppercase
            Text("convotrack")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(Color.primaryFixed)
                .tracking(-1)
                .textCase(.uppercase)

            // font-label-caps tracking-[0.2em] opacity-80
            Text("MULTIPLAYER NAVIGATION")
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(8)
                .opacity(0.8)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.primaryFixed)
                    .frame(width: 6, height: 6)
                    .opacity(glowPulse ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.9).repeatForever(), value: glowPulse)

                Text(loadingText)
                    .font(.labelCaps)
                    .foregroundColor(Color.primaryFixed.opacity(0.7))
                    .tracking(2)
            }
            .padding(.top, 8)
        }
    }

    private func startLoadingCycle() {
        var index = 0
        Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { timer in
            index = (index + 1) % stages.count
            loadingText = stages[index]
            if navigateToAuth { timer.invalidate() }
        }
    }
}

#Preview {
    SplashView()
}
