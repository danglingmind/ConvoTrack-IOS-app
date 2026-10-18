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
    /// Shown once, at the start of onboarding, after the launch check has already resolved the
    /// session (HIG: launching.md). Nothing is loading here, so it stays short (the plan's ~0.6 s
    /// minimum plus the route trace) and has no fake loading-stage text.
    var duration: Double = 1.2
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowPulse = false
    @State private var trimProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DS.Background.base.ignoresSafeArea()
                DS.Gradient.accentAura(endRadius: geo.size.height * 0.6).ignoresSafeArea()

                // Route line — vertically centred
                VStack {
                    Spacer()
                    routeLine
                    Spacer()
                }

                // Logo — 15% from the top
                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.15)
                    logoSection
                    Spacer()
                }

                // Wordmark — bottom edge 20% from the bottom
                VStack {
                    Spacer()
                    titleSection
                    Spacer().frame(height: geo.size.height * 0.20)
                }

                VStack {
                    Spacer()
                    Text("EST. 2024 — CONVOTRACK PROTOCOL V4.2")
                        .dsText(.badgeSmall)
                        .foregroundStyle(DS.Text.subtle)   // decorative; not for reading
                        .padding(.bottom, DS.Space.p4)
                        .accessibilityHidden(true)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                // Static logo and a fully drawn route line.
                trimProgress = 1
            } else {
                glowPulse = true
                withAnimation(DS.Motion.routeTrace) { trimProgress = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onFinished() }
        }
    }

    private var logoSection: some View {
        ZStack {
            Circle()
                .fill(DS.Accent.base.opacity(0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 40)
                .scaleEffect(glowPulse ? 1.05 : 1.0)
                .animation(reduceMotion ? nil : DS.Motion.glowBreath, value: glowPulse)

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)
        }
    }

    // SVG route: "M10,80 Q50,10 120,50 T250,20 T390,70"
    private var routeLine: some View {
        ZStack {
            RoutePath()
                .stroke(DS.Map.routeRail, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            RoutePath()
                .trim(from: 0, to: trimProgress)
                .stroke(DS.Accent.base, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .shadow(color: DS.Accent.glow, radius: 12)
        }
        .frame(maxWidth: 360)
        .frame(height: 120)
        .padding(.horizontal, DS.Space.p5)
        .accessibilityHidden(true)
    }

    private var titleSection: some View {
        VStack(spacing: DS.Space.p2) {
            Text("ConvoTrack")
                .dsText(.brandWordmark)
                .foregroundStyle(DS.Accent.base)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text("Multiplayer navigation")
                .dsText(.eyebrow)
                .foregroundStyle(DS.Text.muted)
        }
        .padding(.horizontal, DS.Space.p5)
    }
}

#Preview {
    SplashView()
}
