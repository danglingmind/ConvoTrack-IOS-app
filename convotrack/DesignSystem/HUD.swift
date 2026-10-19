import SwiftUI

// Navigation HUD components. Glass sits on the functional layer only (turn card, leaderboard,
// bottom bar, pills). The map is content. Apply `.dsHUDTypeSize()` on the HUD container so text
// is capped at AX2, and keep targets at 48 pt or more.

// MARK: - Turn instruction

struct DSTurnInstructionCard: View {
    let systemImage: String
    let distance: String
    var instruction: String? = nil
    var isLandscape = false
    @ScaledMetric(relativeTo: .title2) private var portraitTile: CGFloat = 56
    @ScaledMetric(relativeTo: .title2) private var landscapeTile: CGFloat = 48

    var body: some View {
        let tile = isLandscape ? landscapeTile : portraitTile
        HStack(spacing: DS.Space.p3) {
            Image(systemName: systemImage)
                .dsIcon(isLandscape ? 24 : 28, weight: .bold)
                .foregroundStyle(DS.Text.onAccent)
                .frame(width: tile, height: tile)
                .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(distance).dsText(.hudTurnDistance).foregroundStyle(DS.Accent.base)
                Text(instruction ?? String(localized: "Follow route"))
                    .dsText(.hudTurnInstruction).foregroundStyle(DS.Text.primary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 10)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(DS.Accent.border, lineWidth: DS.BorderWidth.default))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bottom bar

struct DSBarStat: View {
    let label: LocalizedStringKey
    let value: String?
    var unit: String? = nil
    /// Rigid stats never shrink, so `ViewThatFits` can reject a layout that is too wide.
    var rigid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dsText(.hudStatLabel).foregroundStyle(DS.Text.muted).lineLimit(1).minimumScaleFactor(rigid ? 1 : 0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "--").dsText(.hudStatValue).foregroundStyle(DS.Text.primary).lineLimit(1)
                if let unit { Text(unit).dsText(.hudStatLabel).foregroundStyle(DS.Text.muted).lineLimit(1) }
            }
        }
        .fixedSize(horizontal: rigid, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(unit.map { "\(value ?? "--") \($0)" } ?? (value ?? "--")))
    }
}

struct DSNavBottomBar: View {
    let speed: String?
    let eta: String?
    let distance: String?
    var isLandscape = false
    var onRegroup: () -> Void
    var onEnd: () -> Void

    private var divider: some View {
        Rectangle().fill(DS.Border.divider).frame(width: DS.BorderWidth.hairline, height: 28)
    }

    private func buttons(_ size: DSSquareIconButton.Size) -> some View {
        HStack(spacing: DS.Space.p2) {
            DSSquareIconButton(systemImage: "person.3.fill", label: "Regroup", size: size, action: onRegroup)
            DSSquareIconButton(systemImage: "stop.fill", label: "End ride", variant: .danger, size: size, action: onEnd)
        }
    }

    var body: some View {
        // Units sit beside the values only when there's room (spec: from 430 pt wide). Otherwise
        // they move into the labels, and on the narrowest layouts the digits shrink, never clip.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.p3) {
                DSBarStat(label: "Speed", value: speed, unit: "km/h")
                divider
                DSBarStat(label: "ETA", value: eta)
                divider
                DSBarStat(label: "Dist", value: distance, unit: "km")
                Spacer(minLength: 0)
                buttons(isLandscape ? .hudLandscape : .hud)
            }
            .padding(.horizontal, DS.Space.p5)
            HStack(spacing: DS.Space.p2) {
                DSBarStat(label: "Speed (km/h)", value: speed)
                divider
                DSBarStat(label: "ETA", value: eta)
                divider
                DSBarStat(label: "Dist (km)", value: distance)
                Spacer(minLength: 0)
                buttons(isLandscape ? .hudLandscape : .hud)
            }
            .padding(.horizontal, DS.Space.p5)
            HStack(spacing: DS.Space.p2) {
                // At 402 pt there's no room for "SPEED (KM/H)" at 11 pt, so the unit is the label.
                DSBarStat(label: "km/h", value: speed, rigid: false)
                divider
                DSBarStat(label: "ETA", value: eta, rigid: false)
                divider
                DSBarStat(label: "km", value: distance, rigid: false)
                buttons(.hudLandscape)   // 48 pt is still the HUD minimum
            }
            .padding(.horizontal, DS.Space.p3)
        }
        .padding(.vertical, DS.Space.p3)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}

