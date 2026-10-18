import SwiftUI
import UIKit

// MARK: - Haptics (interaction.haptics.*.ios)

enum DSHaptic {
    /// Primary action: medium impact.
    static func primary() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Selection: light.
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Destructive: warning.
    static func destructive() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    /// Incoming alert (emergency banner, group split).
    static func alert() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Liquid Glass (chrome only)

private struct DSGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let clear: Bool
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            // Opaque fallback listed for the glass tokens.
            content
                .background(DS.Surface.glassStrong, in: shape)
                .overlay(shape.stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
        } else if clear {
            content.glassEffect(.clear, in: shape)
        } else if interactive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// Liquid Glass for chrome (buttons, pills, HUD). Falls back to an opaque fill under Reduce
    /// Transparency or Increase Contrast. Never use on cards or rows.
    func dsGlass<S: Shape>(in shape: S, clear: Bool = false, interactive: Bool = false) -> some View {
        modifier(DSGlassModifier(shape: shape, clear: clear, interactive: interactive))
    }

    func dsGlass(clear: Bool = false, interactive: Bool = false) -> some View {
        dsGlass(in: Capsule(), clear: clear, interactive: interactive)
    }
}

// MARK: - Adaptive stack

/// Horizontal at normal text sizes, vertical (leading-aligned) at accessibility sizes
/// (`layout.md › Adaptability`).
struct DSAdaptiveStack<Content: View>: View {
    var spacing: CGFloat = DS.Space.p3
    var verticalAlignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: verticalAlignment, spacing: spacing) { content }
        }
    }
}

// MARK: - Press style

struct DSPressStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? DS.Opacity.pressed : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - FloatingButton

/// Circular glass button over a photo or map. Icon-only, so `label` is required.
struct DSFloatingButton: View {
    enum Variant { case standard, accentIcon, onDark }

    let systemImage: String
    let label: LocalizedStringKey
    var variant: Variant = .standard
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .dsIcon(DS.IconSize.default, weight: .medium)
                .foregroundStyle(variant == .accentIcon ? DS.Accent.base : DS.Text.primary.base)
                .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                .contentShape(Circle())
        }
        .buttonStyle(DSPressStyle(scale: 0.95))
        .dsGlass(in: Circle(), clear: variant != .onDark, interactive: true)
        .accessibilityLabel(label)
    }
}

// MARK: - ConnectionStatusButton

enum DSConnectionState { case connected, reconnecting, offline }

/// Antenna button. Only show it while a ride session exists, or when the app is offline.
struct DSConnectionStatusButton: View {
    let state: DSConnectionState
    /// In a navigation-bar toolbar iOS 26 already draws the glass circle, so skip our own.
    var isToolbarItem = false
    var action: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var iconColor: Color {
        switch state {
        case .connected: DS.Text.primary.base
        case .reconnecting: DS.Status.warning
        case .offline: DS.Text.muted.base
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected: DS.Status.success
        case .reconnecting: DS.Status.warning
        case .offline: DS.Text.subtle.base
        }
    }

    private var stateWords: LocalizedStringKey {
        switch state {
        case .connected: "Live · connected to ride"
        case .reconnecting: "Reconnecting…"
        case .offline: "Offline"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .dsIcon(DS.IconSize.default, weight: .medium)
                .foregroundStyle(iconColor)
                .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(DS.Background.base, lineWidth: 2))
                        .opacity(state == .reconnecting && pulse ? 0.35 : 1)
                        .padding(10)
                }
        }
        .buttonStyle(DSPressStyle(scale: 0.95))
        .modifier(OptionalGlass(enabled: !isToolbarItem))
        .accessibilityLabel(Text("Connection status"))
        .accessibilityValue(Text(stateWords))
        .onAppear { updatePulse() }
        .onChange(of: state) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard state == .reconnecting, !reduceMotion else { pulse = false; return }
        withAnimation(DS.Motion.livePulse) { pulse = true }
    }
}

private struct OptionalGlass: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.dsGlass(in: Circle(), clear: true, interactive: true) } else { content }
    }
}

// MARK: - SectionHeading

struct DSSectionHeading<Trailing: View>: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var heading: some View {
        HStack(spacing: DS.Space.p2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .dsIcon(DS.IconSize.sm)
                    .foregroundStyle(DS.Accent.base)
                    .accessibilityHidden(true)
            }
            Text(title)
                .dsText(.sectionLabel)
                .foregroundStyle(DS.Text.label)
                .accessibilityAddTraits(.isHeader)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The trailing control drops under the heading instead of pushing the page wider.
                VStack(alignment: .leading, spacing: DS.Space.p2) {
                    heading
                    trailing
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    heading
                    Spacer(minLength: DS.Space.p3)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }
}

