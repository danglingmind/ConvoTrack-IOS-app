import SwiftUI

// Navigation HUD components. Glass sits on the functional layer only: the turn card, the banner
// slot, the bottom bar and the small floating controls. Rows of content (leaderboard cards) and
// solid-fill chips are opaque. The map is content. Apply `.dsHUDTypeSize()` on the HUD container so text
// is capped at AX2, and keep targets at 48 pt or more.

// MARK: - Turn instruction

/// What is wrong with the guidance right now, shown on the turn card. Off-route wins.
enum NavStatus {
    case offRoute, reconnecting
}

struct DSTurnInstructionCard: View {
    let systemImage: String
    /// Empty hides the distance line.
    let distance: String
    var instruction: String? = nil
    /// One line above the distance: the guidance is unreliable, and why. Tints the border.
    var status: NavStatus? = nil
    /// SF Symbol of the maneuver after this one (a quick double turn), with its spoken form.
    var thenSystemImage: String? = nil
    var thenSpoken: String? = nil
    var isLandscape = false
    @ScaledMetric(relativeTo: .title2) private var portraitTile: CGFloat = 56
    @ScaledMetric(relativeTo: .title2) private var landscapeTile: CGFloat = 48

    private var border: Color {
        switch status {
        case .offRoute:     DS.Status.dangerBorder
        case .reconnecting: DS.Status.warning.opacity(0.5)
        case nil:           DS.Accent.border
        }
    }

    private func statusLine(_ status: NavStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .offRoute:
                Image(systemName: "exclamationmark.triangle.fill").dsIcon(DS.IconSize.xs)
                Text("Off route · rerouting…").dsText(.badge)
            case .reconnecting:
                ProgressView().controlSize(.mini).tint(DS.Status.warning)
                Text("Reconnecting…").dsText(.badge)
            }
        }
        .foregroundStyle(status == .offRoute ? DS.Status.danger : DS.Status.warning)
        .lineLimit(1)
    }

    var body: some View {
        let tile = isLandscape ? landscapeTile : portraitTile
        HStack(spacing: DS.Space.p3) {
            Image(systemName: systemImage)
                .dsIcon(isLandscape ? 24 : 28, weight: .bold)
                .foregroundStyle(DS.Text.onAccent)
                .frame(width: tile, height: tile)
                .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .accessibilityHidden(true)
            // No Spacer on purpose: the tile is fixed-width, so this column gets ALL the remaining
            // width, which lets the street name wrap instead of truncating.
            VStack(alignment: .leading, spacing: 2) {
                if let status { statusLine(status) }
                if !distance.isEmpty {
                    Text(distance)
                        .dsText(isLandscape ? .hudEta : .hudTurnDistance)
                        .foregroundStyle(DS.Accent.base)
                        .lineLimit(1)
                }
                // Two lines rather than one: a truncated road name is worth less than a wrapped one.
                Text(instruction ?? String(localized: "Follow route"))
                    .dsText(isLandscape ? .bodyStrong : .hudTurnInstruction)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let thenSystemImage {
                    HStack(spacing: 4) {
                        Text("Then").dsText(.bodySmall)
                        Image(systemName: thenSystemImage).dsIcon(DS.IconSize.sm, weight: .bold)
                    }
                    .foregroundStyle(DS.Text.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Then \(thenSpoken ?? String(localized: "continue"))"))
                }
            }
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(border, lineWidth: DS.BorderWidth.default))
        .dsShadow(DS.Shadow.floating)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bottom bar

/// One stat written directly on the bar (no card). Labels sit on glass over the map, so they use
/// `secondary`, not `muted`.
struct DSBarStat: View {
    let label: LocalizedStringKey
    let value: String?
    var unit: String? = nil
    /// Third line under the value ("42m left").
    var sub: String? = nil
    /// Replaces the value in the VoiceOver reading (a clock time spoken in words).
    var spoken: String? = nil
    var valueStyle: DSTextStyle = .hudStatValue
    /// Rigid stats never shrink, so `ViewThatFits` can reject a layout that is too wide.
    var rigid = false

    var body: some View {
        let shown = value ?? "--"
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsText(.hudStatLabel).foregroundStyle(DS.Text.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(shown).dsText(valueStyle).foregroundStyle(DS.Text.primary).lineLimit(1)
                if let unit { Text(unit).dsText(.hudStatLabel).foregroundStyle(DS.Text.secondary).lineLimit(1) }
            }
            if let sub { Text(sub).dsText(.micro).foregroundStyle(DS.Text.secondary).lineLimit(1).monospacedDigit() }
        }
        .fixedSize(horizontal: rigid, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken.map { s in sub.map { "\(s), \($0)" } ?? s }
                                 ?? (unit.map { "\(shown) \($0)" } ?? shown)))
    }
}

