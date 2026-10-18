import SwiftUI
import AVKit
import AVFoundation

// MARK: - Playback policy

/// Whether decorative onboarding video may move. Poster-only when the rider has asked the
/// system for less motion, turned autoplay off, or is on Low Power Mode (our choice).
enum OnboardingPlaybackPolicy {
    static func allowsMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
            && UIAccessibility.isVideoAutoplayEnabled
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Backdrop

/// Full-bleed visual behind an onboarding page. Resolution order:
///   1. bundled `<videoName>.mp4`  → looping, silent video
///   2. bundled `<posterName>` image asset (a real screenshot) → still image
///   3. `RouteBackdrop` — a code-drawn stand-in so the flow is buildable before footage exists
struct OnboardingBackdrop: View {
    let videoName: String
    let posterName: String
    let variant: RouteBackdrop.Variant
    /// False (Reduce Motion, autoplay off, Low Power) = poster only. The video layer is not
    /// mounted at all: a paused player still draws its first frame over the poster, and the
    /// poster is the frame chosen to tell the whole story.
    let allowsMotion: Bool
    /// False = hold on the current frame (the rider tapped pause) / freeze the stand-in.
    let isPlaying: Bool

    var body: some View {
        ZStack {
            DS.Background.deep

            if allowsMotion, let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                poster
                LoopingVideoView(url: url, isPlaying: isPlaying)
            } else if UIImage(named: posterName) != nil {
                poster
            } else {
                RouteBackdrop(variant: variant, isAnimating: isPlaying)
            }
        }
        .ignoresSafeArea()
        // Decorative: the copy carries all of the meaning.
        .accessibilityHidden(true)
    }

    @ViewBuilder private var poster: some View {
        if UIImage(named: posterName) != nil {
            Image(posterName).resizable().scaledToFill()
        }
    }
}

// MARK: - Looping video

/// Silent looping video. Never touches the audio session's active state, so a rider's music
/// keeps playing; the clips are shipped without an audio track as well.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerContainer {
        let view = PlayerContainer()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ view: PlayerContainer, context: Context) {
        isPlaying ? view.play() : view.pause()
    }

    static func dismantleUIView(_ view: PlayerContainer, coordinator: ()) {
        view.teardown()
    }

    final class PlayerContainer: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?
        private var wantsPlayback = false

        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func configure(url: URL) {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            playerLayer.player = queue
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear

            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.player?.pause() }
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.wantsPlayback else { return }
                self.player?.play()
            }
        }

        func play()  { wantsPlayback = true;  player?.play() }
        func pause() { wantsPlayback = false; player?.pause() }

        func teardown() {
            player?.pause()
            looper?.disableLooping()
            [backgroundObserver, foregroundObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
            playerLayer.player = nil
            player = nil
            looper = nil
        }
    }
}

// MARK: - Stand-in artwork

/// A drawn "live map": dark grid, lime route, riders moving along it. Stands in for the real
/// footage/screenshots and is also the fallback if a clip is ever missing from the bundle.
struct RouteBackdrop: View {
    enum Variant { case tracking, regroup, invite }

    let variant: Variant
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                draw(into: &ctx, size: size, time: isAnimating ? t : 0)
            }
        }
    }

    // MARK: Drawing

    private func routePoints(in size: CGSize) -> [CGPoint] {
        let phase: Double = {
            switch variant {
            case .tracking: return 0
            case .regroup:  return 1.4
            case .invite:   return 2.6
            }
        }()
        return (0...80).map { i in
            let p = Double(i) / 80
            let x = size.width * (0.14 + 0.62 * (0.5 + 0.5 * sin(p * 5.2 + phase)))
            let y = size.height * (0.15 + 0.52 * p)
            return CGPoint(x: x, y: y)
        }
    }

    private func point(on pts: [CGPoint], at progress: Double) -> CGPoint {
        let p = min(max(progress, 0), 0.999) * Double(pts.count - 1)
        let i = Int(p), f = CGFloat(p - Double(i))
        let a = pts[i], b = pts[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private func draw(into ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Faint street grid
        var grid = Path()
        let step: CGFloat = 46
        stride(from: CGFloat(0), through: size.width, by: step).forEach {
            grid.move(to: CGPoint(x: $0, y: 0)); grid.addLine(to: CGPoint(x: $0, y: size.height))
        }
        stride(from: CGFloat(0), through: size.height, by: step).forEach {
            grid.move(to: CGPoint(x: 0, y: $0)); grid.addLine(to: CGPoint(x: size.width, y: $0))
        }
        ctx.stroke(grid, with: .color(DS.Border.strongColor.opacity(0.18)), lineWidth: 1)

        // Route
        let pts = routePoints(in: size)
        var route = Path()
        route.move(to: pts[0])
        pts.dropFirst().forEach { route.addLine(to: $0) }
        ctx.stroke(route, with: .color(DS.Accent.base.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        ctx.stroke(route, with: .color(DS.Accent.base),
                   style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        // Riders. Loop progress so the clip is seamless.
        let loop = (time / 9).truncatingRemainder(dividingBy: 1)
        let leader = 0.18 + loop * 0.5
        let gaps: [Double] = variant == .regroup
            ? [0, 0.05 + 0.07 * (1 - abs(sin(loop * .pi))), 0.10 + 0.14 * (1 - abs(sin(loop * .pi))), 0.16 + 0.22 * (1 - abs(sin(loop * .pi)))]
            : [0, 0.07, 0.14, 0.21]

        if variant == .regroup {
            let gather = point(on: pts, at: leader)
            let pulse = CGFloat((time * 0.7).truncatingRemainder(dividingBy: 1))
            let r = 22 + 70 * pulse
            ctx.stroke(Path(ellipseIn: CGRect(x: gather.x - r, y: gather.y - r, width: r * 2, height: r * 2)),
                       with: .color(DS.Status.danger.opacity(0.6 * (1 - pulse))), lineWidth: 3)
        }

        for (idx, gap) in gaps.enumerated() {
            let p = point(on: pts, at: leader - gap)
            let isLeader = idx == 0
            let radius: CGFloat = isLeader ? 12 : 9
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius - 5, y: p.y - radius - 5, width: (radius + 5) * 2, height: (radius + 5) * 2)),
                     with: .color(DS.Background.base.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(isLeader ? DS.Accent.base : DS.Status.success))
        }

        // Invite variant: a join "ping" travelling to a new rider
        if variant == .invite {
            let p = point(on: pts, at: max(leader - 0.34, 0.02))
            let pulse = CGFloat((time * 0.5).truncatingRemainder(dividingBy: 1))
            let r = 10 + 40 * pulse
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(DS.Status.success.opacity(0.7 * (1 - pulse))), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                     with: .color(DS.Status.success))
        }
    }
}
