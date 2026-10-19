import SwiftUI

// MARK: - Avatar

/// Initial-only avatars get a solid colour picked from the rider id. Presence is a dot with a ring.
struct DSAvatar: View {
    let name: String
    /// Stable id used to pick the palette colour.
    let id: String
    var imageURL: URL? = nil
    var size: CGFloat = DS.AvatarSize.md
    /// nil hides the presence dot.
    var isOnline: Bool? = nil
    var highlightRing: Color? = nil

    private var initial: String { String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased() }

    private var paletteColor: Color {
        // Not hashValue: it changes between launches.
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return DS.avatarPalette[sum % DS.avatarPalette.count]
    }

    var body: some View {
        ZStack {
            Circle().fill(imageURL == nil ? paletteColor : DS.Surface.avatar)
            Text(initial)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(DS.Text.primary)
            if let imageURL {
                CachedImage(url: imageURL, pointSize: size) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay { if let highlightRing { Circle().stroke(highlightRing, lineWidth: DS.BorderWidth.focus) } }
        .overlay(alignment: .bottomTrailing) {
            if let isOnline {
                Circle()
                    .fill(isOnline ? DS.Status.success : DS.Text.subtle.base)
                    .frame(width: size * 0.29, height: size * 0.29)
                    .overlay(Circle().stroke(DS.Background.base, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)   // the row that contains it reads the name
    }
}

struct DSAvatarStack: View {
    struct Item: Identifiable { let id: String; let name: String; var imageURL: URL? = nil }

    let items: [Item]
    var maxShown = 2

    var body: some View {
        let shown = Array(items.prefix(maxShown))
        let extra = items.count - shown.count
        HStack(spacing: -8) {
            ForEach(shown) { item in
                DSAvatar(name: item.name, id: item.id, imageURL: item.imageURL, size: DS.AvatarSize.stack)
                    .overlay(Circle().stroke(DS.Background.base, lineWidth: 2))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Text.primary)
                    .frame(width: DS.AvatarSize.stack, height: DS.AvatarSize.stack)
                    .background(DS.Surface.glassOnPhoto, in: Circle())
                    .overlay(Circle().stroke(DS.Background.base, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(items.count) riders"))
    }
}

// MARK: - Badges

/// READY (lime) / WAITING (neutral) / RIDING (green). Solid fills; the word carries the state.
struct DSStatusBadge: View {
    enum Kind { case ready, waiting, riding }
    let kind: Kind

    private var title: LocalizedStringKey {
        switch kind {
        case .ready: "Ready"
        case .waiting: "Waiting"
        case .riding: "Riding"
        }
    }

    private var fill: Color {
        switch kind {
        case .ready: DS.Accent.base
        case .waiting: DS.Surface.neutralBadge
        case .riding: DS.Status.success
        }
    }

    private var ink: Color {
        switch kind {
        case .ready: DS.Text.onAccent
        case .waiting: DS.Text.muted.base
        case .riding: DS.Text.onSuccess
        }
    }

    var body: some View {
        Text(title)
            .dsText(.badge)
            .foregroundStyle(ink)
            .padding(.horizontal, DS.Space.p3)
            .frame(minHeight: 22)
            .background(fill, in: Capsule())
    }
}

/// Informational tag, deliberately quiet (outlined, not filled) so it can't be mistaken for the
/// lime action next to it (RESUME).
struct DSLeaderBadge: View {
    var body: some View {
        Text("Leader")
            .dsText(.badgeSmall)
            .foregroundStyle(DS.Text.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(DS.Border.strong, lineWidth: DS.BorderWidth.default))
    }
}

/// Membership state at a glance: PRO (earned, quiet lime outline), TRIAL · 2D (countdown,
/// amber on the last day) or GO PRO (the one filled variant — it's an invitation, not a label).
struct DSPlanBadge: View {
    enum Kind: Equatable {
        case pro
        /// `daysLeft` 1 = last day.
        case trial(daysLeft: Int)
        case goPro
    }
    let kind: Kind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the label drops "Trial ·" — the hourglass already says it — so the
    /// badge can't crowd the toolbar. VoiceOver keeps the full sentence either way.
    private var title: LocalizedStringKey {
        let compact = dynamicTypeSize.isAccessibilitySize
        switch kind {
        case .pro: return "Pro"
        case .trial(let days):
            if days <= 1 { return compact ? "Today" : "Trial · today" }
            return compact ? "\(days)d" : "Trial · \(days)d"
        case .goPro: return "Go Pro"
        }
    }

    private var systemImage: String {
        switch kind {
        case .pro: "rosette"
        case .trial: "hourglass"
        case .goPro: "sparkles"
        }
    }

    private var isLastDay: Bool { kind == .trial(daysLeft: 1) || kind == .trial(daysLeft: 0) }

    private var ink: Color {
        switch kind {
        case .pro: DS.Accent.base
        case .trial: isLastDay ? DS.Status.warning : DS.Text.primary.base
        case .goPro: DS.Pro.gold   // unused: GO PRO draws with the gold gradient
        }
    }

    private var fill: Color {
        switch kind {
        case .pro: DS.Accent.tint
        case .trial: isLastDay ? DS.Status.warningTint : DS.Surface.glassSubtle
        case .goPro: DS.Accent.base
        }
    }

    private var stroke: Color {
        switch kind {
        case .pro: DS.Accent.border
        case .trial: isLastDay ? DS.Status.warning.opacity(0.45) : DS.Border.default.base
        case .goPro: .clear
        }
    }

    private var accessibilityText: Text {
        switch kind {
        case .pro: Text("ConvoTrack Pro")
        case .trial(let days):
            days <= 1 ? Text("Free trial, ends today") : Text("Free trial, \(days) days left")
        case .goPro: Text("Go Pro")
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).dsIcon(12, weight: .bold)
            Text(title).dsText(.badgeSmall).lineLimit(1).fixedSize()
        }
        // GO PRO's text and icon carry the gold; everything else uses its flat ink.
        .foregroundStyle(kind == .goPro ? AnyShapeStyle(DS.Pro.gradient) : AnyShapeStyle(ink))
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
    }

    var body: some View {
        Group {
            if kind == .goPro {
                label.dsGoProShine(in: Capsule())
            } else {
                label
                    .background(fill, in: Capsule())
                    .overlay(Capsule().stroke(stroke, lineWidth: DS.BorderWidth.default))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// The Go Pro treatment (design option A): gold rim light, a glint that sweeps under the content
/// about every 3.2 s and a gold glow that breathes on a 2.4 s cycle. On chrome (the GO PRO chip) it
/// sits on clear interactive Liquid Glass; on content (the Profile Pro card) it sits on the normal
/// card surface instead, since glass is for the floating control layer only (`dsGlass`).
/// Reduce Motion: no sweep, steady glow. Reduce Transparency / Increase Contrast: `dsGlass`'s
/// opaque fallback, keeping the gold rim.
struct DSGoProShine<S: Shape>: ViewModifier {
    let shape: S
    /// true for chrome (chips, pills); false for cards.
    var glass = true
    /// false for still surfaces (the paywall): same gold, no glint, steady glow.
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One full cycle; the glint takes the first ~35% of it, then it rests.
    private let cycle: Double = 3.2
    private let sweepShare: Double = 0.35

    func body(content: Content) -> some View {
        if reduceMotion || !animated {
            styled(content, sweep: nil, breathe: 0.5)
        } else {
            // 30 fps is plenty for a glint and keeps an always-on element cheap.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: cycle) / cycle
                styled(content,
                       sweep: phase < sweepShare ? phase / sweepShare : nil,
                       breathe: 0.5 + 0.5 * sin(t * 2 * .pi / 2.4))
            }
        }
    }

    /// - Parameters:
    ///   - sweep: 0…1 progress of the glint across; nil while it rests.
    ///   - breathe: 0…1 glow strength.
    @ViewBuilder
    private func styled(_ content: Content, sweep: Double?, breathe: Double) -> some View {
        let glinted = content
            // The glint is drawn on the surface but under the content, so it never washes out text.
            .background {
                if let sweep {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(glass ? 0.5 : 0.14), .white.opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: max(geo.size.width * 0.38, 60), height: geo.size.height * 2.4)
                        .rotationEffect(.degrees(20))
                        .offset(x: -geo.size.width * 0.5 + sweep * geo.size.width * 1.5,
                                y: -geo.size.height * 0.7)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
        Group {
            if glass {
                glinted.dsGlass(in: shape, interactive: true)
            } else {
                glinted.background(DS.Surface.card, in: shape)
            }
        }
        .overlay(
            shape.stroke(
                LinearGradient(colors: [DS.Pro.goldLight.opacity(0.85), DS.Pro.goldDeep.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.2
            )
        )
        .shadow(color: DS.Pro.glow.opacity((glass ? 0.22 : 0.12) + (glass ? 0.3 : 0.18) * breathe),
                radius: (glass ? 5 : 8) + (glass ? 5 : 8) * breathe)
    }
}

extension View {
    /// Gold rim, glint and breathing glow for the Go Pro invitation. `glass` only on chrome.
    func dsGoProShine<S: Shape>(in shape: S, glass: Bool = true, animated: Bool = true) -> some View {
        modifier(DSGoProShine(shape: shape, glass: glass, animated: animated))
    }
}

struct DSChip: View {
    enum Variant { case positive, neutral }
    let title: LocalizedStringKey
    var variant: Variant = .neutral

    var body: some View {
        Text(title)
            .dsText(.badge)
            .foregroundStyle(variant == .positive ? DS.Text.onAccent : DS.Text.secondary.base)
            .padding(.horizontal, DS.Space.p2)
            .padding(.vertical, DS.Space.p1)
            .background(variant == .positive ? DS.Accent.base : DS.Surface.glassSubtle,
                        in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            .overlay {
                if variant == .neutral {
                    RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                        .stroke(DS.Border.default, lineWidth: DS.BorderWidth.default)
                }
            }
    }
}

/// Icon + mono value over a photo (distance, ETA on the active-ride card).
struct DSMetaChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).dsIcon(15, weight: .medium)
            Text(text).dsText(.dataMono)
        }
        .foregroundStyle(DS.Text.primary)
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(DS.Control.metaFill, in: Capsule())
        .overlay(Capsule().stroke(DS.Control.metaBorder, lineWidth: DS.BorderWidth.default))
    }
}

// MARK: - Live indicator / status pill

struct DSLiveIndicator: View {
    var title: LocalizedStringKey = "Live"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.Accent.base)
                .frame(width: 6, height: 6)
                .opacity(dim ? 0.35 : 1)
            Text(title).dsText(.badge).foregroundStyle(DS.Accent.base)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DS.Motion.livePulse) { dim = true }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DSStatusPill: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).dsIcon(11) }
            Text(title).dsText(.badge)
        }
        .foregroundStyle(DS.Text.muted)
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 6)
        .background(DS.Surface.glassSubtle, in: Capsule())
        .overlay(Capsule().stroke(DS.Border.subtle, lineWidth: DS.BorderWidth.default))
    }
}

// MARK: - Empty / error / loading / inline error

struct DSEmptyState: View {
    var systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var isError = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.p4) {
            Image(systemName: systemImage)
                .dsIcon(26, weight: .medium)
                .foregroundStyle(isError ? DS.Status.danger : DS.Accent.base)
                .frame(width: 56, height: 56)
                .background(isError ? DS.Status.dangerTint : DS.Accent.tint, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .dsText(.cardTitle)
                .foregroundStyle(DS.Text.primary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.muted)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                DSPillButton(title: actionTitle,
                             systemImage: isError ? "arrow.clockwise" : nil,
                             variant: isError ? .neutral : .primary,
                             large: true, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, DS.Space.p5)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(isError ? DS.Status.dangerBorder : DS.Border.subtle.base,
                              style: StrokeStyle(lineWidth: DS.BorderWidth.default, dash: isError ? [] : [6, 6]))
        }
        .accessibilityElement(children: .contain)
    }
}

struct DSErrorState: View {
    var title: LocalizedStringKey = "Something went wrong"
    var message: LocalizedStringKey? = nil
    var retry: () -> Void

    var body: some View {
        DSEmptyState(systemImage: "exclamationmark.circle", title: title, message: message,
                     actionTitle: "Retry", isError: true, action: retry)
    }
}

struct DSLoadingState: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(DS.Accent.base)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityLabel(Text("Loading"))
    }
}