struct DSBarDivider: View {
    var height: CGFloat = 30
    var body: some View {
        Rectangle().fill(DS.Border.divider).frame(width: DS.BorderWidth.hairline, height: height)
    }
}

/// Speed, arrival and distance side by side. `showUnits: false` drops the unit and the AM/PM
/// period (the first things to go on narrow layouts).
struct DSNavStats: View {
    let speed: String?
    let arrival: String?
    var arrivalPeriod: String? = nil
    var arrivalSub: String? = nil
    var arrivalSpoken: String? = nil
    let distance: String?
    var spacing: CGFloat = 16
    var showUnits = true
    var isLandscape = false

    var body: some View {
        let style: DSTextStyle = isLandscape ? .hudEta : .hudStatValue
        HStack(spacing: spacing) {
            DSBarStat(label: "SPEED", value: speed, unit: showUnits ? "KM/H" : nil, valueStyle: style)
            DSBarDivider(height: isLandscape ? 26 : 30)
            DSBarStat(label: "ARRIVAL", value: arrival, unit: showUnits ? arrivalPeriod : nil,
                      sub: arrivalSub, spoken: arrivalSpoken, valueStyle: style)
            DSBarDivider(height: isLandscape ? 26 : 30)
            DSBarStat(label: "DIST", value: distance, unit: showUnits ? "KM" : nil, valueStyle: style)
        }
    }
}

/// The portrait control row: stats, then the action buttons. Adaptive by construction rather than
/// by tuned constants: `ViewThatFits` measures each variant against the width SwiftUI actually
/// proposes (any device, orientation, split-screen or Dynamic Type) and picks the first that fits,
/// shedding spacing, then unit labels, in that order. The glass backdrop and anything above the
/// row (the convoy strip) belong to the caller.
struct DSNavBottomBar<Buttons: View>: View {
    let speed: String?
    let arrival: String?
    var arrivalPeriod: String? = nil
    var arrivalSub: String? = nil
    var arrivalSpoken: String? = nil
    let distance: String?
    var isLandscape = false
    @ViewBuilder var buttons: Buttons

    private func row(spacing: CGFloat, showUnits: Bool) -> some View {
        HStack(spacing: spacing) {
            DSNavStats(speed: speed, arrival: arrival, arrivalPeriod: arrivalPeriod, arrivalSub: arrivalSub,
                       arrivalSpoken: arrivalSpoken, distance: distance, spacing: spacing,
                       showUnits: showUnits, isLandscape: isLandscape)
            Spacer(minLength: 6)   // keeps the ideal width measurable for ViewThatFits
            buttons
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(spacing: 16, showUnits: true)
            row(spacing: 10, showUnits: true)
            row(spacing: 8, showUnits: false)
        }
    }
}

// MARK: - Banners

/// One frame for every banner in the alert slot. Glass, except `.emergency`, which is an opaque
/// danger surface so it reads as the most urgent thing on the screen.
struct DSBanner<Actions: View, Trailing: View>: View {
    enum Tone { case regroup, emergency, complete }

    let tone: Tone
    let eyebrow: LocalizedStringKey
    let message: String
    var detail: String? = nil
    /// Overrides the tone's symbol / colour (a regroup takes its colour from the stop type).
    var icon: String? = nil
    var tint: Color? = nil
    /// Spoken on appear instead of `message`.
    var announcement: String? = nil
    /// Full-width controls under the text.
    @ViewBuilder var actions: Actions
    /// Compact controls at the trailing edge of the text row.
    @ViewBuilder var trailing: Trailing
    @ScaledMetric(relativeTo: .body) private var disc: CGFloat = 36

