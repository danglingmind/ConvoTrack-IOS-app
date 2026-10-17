import SwiftUI

private struct ValuePage: Identifiable {
    let id: Int
    let eyebrow: LocalizedStringKey
    let headline: LocalizedStringKey
    let body: LocalizedStringKey
    let videoName: String
    let posterName: String
    let variant: RouteBackdrop.Variant
    let description: LocalizedStringKey
}

/// Three value screens + one question. Hosted by `ContentView`; calls `onFinish` when the
/// rider reaches the end or taps Skip (both go to sign-in).
struct OnboardingFlowView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var userPaused = false

    private let pages: [ValuePage] = [
        ValuePage(id: 0,
                  eyebrow: "LIVE TRACKING",
                  headline: "Every rider. One map.",
                  body: "See where your whole pack is, second by second — even the ones you can't see.",
                  videoName: "onboarding_tracking", posterName: "onboarding_tracking_poster",
                  variant: .tracking,
                  description: "Map showing four riders moving along a route."),
        ValuePage(id: 1,
                  eyebrow: "REGROUP",
                  headline: "Nobody gets left behind.",
                  body: "Call a regroup and every phone knows where to wait. One tap for emergencies.",
                  videoName: "onboarding_regroup", posterName: "onboarding_regroup_poster",
                  variant: .regroup,
                  description: "Map showing riders converging on a regroup point."),
        ValuePage(id: 2,
                  eyebrow: "ONE LINK",
                  headline: "One link. Everyone's in.",
                  body: "Share a link. They're on the map. No group chat chaos.",
                  videoName: "onboarding_invite", posterName: "onboarding_invite_poster",
                  variant: .invite,
                  description: "Map showing a new rider joining the group."),
    ]

    private var pageCount: Int { pages.count + 1 }          // + the question
    private var onQuestion: Bool { index == pages.count }
    private var motionAllowed: Bool { OnboardingPlaybackPolicy.allowsMotion(reduceMotion: reduceMotion) }

    var body: some View {
        ZStack {
            Color.surfaceDim.ignoresSafeArea()

            Group {
                if onQuestion {
                    PackSizeQuestionView(onContinue: finish)
                } else {
                    pageView(pages[index])
                }
            }
            .id(index)
            // Cross-fade, never a slide: nothing travels across the screen when motion is reduced,
            // and it is calmer for everyone else too.
            .transition(.opacity)

            VStack(spacing: 0) {
                topBar
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -50 { advance() }
                else if value.translation.width > 50 { goBack() }
            }
        )
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            if !onQuestion && OnboardingPlaybackPolicy.allowsMotion(reduceMotion: reduceMotion) {
                Button { userPaused.toggle() } label: {
                    Image(systemName: userPaused ? "play.fill" : "pause.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceContainerHigh.opacity(0.7), in: Circle())
                }
                .accessibilityLabel(userPaused ? Text("Play background animation") : Text("Pause background animation"))
            }
            Spacer()
            Button(action: finish) {
                Text("Skip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .padding(.horizontal, 16)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.surfaceContainerHigh.opacity(0.7), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Page

    private func pageView(_ page: ValuePage) -> some View {
        ZStack(alignment: .bottom) {
            OnboardingBackdrop(
                videoName: page.videoName,
                posterName: page.posterName,
                variant: page.variant,
                isPlaying: motionAllowed && !userPaused
            )

            // Scrim: text sits in the lower part of the screen on near-opaque surface, so contrast
            // holds over the brightest frame of any clip.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.38),
                    .init(color: Color.surfaceDim.opacity(0.88), location: 0.60),
                    .init(color: Color.surfaceDim.opacity(0.97), location: 0.78),
                    .init(color: Color.surfaceDim, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Scrollable so the copy stays reachable at the largest accessibility text sizes.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.eyebrow)
                            .font(.caption.weight(.bold).monospaced())
                            .tracking(2)
                            .foregroundStyle(Color.onSurfaceVariant)
                        Text(page.headline)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(page.body)
                            .font(.body)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                .defaultScrollAnchor(.bottom)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity, alignment: .bottom)

                footer
            }
            .padding(.top, 72)   // clear of the Skip / pause row
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(page.description))
    }

    private var footer: some View {
        VStack(spacing: 18) {
            pageDots
            Button(action: advance) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.primaryFixed, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.onPrimaryFixed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.onSurface : Color.onSurfaceVariant.opacity(0.45))
                    .frame(width: i == index ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(index + 1) of \(pageCount)"))
    }

    // MARK: Navigation

    private func advance() {
        guard index < pageCount - 1 else { finish(); return }
        withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
    }

    private func goBack() {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { index -= 1 }
    }

    private func finish() { onFinish() }
}

#Preview { OnboardingFlowView(onFinish: {}) }