/// Text plus an icon, never colour alone.
struct DSInlineError: View {
    let message: LocalizedStringKey

    var body: some View {
        Label {
            Text(message).dsText(.bodySmall)
        } icon: {
            Image(systemName: "exclamationmark.circle").dsIcon(DS.IconSize.sm)
        }
        .foregroundStyle(DS.Status.danger)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Preview

struct FeedbackGallery: View {
    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.p4) {
                    DSAdaptiveStack {
                        DSAvatar(name: "Asha", id: "u1", isOnline: true)
                        DSAvatar(name: "Ravi", id: "u2", isOnline: false, highlightRing: DS.Accent.base)
                        DSAvatarStack(items: [.init(id: "a", name: "A"), .init(id: "b", name: "B"), .init(id: "c", name: "C")])
                    }
                    DSAdaptiveStack { DSStatusBadge(kind: .ready); DSStatusBadge(kind: .waiting); DSStatusBadge(kind: .riding); DSLeaderBadge() }
                    DSAdaptiveStack { DSChip(title: "Ready", variant: .positive); DSChip(title: "Solo") }
                    DSAdaptiveStack { DSPlanBadge(kind: .pro); DSPlanBadge(kind: .trial(daysLeft: 2)); DSPlanBadge(kind: .trial(daysLeft: 1)); DSPlanBadge(kind: .goPro) }
                    DSAdaptiveStack { DSMetaChip(systemImage: "point.topleft.down.to.point.bottomright.curvepath", text: "51.7 km"); DSMetaChip(systemImage: "clock", text: "1h 12m") }
                    DSAdaptiveStack { DSLiveIndicator(); DSLiveIndicator(title: "Riding"); DSStatusPill(title: "Offline", systemImage: "wifi.slash") }
                    DSInlineError(message: "Couldn't join. Check the code and try again.")
                    DSEmptyState(systemImage: "flag", title: "No rides yet", message: "Create a ride or join one with an invite code.", actionTitle: "Create ride") {}
                    DSErrorState(message: "Check your connection.") {}
                    DSLoadingState()
                }
                .padding(DS.Space.screenInset)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Feedback") { FeedbackGallery() }
#Preview("Feedback AX3") { FeedbackGallery().dynamicTypeSize(.accessibility3) }