    private var color: Color {
        tint ?? {
            switch tone {
            case .regroup: DS.Accent.base
            case .emergency: DS.Status.danger
            case .complete: DS.Status.success
            }
        }()
    }

    private var symbol: String {
        icon ?? {
            switch tone {
            case .regroup: "person.3.fill"
            case .emergency: "exclamationmark.triangle.fill"
            case .complete: "checkmark.circle.fill"
            }
        }()
    }

    private var border: Color {
        switch tone {
        case .regroup: color.opacity(0.5)
        case .emergency: DS.Status.danger
        case .complete: DS.Status.successBorder
        }
    }

    private var hasControls: Bool { Actions.self != EmptyView.self || Trailing.self != EmptyView.self }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            HStack(spacing: DS.Space.p3) {
                Image(systemName: symbol)
                    .dsIcon(DS.IconSize.md, weight: .semibold)
                    .foregroundStyle(color)
                    .frame(width: disc, height: disc)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow).dsText(.badge).foregroundStyle(color)
                    Text(message).dsText(.bodySmall).fontWeight(.semibold).foregroundStyle(DS.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(detail).dsText(.helper).foregroundStyle(DS.Text.secondary) }
                }
                Spacer(minLength: 0)
                trailing
            }
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, DS.Space.p3)
        .background {
            if tone == .emergency { shape.fill(DS.Surface.dangerContainer) } else { Color.clear.dsGlass(in: shape) }
        }
        .overlay(shape.stroke(border, lineWidth: DS.BorderWidth.emphasis))
        // Announced when it appears: emergency at high priority, the rest politely. Controls
        // inside keep their own accessibility elements.
        .accessibilityElement(children: hasControls ? .contain : .combine)
        .onAppear {
            var text = AttributedString(announcement ?? message)
            text.accessibilitySpeechAnnouncementPriority = tone == .emergency ? .high : .default
            AccessibilityNotification.Announcement(text).post()
            if tone == .emergency { DSHaptic.alert() }
        }
    }
}

