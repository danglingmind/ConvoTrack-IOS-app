import SwiftUI

// MARK: - Type scale
//
// One family: SF Pro for everything, with the Expanded width for display titles. SF Mono is
// kept only for invite and one-time codes, where 0/O must be unambiguous; live numbers use SF Pro
// with tabular digits. Every style scales with Dynamic Type through
// `@ScaledMetric(relativeTo:)`, keeps its tracking (halved at accessibility sizes) and applies
// its `.textCase`. Strings are stored in title or sentence case; uppercase is applied here.
//
// Colour is deliberately not part of a style: pass it with `.foregroundStyle(...)`.
//
//     Text("Ride history").dsText(.heroTitle)
//     Text(distance).dsText(.metricValue).monospacedDigit()

enum DSTextStyle {
    case heroTitle, heroTitleCompact, heroSubtitle
    case eyebrow, brandWordmark, headerTitle, headerSubtitle
    case sectionLabel, sectionAction, fieldLabel
    case titleLarge, cardTitle, rowTitle
    case body, bodyStrong, bodySmall, input, locationTitle, helper
    case button, buttonWide, buttonPill, link
    case statLabel, statValue, metricValue, metricDisplay
    case detailLabel, detailValue
    case dataMono, codeValue, codeDisplay, otpDisplay
    case badge, badgeSmall, metaTag, navLabel, micro
    case mapLabel
    case hudTurnDistance, hudTurnInstruction, hudStatValue, hudStatLabel, hudEta

    struct Spec {
        var size: CGFloat
        var weight: Font.Weight
        var design: Font.Design = .default
        var width: Font.Width = .standard
        var tracking: CGFloat = 0
        var uppercase = false
        var relativeTo: Font.TextStyle
        /// Fixed-height components shrink to this fraction instead of clipping.
        var minimumScale: CGFloat = 1
    }

    /// Sizes are the spec's, except badgeSmall / statLabel / hudStatLabel / micro, which are raised
    /// from 10 pt to 11 pt (iOS minimum; plan §1 issue 8).
    var spec: Spec {
        switch self {
        case .heroTitle:          Spec(size: 34, weight: .heavy, width: .expanded, tracking: -0.5, relativeTo: .largeTitle, minimumScale: 0.7)
        case .heroTitleCompact:   Spec(size: 28, weight: .heavy, width: .expanded, tracking: -0.4, relativeTo: .largeTitle, minimumScale: 0.7)
        case .heroSubtitle:       Spec(size: 15, weight: .regular, relativeTo: .body)
        case .eyebrow:            Spec(size: 12, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption)
        case .brandWordmark:      Spec(size: 40, weight: .heavy, tracking: 4, uppercase: true, relativeTo: .largeTitle, minimumScale: 0.6)
        case .headerTitle:        Spec(size: 15, weight: .semibold, tracking: 2.0, uppercase: true, relativeTo: .headline)
        case .headerSubtitle:     Spec(size: 13, weight: .regular, relativeTo: .footnote)
        case .sectionLabel:       Spec(size: 13, weight: .semibold, tracking: 2.0, uppercase: true, relativeTo: .subheadline)
        case .sectionAction:      Spec(size: 13, weight: .semibold, relativeTo: .caption)
        case .fieldLabel:         Spec(size: 12, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption)
        case .titleLarge:         Spec(size: 24, weight: .bold, relativeTo: .title)
        case .cardTitle:          Spec(size: 22, weight: .bold, relativeTo: .title2)
        case .rowTitle:           Spec(size: 16, weight: .semibold, relativeTo: .headline)
        case .body:               Spec(size: 15, weight: .regular, relativeTo: .body)
        case .bodyStrong:         Spec(size: 15, weight: .semibold, relativeTo: .body)
        case .bodySmall:          Spec(size: 13, weight: .regular, relativeTo: .footnote)
        case .input:              Spec(size: 18, weight: .medium, relativeTo: .body)
        case .locationTitle:      Spec(size: 16, weight: .medium, relativeTo: .body)
        case .helper:             Spec(size: 12, weight: .regular, relativeTo: .caption)
        case .button:             Spec(size: 17, weight: .bold, relativeTo: .headline)
        case .buttonWide:         Spec(size: 16, weight: .semibold, relativeTo: .headline)
        case .buttonPill:         Spec(size: 14, weight: .semibold, relativeTo: .subheadline)
        case .link:               Spec(size: 13, weight: .semibold, relativeTo: .footnote)
        case .statLabel:          Spec(size: 11, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption)
        case .statValue:          Spec(size: 18, weight: .semibold, relativeTo: .headline, minimumScale: 0.6)
        case .metricValue:        Spec(size: 24, weight: .semibold, relativeTo: .title2, minimumScale: 0.6)
        case .metricDisplay:      Spec(size: 44, weight: .bold, tracking: -0.8, relativeTo: .largeTitle, minimumScale: 26.0 / 44.0)
        case .detailLabel:        Spec(size: 14, weight: .regular, relativeTo: .subheadline)
        case .detailValue:        Spec(size: 15, weight: .medium, relativeTo: .body)
        case .dataMono:           Spec(size: 13, weight: .semibold, relativeTo: .footnote)
        case .codeValue:          Spec(size: 18, weight: .bold, design: .monospaced, tracking: 1.0, uppercase: true, relativeTo: .body)
        case .codeDisplay:        Spec(size: 30, weight: .bold, design: .monospaced, tracking: 6, uppercase: true, relativeTo: .title, minimumScale: 0.6)
        case .otpDisplay:         Spec(size: 26, weight: .bold, design: .monospaced, tracking: 10, relativeTo: .title2, minimumScale: 0.6)
        case .badge:              Spec(size: 12, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption)
        case .badgeSmall:         Spec(size: 11, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption2)
        case .metaTag:            Spec(size: 12, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption)
        case .navLabel:           Spec(size: 12, weight: .medium, relativeTo: .caption)
        case .micro:              Spec(size: 11, weight: .medium, relativeTo: .caption2)
        case .mapLabel:           Spec(size: 11, weight: .semibold, tracking: 1.5, uppercase: true, relativeTo: .caption2)
        case .hudTurnDistance:    Spec(size: 26, weight: .heavy, relativeTo: .title2, minimumScale: 0.6)
        case .hudTurnInstruction: Spec(size: 17, weight: .semibold, relativeTo: .headline)
        case .hudStatValue:       Spec(size: 24, weight: .heavy, relativeTo: .title2, minimumScale: 0.6)
        case .hudStatLabel:       Spec(size: 11, weight: .bold, tracking: 1.0, uppercase: true, relativeTo: .caption2)
        case .hudEta:             Spec(size: 22, weight: .heavy, relativeTo: .title3, minimumScale: 0.6)
        }
    }

