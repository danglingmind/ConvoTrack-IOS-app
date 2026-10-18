import SwiftUI

// MARK: - SurfaceCard (content layer: opaque, never glass)

enum DSSurfaceKind {
    /// Stat tiles, settings groups, plan cards.
    case card
    /// Roster rows, ride rows, details list.
    case quiet
}

private struct DSSurfaceModifier: ViewModifier {
    let kind: DSSurfaceKind
    let radius: CGFloat
    var borderColor: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(kind == .card ? DS.Surface.card : DS.Surface.cardQuiet, in: shape)
            .overlay(shape.stroke(borderColor.map { AnyShapeStyle($0) }
                                    ?? AnyShapeStyle(kind == .card ? DS.Border.subtle : DS.Border.hairline),
                                  lineWidth: kind == .card ? DS.BorderWidth.default : DS.BorderWidth.hairline))
    }
}

extension View {
    /// Opaque content surface with a hairline. Cards stay opaque (Liquid Glass is for chrome only).
    func dsSurfaceCard(_ kind: DSSurfaceKind = .card, radius: CGFloat = DS.Radius.md, border: Color? = nil) -> some View {
        modifier(DSSurfaceModifier(kind: kind, radius: radius, borderColor: border))
    }
}

/// Icon in a 36–40 pt disc (metric cards, location cards, benefit tiles).
struct DSIconDisc: View {
    let systemImage: String
    var iconSize: CGFloat = DS.IconSize.md
    var fill: Color = DS.Surface.iconDisc
    var tint: Color = DS.Accent.base
    // The disc grows with the glyph so the icon never spills out at large text sizes.
    @ScaledMetric private var size: CGFloat

    init(systemImage: String, size: CGFloat = 36, iconSize: CGFloat = DS.IconSize.md,
         fill: Color = DS.Surface.iconDisc, tint: Color = DS.Accent.base) {
        self.systemImage = systemImage
        self.iconSize = iconSize
        self.fill = fill
        self.tint = tint
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(systemName: systemImage)
            .dsIcon(iconSize, weight: .medium)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Stat tiles

struct DSStatTile: View {
    enum Variant { case standard, status, code }

    let systemImage: String
    let label: LocalizedStringKey
    let value: String
    var variant: Variant = .standard
    /// Equal-width, equal-height columns (History, Profile) instead of widths that follow content.
    var fillsWidth = false
    /// Three-up strips are ~110 pt wide, so the icon is dropped there to leave the label room.
    var showsIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DS.Space.p2) {
                if showsIcon {
                    Image(systemName: systemImage)
                        .dsIcon(DS.IconSize.md)
                        .foregroundStyle(variant == .status ? DS.Status.success : DS.Text.secondary.base)
                }
                Text(label).dsText(.statLabel).foregroundStyle(DS.Text.muted).lineLimit(2)
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)   // values sit on one line across equal-height tiles
            Text(value)
                .dsText(variant == .code ? .codeValue : .statValue)
                .foregroundStyle(variant == .status ? DS.Status.success : DS.Text.primary.base)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 10)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 56, alignment: .topLeading)
        .frame(maxHeight: fillsWidth ? .infinity : nil, alignment: .topLeading)
        .dsSurfaceCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}

/// Small stat chip for map overlays: label, value and optional unit.
struct DSStatPill: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String? = nil
    var dot: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).dsText(.statLabel).foregroundStyle(DS.Text.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(value).dsText(.metricValue).foregroundStyle(DS.Text.primary).lineLimit(1)
                if let unit { Text(unit).dsText(.helper).foregroundStyle(DS.Text.muted) }
            }
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 10)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous), clear: true)
        .accessibilityElement(children: .combine)
    }
}

struct DSMetricCard: View {
    let systemImage: String
    let label: LocalizedStringKey
    let value: String?

    var body: some View {
        HStack(spacing: DS.Space.p3) {
            DSIconDisc(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).dsText(.statLabel).foregroundStyle(DS.Text.muted)
                Text(value ?? "--").dsText(.metricValue).foregroundStyle(DS.Text.primary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 48)
        .dsSurfaceCard()
        .accessibilityElement(children: .combine)
    }
}

/// Fixed-height summary metric. The value shrinks (never below 26 pt) instead of clipping.
struct DSSummaryMetricCard: View {
    enum Variant { case standard, primary, alert }