extension DSBanner where Actions == EmptyView, Trailing == EmptyView {
    init(tone: Tone, eyebrow: LocalizedStringKey, message: String, detail: String? = nil,
         icon: String? = nil, tint: Color? = nil, announcement: String? = nil) {
        self.init(tone: tone, eyebrow: eyebrow, message: message, detail: detail, icon: icon, tint: tint,
                  announcement: announcement, actions: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension DSBanner where Trailing == EmptyView {
    init(tone: Tone, eyebrow: LocalizedStringKey, message: String, detail: String? = nil,
         icon: String? = nil, tint: Color? = nil, announcement: String? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.init(tone: tone, eyebrow: eyebrow, message: message, detail: detail, icon: icon, tint: tint,
                  announcement: announcement, actions: actions, trailing: { EmptyView() })
    }
}

extension DSBanner where Actions == EmptyView {
    init(tone: Tone, eyebrow: LocalizedStringKey, message: String, detail: String? = nil,
         icon: String? = nil, tint: Color? = nil, announcement: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(tone: tone, eyebrow: eyebrow, message: message, detail: detail, icon: icon, tint: tint,
                  announcement: announcement, actions: { EmptyView() }, trailing: trailing)
    }
}

/// Icon, colour and name of a regroup stop, from the backend's type string.
enum DSRegroupKind {
    static func icon(_ type: String) -> String {
        switch type {
        case "FUEL":   "fuelpump"
        case "FOOD":   "fork.knife"
        case "SCENIC": "camera"
        default:       "hand.raised.fill"
        }
    }

    static func label(_ type: String) -> String {
        switch type {
        case "FUEL":   String(localized: "Fuel stop")
        case "FOOD":   String(localized: "Food stop")
        case "SCENIC": String(localized: "Scenic stop")
        default:       String(localized: "Stop")
        }
    }

    static func color(_ type: String) -> Color {
        switch type {
        case "FUEL":   DS.Category.fuel
        case "FOOD":   DS.Category.food
        case "SCENIC": DS.Category.scenic
        default:       DS.Category.other
        }
    }
}

/// 48 pt icon button for a banner's trailing edge. `quiet` draws a small raised disc (dismiss).
struct DSBannerIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var tint: Color = DS.Status.danger
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if quiet {
                Image(systemName: systemImage)
                    .dsIcon(DS.IconSize.xs, weight: .bold)
                    .foregroundStyle(DS.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(DS.Surface.raised, in: Circle())
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: systemImage)
                    .dsIcon(DS.IconSize.sm, weight: .bold)
                    .foregroundStyle(tint)
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(Text(label))
    }
}

/// Large "Group split" alert: names the rider who fell behind and offers Regroup / Dismiss.
struct GroupSplitAlert: View {
    let riderName: String
    let gapMeters: Double
    let onIgnore: () -> Void
    let onRegroup: () -> Void

    /// Whole metres under a kilometre, tenths of a km above, rounded the way the turn banner is so
    /// the figure doesn't tick on every GPS fix.
    private var gapText: String {
        if gapMeters < 1000 { return "\(max(10, Int((gapMeters / 10).rounded()) * 10)) m" }
        return String(format: "%.1f km", gapMeters / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p4) {
            HStack(spacing: DS.Space.p3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .dsIcon(DS.IconSize.lg, weight: .semibold)
                    .foregroundStyle(DS.Surface.dangerContainer)
                    .frame(width: 44, height: 44)
                    .background(DS.Status.danger, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text("Group split")
                    .dsText(.titleLarge)
                    .foregroundStyle(DS.Status.danger)
                    .accessibilityAddTraits(.isHeader)
            }

            Text("**\(riderName)** is **\(gapText)** behind the leader.")
                .dsText(.body)
                .foregroundStyle(DS.Text.primary)

            // Regroup is the action; Dismiss is a quiet text button.
            DSAdaptiveStack(spacing: DS.Space.p3) {
                DSPillButton(title: "Regroup", systemImage: "person.3.fill", variant: .primary, large: true, action: onRegroup)
                DSTextButton(title: "Dismiss", role: .dismiss, action: onIgnore)
            }
        }
        .padding(DS.Space.p5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Status.dangerBorder, lineWidth: DS.BorderWidth.emphasis))
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Group split. \(riderName) is \(gapText) behind the leader")).post()
            DSHaptic.alert()
        }
    }
}

/// Single-line, centred "Reconnecting…" banner with a small progress indicator.
struct DSReconnectingBanner: View {
    var body: some View {
        HStack(spacing: DS.Space.p2) {
            ProgressView().controlSize(.small).tint(DS.Status.warning)
            Text("Reconnecting…").dsText(.badge).foregroundStyle(DS.Status.warning)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, DS.Space.p3)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Status.warning.opacity(0.4), lineWidth: DS.BorderWidth.emphasis))
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Reconnecting…")).post()
        }
    }
}

// MARK: - Pills

struct DSDestinationPill: View {
    let name: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin").dsIcon(DS.IconSize.sm, weight: .semibold).foregroundStyle(DS.Accent.base)
            Text(name).dsText(.bodyStrong).fontWeight(.medium).foregroundStyle(DS.Text.primary).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.right").dsIcon(DS.IconSize.xs, weight: .semibold).foregroundStyle(DS.Text.secondary) }
        }
        .padding(.horizontal, DS.Space.p3)
        .frame(minHeight: 30)
        .dsGlass(clear: true)
        .accessibilityElement(children: .combine)
    }
}

/// "RESUME" capsule. With no action it is a plain label, for use inside a card that is itself a button.
struct DSResumePill: View {
    var action: (() -> Void)? = nil

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill").dsIcon(DS.IconSize.sm)
            Text("Resume").dsText(.buttonPill).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(DS.Text.onAccent)
        .padding(.horizontal, DS.Space.p4)
        .frame(minHeight: 34)
        .background(DS.Accent.base, in: Capsule())
        .dsShadow(DS.Shadow.accentGlow)
    }

    var body: some View {
        if let action {
            Button {
                DSHaptic.primary()
                action()
            } label: {
                label.frame(minHeight: DS.Target.minimum).contentShape(Capsule())
            }
            .buttonStyle(DSPressStyle())
        } else {
            label.accessibilityHidden(true)
        }
    }
}