extension DSSectionHeading where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = EmptyView()
    }
}

/// Trailing "SEE ALL >" action for a section heading.
struct DSSectionAction: View {
    let title: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).dsText(.sectionAction)
                Image(systemName: "chevron.right").dsIcon(DS.IconSize.xs, weight: .semibold)
            }
            .foregroundStyle(DS.Text.label)
            .frame(minHeight: DS.Target.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HeroTitleBlock

struct DSHeroTitleBlock: View {
    var eyebrow: LocalizedStringKey? = nil
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    /// heroTitleCompact (30 pt) for the smaller photo headers such as History.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow).dsText(.eyebrow).foregroundStyle(DS.Text.label)
            }
            Text(title)
                .dsText(compact ? .heroTitleCompact : .heroTitle)
                .foregroundStyle(DS.Text.onPhoto)
                .lineLimit(2)
                .dsShadow(DS.Shadow.textOnPhoto)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .dsText(.heroSubtitle)
                    .foregroundStyle(DS.Text.secondary)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - GlassPill

struct DSGlassPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, DS.Space.p3)
            .frame(minHeight: 34)
            .dsGlass(clear: true)
    }
}

// MARK: - Dividers

struct DSDivider: View {
    var body: some View {
        Rectangle().fill(DS.Border.divider).frame(height: DS.BorderWidth.hairline)
    }
}

struct DSOrDivider: View {
    var body: some View {
        HStack(spacing: DS.Space.p4) {
            Rectangle().fill(DS.Border.divider).frame(height: 1)
            Text("Or").dsText(.badge).foregroundStyle(DS.Text.muted)
            Rectangle().fill(DS.Border.divider).frame(height: 1)
        }
        .padding(.vertical, DS.Space.p2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Or"))
    }
}

// MARK: - Backdrop and hero photo

/// App background gradient. Put it behind every screen.
struct DSScreenBackground: View {
    var body: some View {
        DS.Gradient.appBackground.ignoresSafeArea()
    }
}

/// Hero photo that fades into the base. Decorative; the headline carries the meaning.
struct DSHeroPhoto: View {
    let imageName: String
    /// nil fills whatever it is used as a background for (content that can grow with text size).
    var height: CGFloat? = 300
    var imageOpacity: Double = 1
    /// Adds the left-side fade that keeps the headline legible (Home).
    var sideFade = false

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .opacity(imageOpacity)
            if sideFade { DS.Gradient.photoSideFade }
            DS.Gradient.photoFade
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)   // decorative: must never swallow taps meant for the content on top
        .accessibilityHidden(true)
    }
}

// MARK: - Sticky bottom action

extension View {
    /// Sticky primary action above the tab bar / home indicator, with a 32 pt fade above it.
    func dsStickyBottomAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        let built = action()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            built
                .padding(.horizontal, DS.Space.screenInset)
                .padding(.top, DS.Space.p3)
                .padding(.bottom, DS.Space.p3)
                // Solid base behind the button (a disabled, translucent button must not show the
                // content scrolling under it) with the 32 pt fade above.
                .background(DS.Background.base)
                .background(alignment: .top) {
                    DS.Gradient.bottomActionFade
                        .frame(height: DS.Space.p8)
                        .offset(y: -DS.Space.p8)
                        .allowsHitTesting(false)
                }
        }
    }
}

// MARK: - Previews

struct ChromeGallery: View {
    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                    ZStack(alignment: .bottomLeading) {
                        DSHeroPhoto(imageName: "hero_riders_sunset_mirrored", height: 240, sideFade: true)
                        DSHeroTitleBlock(eyebrow: "Ride together", title: "Discover new roads", subtitle: "Plan it. Ride it. Together.")
                            .padding(DS.Space.screenInset)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.p4) {
                        DSAdaptiveStack(spacing: DS.Space.p3) {
                            DSFloatingButton(systemImage: "chevron.backward", label: "Back") {}
                            DSFloatingButton(systemImage: "pencil", label: "Edit ride", variant: .onDark) {}
                            DSConnectionStatusButton(state: .connected)
                            DSConnectionStatusButton(state: .reconnecting)
                            DSConnectionStatusButton(state: .offline)
                        }
                        DSSectionHeading(title: "Recent rides") { DSSectionAction(title: "See all") {} }
                        DSGlassPill { Text("Point at a ConvoTrack QR code").dsText(.bodyStrong).foregroundStyle(DS.Text.primary) }
                        DSOrDivider()
                    }
                    .padding(.horizontal, DS.Space.screenInset)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Chrome") { ChromeGallery() }
#Preview("Chrome AX3") { ChromeGallery().dynamicTypeSize(.accessibility3) }