// MARK: - Banners

struct DSBanner: View {
    enum Tone { case connection, regroup, split, emergency, complete }

    let tone: Tone
    let eyebrow: LocalizedStringKey
    let message: String
    var detail: String? = nil
    @ScaledMetric(relativeTo: .body) private var disc: CGFloat = 36

    private var color: Color {
        switch tone {
        case .connection, .split: DS.Status.warning
        case .regroup: DS.Accent.base
        case .emergency: DS.Status.danger
        case .complete: DS.Status.success
        }
    }

    private var icon: String {
        switch tone {
        case .connection: "wifi.exclamationmark"
        case .regroup: "person.3.fill"
        case .split: "arrow.left.and.right"
        case .emergency: "exclamationmark.triangle.fill"
        case .complete: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.p3) {
            Image(systemName: icon)
                .dsIcon(DS.IconSize.md, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: disc, height: disc)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).dsText(.badge).foregroundStyle(color)
                Text(message).dsText(.bodySmall).fontWeight(.semibold).foregroundStyle(DS.Text.primary)
                if let detail { Text(detail).dsText(.helper).foregroundStyle(DS.Text.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, DS.Space.p3)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(color.opacity(0.4), lineWidth: DS.BorderWidth.emphasis))
        // Announced when it appears: emergency at high priority, the rest politely.
        .accessibilityElement(children: .combine)
        .onAppear {
            var text = AttributedString("\(message)")
            text.accessibilitySpeechAnnouncementPriority = tone == .emergency ? .high : .default
            AccessibilityNotification.Announcement(text).post()
            if tone == .emergency || tone == .split { DSHaptic.alert() }
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

struct DSLeaderboardCard: View {
    let rank: Int
    let name: String
    let id: String
    let gap: String
    var isMe = false
    var isSelected = false

    var body: some View {
        HStack(spacing: DS.Space.p2) {
            Text("\(rank)").dsText(.badge).foregroundStyle(DS.Text.muted)
            DSAvatar(name: name, id: id, size: DS.AvatarSize.stack)
            VStack(alignment: .leading, spacing: 0) {
                Text(isMe ? String(localized: "You") : name).dsText(.rowTitle).foregroundStyle(DS.Text.primary).lineLimit(1)
                Text(gap).dsText(.dataMono).foregroundStyle(DS.Text.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: DS.Target.hud)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous), interactive: true)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .stroke(isSelected ? DS.Accent.border : .clear, lineWidth: DS.BorderWidth.default))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

struct HUDGallery: View {
    var body: some View {
        ZStack {
            DS.Map.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.p3) {
                    DSTurnInstructionCard(systemImage: "arrow.turn.up.right", distance: "450 m", instruction: "Turn right onto Nandi Hills Rd")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            DSLeaderboardCard(rank: 1, name: "Asha", id: "a", gap: "Leading", isMe: true, isSelected: true)
                            DSLeaderboardCard(rank: 2, name: "Ravi", id: "b", gap: "-120 m")
                        }
                    }
                    DSBanner(tone: .regroup, eyebrow: "Regroup called", message: "Fuel stop in 500 m", detail: "Called by Asha")
                    DSBanner(tone: .emergency, eyebrow: "Emergency", message: "Ravi needs help")
                    DSAdaptiveStack { DSDestinationPill(name: "Nandi Hills", showsChevron: true); DSResumePill() }
                    DSAdaptiveStack(spacing: 24) { DSEdgeChip(name: "Ravi", id: "b", distance: "1.2 km"); DSEdgeChip(name: "Mia", id: "c", distance: "3.4 km", isOffline: true) }
                    DSRegroupArrivalControl(hasArrived: false) {}
                    DSNavBottomBar(speed: "62", eta: "10:42", distance: "18.4") {} onEnd: {}
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