struct DSRegroupArrivalControl: View {
    var hasArrived: Bool
    var action: () -> Void

    var body: some View {
        if hasArrived {
            DSPillButton(title: "Waiting for others", systemImage: "clock", variant: .neutral, large: true) {}
                .disabled(true)
        } else {
            DSPillButton(title: "Mark as arrived", systemImage: "checkmark.circle.fill", variant: .primary, large: true, action: action)
        }
    }
}

// MARK: - Off-screen rider chip and leaderboard

/// Cardless edge indicator: avatar with a green ring and a distance underneath.
struct DSEdgeChip: View {
    let name: String
    let id: String
    let distance: String
    var isOffline = false
    var imageURL: URL? = nil

    var body: some View {
        VStack(spacing: 3) {
            DSAvatar(name: name, id: id, imageURL: imageURL, size: DS.AvatarSize.sm, highlightRing: DS.Map.edgeChipRing)
            Text(distance).dsText(.dataMono).foregroundStyle(DS.Text.primary).dsShadow(DS.Shadow.textOnPhoto)
        }
        .opacity(isOffline ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(distance) away"))
    }
}

/// One tappable card per rider in the convoy strip: avatar, first name and how far that rider is
/// ahead of (+) or behind (-) me. Opaque, not glass: it is a row of content on a glass bar.
struct DSLeaderboardCard: View {
    let name: String
    let id: String
    var imageURL: URL? = nil
    let rank: Int
    var isMe = false
    /// Metres this rider is ahead of (+) or behind (-) me. Nil for my own card.
    var gapMeters: Double? = nil
    var isSelected = false
    var isOffline = false
    var onTap: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHighlighted: Bool { rank == 1 || isSelected || isMe }
    private var firstName: String { name.components(separatedBy: " ").first ?? name }

    /// "+1.2 km" ahead, "-300 m" behind, "Level" within a few car lengths.
    private var gapText: String? {
        guard let gap = gapMeters else { return nil }
        let distance = abs(gap)
        if distance < 25 { return String(localized: "Level") }
        let formatted = distance < 1000
            ? "\(Int((distance / 10).rounded()) * 10) m"
            : String(format: "%.1f km", distance / 1000)
        return (gap > 0 ? "+" : "\u{2212}") + formatted
    }

    private var spokenGap: String? {
        guard let gap = gapMeters else { return nil }
        let distance = abs(gap)
        if distance < 25 { return String(localized: "level with you") }
        let spoken = NavVoiceGuide.spokenDistance(distance)
        return gap > 0 ? String(localized: "\(spoken) ahead") : String(localized: "\(spoken) behind")
    }