    let label: LocalizedStringKey
    let value: String
    var unit: String? = nil
    var variant: Variant = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).dsText(.statLabel).foregroundStyle(DS.Text.muted)
                Spacer(minLength: 0)
                if variant == .alert {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsIcon(DS.IconSize.sm)
                        .foregroundStyle(DS.Status.danger)
                        .accessibilityLabel(Text("Warning"))
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .dsText(.metricDisplay)
                    .foregroundStyle(variant == .primary ? DS.Accent.base : variant == .alert ? DS.Status.danger : DS.Text.primary.base)
                    .lineLimit(1)
                if let unit { Text(unit).dsText(.statLabel).foregroundStyle(DS.Text.muted) }
            }
        }
        .padding(DS.Space.p4)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .dsSurfaceCard(.card, radius: DS.Radius.lg,
                       border: variant == .primary ? DS.Accent.border : variant == .alert ? DS.Status.dangerBorder : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.map { "\(value) \($0)" } ?? value))
    }
}

// MARK: - Ride rows

/// Recent / history row. `thumbnail` is the destination photo (or a route snapshot).
struct DSRideRowCard<Thumbnail: View>: View {
    let title: String
    let distance: String
    let detail: String
    var isLeader = false
    var inProgress = false
    @ViewBuilder var thumbnail: Thumbnail
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func facts(showsIcon: Bool) -> some View {
        // Side by side normally; stacked at accessibility sizes, where a rigid "5.6 KM LEADER"
        // line is wider than the screen and would widen the whole page.
        DSAdaptiveStack(spacing: 8, verticalAlignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showsIcon {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .dsIcon(DS.IconSize.xs).foregroundStyle(DS.Text.muted)
                }
                Text(distance).dsText(.dataMono).foregroundStyle(DS.Text.secondary).lineLimit(1)
            }
            if isLeader { DSLeaderBadge() }
        }
    }

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: 12) {
            if !large {
                thumbnail
                    .frame(width: 75, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                // Title gets the whole text column.
                Text(title).dsText(.rowTitle).foregroundStyle(DS.Text.primary).lineLimit(large ? 3 : 2)
                // Facts on the left, the one action (RESUME) on the right. LEADER is an outlined
                // tag and RESUME the only filled element, so the call to action is unambiguous.
                if large {
                    VStack(alignment: .leading, spacing: 6) {
                        facts(showsIcon: true)
                        if inProgress { DSTonalPill(title: "Resume").fixedSize() }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            facts(showsIcon: true)
                            Spacer(minLength: 0)
                            if inProgress { DSTonalPill(title: "Resume").fixedSize() }
                        }
                        HStack(alignment: .center, spacing: 8) {
                            facts(showsIcon: false)
                            Spacer(minLength: 0)
                            if inProgress { DSTonalPill(title: "Resume").fixedSize() }
                        }
                    }
                }
                if !detail.isEmpty {
                    Text(detail).dsText(.bodySmall).foregroundStyle(DS.Text.muted).lineLimit(large ? 3 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // keeps the chevron on the trailing edge
            Image(systemName: "chevron.right").dsIcon(DS.IconSize.sm, weight: .semibold).foregroundStyle(DS.Text.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .dsSurfaceCard(.quiet)
        .accessibilityElement(children: .combine)
    }
}

/// Active-ride card on a destination photo. Content layer: opaque scrim, no glass.
struct DSActiveRideCard<Photo: View>: View {
    let title: String
    var destination: String? = nil
    var distance: String? = nil
    var time: String? = nil
    var riders: [DSAvatarStack.Item] = []
    /// Google Places requires the photographer credit wherever a Place photo shows.
    var attribution: String? = nil
    /// nil renders a non-interactive pill, for when the whole card is already a button.
    var onResume: (() -> Void)? = nil
    @ViewBuilder var photo: Photo

    private var chips: some View {
        DSAdaptiveStack(spacing: 6) {
            if let distance { DSMetaChip(systemImage: "point.topleft.down.to.point.bottomright.curvepath", text: distance) }
            if let time { DSMetaChip(systemImage: "clock", text: time) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: destination (flexible) and riders.
            HStack(alignment: .top, spacing: DS.Space.p2) {
                if let destination { DSDestinationPill(name: destination) }
                Spacer(minLength: 0)
                if !riders.isEmpty { DSAvatarStack(items: riders) }
            }
            Spacer(minLength: DS.Space.p3)
            // Title, then chips with RESUME on the same row. If they can't share a row (long
            // localisation, large text), RESUME drops under the chips instead of crushing them.
            Text(title)
                .dsText(.cardTitle)
                .foregroundStyle(DS.Text.onPhoto)
                .lineLimit(2)
                .dsShadow(DS.Shadow.textOnPhoto)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: DS.Space.p2) {
                    chips
                    Spacer(minLength: 0)
                    DSResumePill(action: onResume)
                }
                VStack(alignment: .leading, spacing: DS.Space.p2) {
                    chips
                    DSResumePill(action: onResume)
                }
            }
            .padding(.top, DS.Space.p2)
            if let attribution {
                Text("Photo: \(attribution) · Google")
                    .dsText(.micro)
                    .foregroundStyle(DS.Text.onPhotoMuted)
                    .dsShadow(DS.Shadow.textOnPhoto)
                    .lineLimit(1)
                    .padding(.top, DS.Space.p2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background {
            // Opaque photo + scrim: the card is content, not chrome.
            ZStack {
                photo.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                DS.Gradient.cardPhotoScrim
            }
            // A scaledToFill photo overflows its card; clipping doesn't shrink its hit area, so
            // without this it swallows taps on whatever sits above the card.
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Roster

struct DSRosterRow: View {
    let name: String
    let id: String
    var imageURL: URL? = nil
    var isMe = false
    var isLeader = false
    var isOnline = true
    let badge: DSStatusBadge.Kind
    /// The leader can open a rider to remove them.
    var showsChevron = false

    var body: some View {
        HStack(spacing: DS.Space.p3) {
            DSAvatar(name: name, id: id, imageURL: imageURL, size: isLeader ? DS.AvatarSize.lg : DS.AvatarSize.md, isOnline: isOnline)
            DSAdaptiveStack(spacing: DS.Space.p2) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isMe ? "\(name) (You)" : name).dsText(.rowTitle).foregroundStyle(DS.Text.primary).lineLimit(2)
                    Text(isLeader ? "Ride leader" : "Formation rider")
                        .dsText(.badgeSmall)
                        .foregroundStyle(isLeader ? DS.Accent.base : DS.Text.muted.base)
                }
                Spacer(minLength: DS.Space.p2)
                DSStatusBadge(kind: badge)
            }
            if showsChevron {
                Image(systemName: "chevron.right").dsIcon(DS.IconSize.sm, weight: .semibold).foregroundStyle(DS.Text.muted)
            }
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, DS.Space.p2)
        .frame(minHeight: 56)
        .background(alignment: .leading) {
            if isLeader { Rectangle().fill(DS.Accent.base).frame(width: 3) }
        }
        .background(isLeader ? DS.Surface.leaderRow : .clear)
        .dsSurfaceCard(.quiet, border: isLeader ? DS.Border.leaderRow : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(isLeader ? "Ride leader" : "Formation rider"), \(badgeWord)"))
    }

    private var badgeWord: String {
        switch badge {
        case .ready: String(localized: "Ready")
        case .waiting: String(localized: "Waiting")
        case .riding: String(localized: "Riding")
        }
    }
}

struct DSAwardRow: View {
    let name: String
    let id: String
    let awardTitle: String
    let score: String
    var imageURL: URL? = nil

    var body: some View {
        HStack(spacing: DS.Space.p3) {
            DSAvatar(name: name, id: id, imageURL: imageURL, size: DS.AvatarSize.md, highlightRing: DS.Accent.border)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).dsText(.bodyStrong).foregroundStyle(DS.Text.primary)
                Text(awardTitle).dsText(.badge).foregroundStyle(DS.Accent.base)
            }
            Spacer(minLength: DS.Space.p2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(score).dsText(.metricValue).foregroundStyle(DS.Status.success)
                Text("Sync").dsText(.badge).foregroundStyle(DS.Text.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Regroup reason tile

enum DSRegroupReason: CaseIterable {
    case fuel, food, scenic, emergency

    var title: LocalizedStringKey {
        switch self {
        case .fuel: "Fuel stop"
        case .food: "Food stop"
        case .scenic: "Scenic stop"
        case .emergency: "Emergency"
        }
    }
    var systemImage: String {
        switch self {
        case .fuel: "fuelpump"
        case .food: "fork.knife"
        case .scenic: "camera"
        case .emergency: "exclamationmark.triangle.fill"
        }
    }
    var color: Color {
        switch self {
        case .fuel: DS.Category.fuel
        case .food: DS.Category.food
        case .scenic: DS.Category.scenic
        case .emergency: DS.Category.emergency
        }
    }
}

/// Tiles fire immediately, so there's no confirm. Emergency uses a danger fill plus icon and word.
struct DSReasonTile: View {
    let reason: DSRegroupReason
    var action: () -> Void

    var body: some View {
        Button {
            reason == .emergency ? DSHaptic.alert() : DSHaptic.primary()
            action()
        } label: {
            VStack(spacing: DS.Space.p3) {
                Image(systemName: reason.systemImage)
                    .dsIcon(26, weight: .semibold)
                    .foregroundStyle(reason.color)
                    .frame(width: 48, height: 48)
                    .background(reason.color.opacity(0.14), in: Circle())
                Text(reason.title).dsText(.buttonPill).foregroundStyle(DS.Text.primary).multilineTextAlignment(.center)
            }
            .padding(DS.Space.p5)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(reason == .emergency ? DS.Status.dangerTint : DS.Surface.card.base,
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(reason == .emergency ? DS.Status.dangerBorder : DS.Border.subtle.base, lineWidth: DS.BorderWidth.default))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle(scale: 0.97))
    }
}

// MARK: - Settings

struct DSSettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .dsSurfaceCard(.card, radius: DS.Radius.lg)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

struct DSSettingsRow: View {
    enum Trailing { case chevron, externalLink, none }

    let systemImage: String
    let title: LocalizedStringKey
    var trailing: Trailing = .chevron
    var isDestructive = false
    var showsDivider = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: DS.Space.p4) {
                    Image(systemName: systemImage)
                        .dsIcon(DS.IconSize.md)
                        .foregroundStyle(isDestructive ? DS.Status.danger : DS.Text.secondary.base)
                        .frame(width: DS.IconSize.lg)
                        .accessibilityHidden(true)
                    Text(title).dsText(.body).foregroundStyle(isDestructive ? DS.Status.danger : DS.Text.primary.base)
                    Spacer(minLength: DS.Space.p2)
                    switch trailing {
                    case .chevron: Image(systemName: "chevron.right").dsIcon(DS.IconSize.sm, weight: .semibold).foregroundStyle(DS.Text.subtle)
                    case .externalLink: Image(systemName: "arrow.up.right").dsIcon(DS.IconSize.sm, weight: .semibold).foregroundStyle(DS.Text.subtle)
                    case .none: EmptyView()
                    }
                }
                .padding(.horizontal, DS.Space.p4)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                if showsDivider { DSDivider().padding(.leading, 52) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Promo / benefit / plan

struct DSPromoBanner: View {
    let eyebrow: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var isSubscribed = false
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        DSAdaptiveStack(spacing: DS.Space.p3) {
            DSIconDisc(systemImage: "rosette", size: 40, iconSize: DS.IconSize.lg, fill: DS.Accent.tonal)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).dsText(.fieldLabel).foregroundStyle(DS.Accent.base).lineLimit(1).minimumScaleFactor(0.75)
                Text(message).dsText(.bodySmall).foregroundStyle(DS.Text.primary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            DSPillButton(title: actionTitle, variant: isSubscribed ? .tonal : .primary, action: action)
        }
        .padding(DS.Space.p4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Accent.tint, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(DS.Accent.border, lineWidth: DS.BorderWidth.default))
    }
}

struct DSBenefitTile: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSIconDisc(systemImage: systemImage, iconSize: 18, fill: DS.Accent.tint)
            Text(title).dsText(.fieldLabel).foregroundStyle(DS.Text.primary)
            Text(detail).dsText(.helper).foregroundStyle(DS.Text.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurfaceCard(.card, radius: DS.Radius.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Radio-style plan row. Prices come from the store (`Product.displayPrice`); never a placeholder.
struct DSPlanCard: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let price: String
    var perPeriod: String? = nil
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.p3) {
                ZStack {
                    Circle().stroke(isSelected ? DS.Accent.base : DS.Border.strong.base,
                                    lineWidth: isSelected ? DS.BorderWidth.focus : DS.BorderWidth.emphasis)
                    if isSelected { Circle().fill(DS.Accent.base).frame(width: 11, height: 11) }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).dsText(.fieldLabel).foregroundStyle(isSelected ? DS.Text.primary.base : DS.Text.secondary.base)
                    if let subtitle { Text(subtitle).dsText(.helper).foregroundStyle(DS.Text.muted) }
                }
                Spacer(minLength: DS.Space.p2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price).dsText(.metricValue).foregroundStyle(DS.Text.primary).lineLimit(1)
                    if let perPeriod { Text(perPeriod).dsText(.helper).foregroundStyle(DS.Text.muted) }
                }
            }
            .padding(18)
            .dsSurfaceCard(.card, radius: DS.Radius.lg, border: isSelected ? DS.Accent.border : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - DetailsList

struct DSDetailRow: Identifiable {
    let id = UUID()
    let systemImage: String
    let label: LocalizedStringKey
    let value: String
    var isMono = false
    /// Lets the caller attach a trailing control to specific rows.
    var tag: String? = nil
}

struct DSDetailsList<Trailing: View>: View {
    let rows: [DSDetailRow]
    /// Optional trailing control per row (maps button, copy button).
    @ViewBuilder var trailing: (DSDetailRow) -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.p3) {
                    Image(systemName: row.systemImage).dsIcon(DS.IconSize.md).foregroundStyle(DS.Text.secondary).frame(width: 20)
                    Text(row.label).dsText(.detailLabel).foregroundStyle(DS.Text.muted).frame(width: 108, alignment: .leading)
                    Text(row.value).dsText(row.isMono ? .codeValue : .detailValue).foregroundStyle(DS.Text.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.p2)
                    trailing(row)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .accessibilityElement(children: .contain)
                if index < rows.count - 1 { DSDivider().padding(.leading, 44) }
            }
        }
        .dsSurfaceCard(.quiet)
    }
}

extension DSDetailsList where Trailing == EmptyView {
    init(rows: [DSDetailRow]) {
        self.rows = rows
        self.trailing = { _ in EmptyView() }
    }
}

// MARK: - Preview

struct CardsGallery: View {
    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.p4) {
                    DSActiveRideCard(title: "Nandi Hills sunrise", destination: "Amazon Development Centre, Taurus Block, Bengaluru", distance: "62 km", time: "1h 20m",
                                     riders: [.init(id: "a", name: "A"), .init(id: "b", name: "B"), .init(id: "c", name: "C")], onResume: {}) {
                        Image("hero_road_sunset").resizable().scaledToFill()
                    }
                    DSRideRowCard(title: "Office run", distance: "5.6 km", detail: "Oct 6, 2026 · 2h 14m", isLeader: true, inProgress: true) {
                        Image("hero_road_sunset").resizable().scaledToFill()
                    }
                    DSAdaptiveStack(verticalAlignment: .top) { DSStatTile(systemImage: "key", label: "Code", value: "A1B2C3", variant: .code); DSStatTile(systemImage: "person.3", label: "Riders", value: "3/5") }
                    DSMetricCard(systemImage: "clock", label: "Est. time", value: "1h 12m")
                    DSAdaptiveStack {
                        DSSummaryMetricCard(label: "Total distance", value: "51.7", unit: "km", variant: .primary)
                        DSSummaryMetricCard(label: "Max group split", value: "2.4", unit: "km", variant: .alert)
                    }
                    DSRosterRow(name: "Asha", id: "u1", isMe: true, isLeader: true, badge: .ready)
                    DSRosterRow(name: "Ravi", id: "u2", badge: .waiting, showsChevron: true)
                    DSAwardRow(name: "Asha", id: "u1", awardTitle: "Road captain", score: "98")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(DSRegroupReason.allCases, id: \.self) { DSReasonTile(reason: $0) {} }
                    }
                    DSSettingsGroup {
                        DSSettingsRow(systemImage: "bell", title: "Notifications", trailing: .externalLink) {}
                        DSSettingsRow(systemImage: "hand.raised", title: "Privacy policy", trailing: .externalLink, showsDivider: false) {}
                    }
                    DSSettingsGroup {
                        DSSettingsRow(systemImage: "trash", title: "Delete account", trailing: .none, isDestructive: true, showsDivider: false) {}
                    }
                    DSPromoBanner(eyebrow: "ConvoTrack Pro", message: "Bigger packs · Unlimited rides", actionTitle: "Upgrade") {}
                    DSAdaptiveStack(verticalAlignment: .top) { DSBenefitTile(systemImage: "person.3", title: "25 riders", detail: "Bigger packs"); DSBenefitTile(systemImage: "infinity", title: "Unlimited", detail: "No ride cap") }
                    DSPlanCard(title: "Yearly", subtitle: "Best value", price: "$39.99", perPeriod: "per year", isSelected: true) {}
                    DSPlanCard(title: "Monthly", price: "$4.99", perPeriod: "per month", isSelected: false) {}
                    DSDetailsList(rows: [
                        .init(systemImage: "location.north.fill", label: "Start point", value: "Indiranagar"),
                        .init(systemImage: "key", label: "Joining code", value: "A1B2C3", isMono: true),
                    ])
                }
                .padding(DS.Space.screenInset)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Cards") { CardsGallery() }
#Preview("Cards AX3") { CardsGallery().dynamicTypeSize(.accessibility3) }