    /// Live numbers use tabular digits so values update in place without jitter.
    var usesTabularDigits: Bool {
        switch self {
        case .statValue, .metricValue, .metricDisplay, .dataMono, .badge, .badgeSmall,
             .hudTurnDistance, .hudStatValue, .hudEta: true
        default: spec.design == .monospaced
        }
    }
}

/// Only applied when a style can actually shrink: `minimumScaleFactor(1)` still makes Text report
/// its full ideal width, which can widen a whole scroll view for a long single-line string.
private struct MinimumScale: ViewModifier {
    let factor: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if factor < 1 { content.minimumScaleFactor(factor) } else { content }
    }
}

private struct TabularDigits: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.monospacedDigit() } else { content }
    }
}

private struct DSTextModifier: ViewModifier {
    let style: DSTextStyle
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(style: DSTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.spec.size, relativeTo: style.spec.relativeTo)
    }

    func body(content: Content) -> some View {
        let spec = style.spec
        // Wide tracking at accessibility sizes makes labels wrap badly (plan §4.4).
        let tracking = dynamicTypeSize.isAccessibilitySize ? spec.tracking / 2 : spec.tracking
        content
            .font(.system(size: size, weight: spec.weight, design: spec.design).width(spec.width))
            .tracking(tracking)
            .textCase(spec.uppercase ? .uppercase : nil)
            .modifier(TabularDigits(enabled: style.usesTabularDigits))
            .modifier(MinimumScale(factor: spec.minimumScale))
    }
}

extension View {
    /// Applies a design-system text style: scaled font, tracking, case and tabular digits.
    func dsText(_ style: DSTextStyle) -> some View {
        modifier(DSTextModifier(style: style))
    }

    /// Caps the ride HUD at AX2 so the map stays visible (plan §4.5).
    func dsHUDTypeSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: - Icons

extension DS {
    /// Icon font for `Image(systemName:)`. Scales with Dynamic Type relative to the given style.
    struct IconFont: ViewModifier {
        @ScaledMetric private var size: CGFloat
        private let base: CGFloat
        let weight: Font.Weight

        init(size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) {
            _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
            self.base = size
            self.weight = weight
        }

        func body(content: Content) -> some View {
            // Capped at 1.5×: icons live in fixed-size buttons and discs, so unbounded scaling
            // at accessibility sizes spills out of them.
            content.font(.system(size: min(size, base * 1.5), weight: weight))
        }
    }
}

extension View {
    func dsIcon(_ size: CGFloat = DS.IconSize.default, weight: Font.Weight = .regular) -> some View {
        modifier(DS.IconFont(size: size, weight: weight))
    }
}