    var body: some View {
        // No rank number: the strip is already ordered by position. `rank` only drives the
        // leader highlight.
        Button {
            DSHaptic.selection()
            onTap()
        } label: {
            HStack(spacing: 7) {
                DSAvatar(
                    name: name, id: id, imageURL: imageURL,
                    size: DS.AvatarSize.stack,
                    isOnline: isOffline ? false : nil,   // grey dot = heartbeats lapsed
                    highlightRing: isHighlighted ? DS.Accent.base : nil
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(firstName)
                        .dsText(.navLabel)
                        .fontWeight(.bold)
                        .foregroundStyle(DS.Text.primary)
                        .lineLimit(1)
                    // The gap is the point of the card: where is this rider relative to me?
                    Text(isMe ? String(localized: "You") : (gapText ?? ""))
                        .dsText(.dataMono)
                        .foregroundStyle(isMe ? DS.Accent.base : DS.Text.secondary.base)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: DS.Target.hud)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isHighlighted ? DS.Accent.base : DS.Border.default.base, lineWidth: isHighlighted ? DS.BorderWidth.emphasis : DS.BorderWidth.default))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isOffline ? DS.Opacity.offline : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: isSelected)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isOffline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name)\(isMe ? ", you" : "")\(isOffline ? ", offline" : "")\(spokenGap.map { ", " + $0 } ?? "")"))
        .accessibilityHint(Text(isMe ? "Recentres the map on you" : "Shows rider on map"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

struct HUDGallery: View {
    var body: some View {
        ZStack {
            DS.Map.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.p3) {
                    DSTurnInstructionCard(systemImage: "arrow.turn.up.right", distance: "450 m", instruction: "Turn right onto Nandi Hills Rd",
                                          thenSystemImage: "arrow.turn.up.left", thenSpoken: "turn left")
                    DSTurnInstructionCard(systemImage: "arrow.turn.up.right", distance: "450 m", instruction: "Turn right onto Nandi Hills Rd", status: .offRoute)
                    DSTurnInstructionCard(systemImage: "arrow.up", distance: "", instruction: nil, status: .reconnecting, isLandscape: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            DSLeaderboardCard(name: "Asha", id: "a", rank: 1, isMe: true, isSelected: true)
                            DSLeaderboardCard(name: "Ravi", id: "b", rank: 2, gapMeters: -120)
                            DSLeaderboardCard(name: "Mia", id: "c", rank: 3, gapMeters: 1800, isOffline: true)
                        }
                    }
                    GroupSplitAlert(riderName: "Ravi", gapMeters: 2400, onIgnore: {}, onRegroup: {})
                    DSBanner(tone: .regroup, eyebrow: "Regroup called", message: "Head to the Fuel stop",
                             icon: DSRegroupKind.icon("FUEL"), tint: DSRegroupKind.color("FUEL"),
                             actions: {
                        DSAdaptiveStack(spacing: DS.Space.p2) {
                            DSPillButton(title: "Show", systemImage: "scope", variant: .tonal, large: true) {}
                            DSRegroupArrivalControl(hasArrived: false) {}
                        }
                    })
                    DSBanner(tone: .regroup, eyebrow: "Regroup called", message: "Head to the Food stop",
                             icon: DSRegroupKind.icon("FOOD"), tint: DSRegroupKind.color("FOOD"),
                             actions: {
                        DSAdaptiveStack(spacing: DS.Space.p2) {
                            DSPillButton(title: "Show", systemImage: "scope", variant: .tonal, large: true) {}
                            DSRegroupArrivalControl(hasArrived: true) {}
                        }
                    })
                    DSBanner(tone: .emergency, eyebrow: "Emergency", message: "Ravi needs help \u{2014} head to their location",
                             announcement: "Emergency. Ravi needs help",
                             trailing: {
                        DSBannerIconButton(systemImage: "scope", label: "Show emergency on map") {}
                        DSBannerIconButton(systemImage: "xmark", label: "Dismiss emergency", quiet: true) {}
                    })
                    DSBanner(tone: .complete, eyebrow: "Regroup complete", message: "Everyone arrived")
                    DSReconnectingBanner()
                    DSAdaptiveStack { DSDestinationPill(name: "Nandi Hills", showsChevron: true); DSResumePill() }
                    DSAdaptiveStack(spacing: 24) { DSEdgeChip(name: "Ravi", id: "b", distance: "1.2 km"); DSEdgeChip(name: "Mia", id: "c", distance: "3.4 km", isOffline: true) }
                    DSNavBottomBar(speed: "62", arrival: "10:42", arrivalPeriod: "AM", arrivalSub: "42m left", arrivalSpoken: "10:42 AM", distance: "18.4") {
                        DSSquareIconButton(systemImage: "person.3.fill", label: "Regroup", size: .hud, action: {})
                        DSSquareIconButton(systemImage: "stop.fill", label: "End ride", variant: .danger, size: .hud, action: {})
                    }
                    .padding(.horizontal, DS.Space.p5)
                    .padding(.vertical, DS.Space.p3)
                    .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                }
                .padding(DS.Space.screenInset)
                .dsHUDTypeSize()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("HUD") { HUDGallery() }
#Preview("HUD AX3") { HUDGallery().dynamicTypeSize(.accessibility3) }
