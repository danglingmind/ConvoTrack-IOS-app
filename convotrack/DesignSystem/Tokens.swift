import SwiftUI

// MARK: - Design tokens
//
// Source: convotrack-android/design/convotrack_design_system.json (spec v2.4.0), adapted per
// design/IOS_REDESIGN_PLAN.md. Screens read everything from `DS`; they never use raw hex, raw font
// sizes or raw corner radii.
//
// Two kinds of colour token:
// - `Color` for values that never change (accent, status, backgrounds).
// - `DSStyle` for values that adapt to Reduce Transparency / Increase Contrast. It is a
//   `ShapeStyle`, so it works anywhere a style does: `.foregroundStyle(DS.Text.muted)`,
//   `.background(DS.Surface.card)`, `.fill(...)`, `.stroke(...)`.

enum DS {}

// MARK: - Adaptive style

struct DSStyle: ShapeStyle {
    var base: Color
    /// Used when Increase Contrast is on.
    var highContrast: Color? = nil
    /// Used when Reduce Transparency or Increase Contrast is on, for translucent tokens.
    var opaque: Color? = nil

    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.accessibilityReduceTransparency, let opaque { return opaque }
        if environment.colorSchemeContrast == .increased {
            if let highContrast { return highContrast }
            if let opaque { return opaque }
        }
        return base
    }
}

// MARK: - Colour

extension Color {
    /// 0xRRGGBB with optional opacity.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension DS {
    enum Background {
        static let base = Color(rgb: 0x060C12)
        static let deep = Color(rgb: 0x02070B)
        static let elevated = Color(rgb: 0x0B131B)
        static let topGradient = Color(rgb: 0x0E1822)
        static let pureBlack = Color.black
    }

    enum Surface {
        static let card = DSStyle(base: Color(rgb: 0x141E29, opacity: 0.78), opaque: Color(rgb: 0x111A24))
        static let cardQuiet = DSStyle(base: Color(rgb: 0x0E161F, opacity: 0.80), opaque: Color(rgb: 0x0B131C))
        static let field = DSStyle(base: Color(rgb: 0x1B2631, opacity: 0.92), opaque: Color(rgb: 0x1A2530))
        static let fieldFocused = DSStyle(base: Color(rgb: 0x1F2C38, opacity: 0.98), opaque: Color(rgb: 0x1F2C38))
        static let glassOnPhoto = DSStyle(base: Color(rgb: 0x161A1E, opacity: 0.55), opaque: Color(rgb: 0x161A1E))
        static let glassPill = DSStyle(base: Color(rgb: 0x1E2834, opacity: 0.62), opaque: Color(rgb: 0x1E2834))
        static let glassStrong = DSStyle(base: Color(rgb: 0x101820, opacity: 0.92), opaque: Color(rgb: 0x10181F))
        static let nav = DSStyle(base: Color(rgb: 0x0C1115, opacity: 0.92), opaque: Color(rgb: 0x0C1115))
        static let scrim = Color(rgb: 0x02070C, opacity: 0.56)
        static let pressed = Color.white.opacity(0.06)
        static let glassSubtle = Color.white.opacity(0.035)
        static let leaderRow = Color(rgb: 0x5EF7A6, opacity: 0.035)

        static let neutralBadge = Color(rgb: 0x2A2F37)
        static let iconDisc = Color(rgb: 0x1A231B)
        static let raised = Color(rgb: 0x16212D)
        static let dialog = Color(rgb: 0x111B26)
        static let sheet = Color(rgb: 0x0B131B)
        static let avatar = Color(rgb: 0x1E2A38)
        static let mapFrame = Color(rgb: 0x11191D)
        static let dangerContainer = Color(rgb: 0x3A1518)
        static let cameraControl = Color.black.opacity(0.50)
        /// QR code frame: white whatever the theme, so scanners can read it.
        static let codeWhite = Color.white
    }

    enum Text {
        static let primary = DSStyle(base: Color(rgb: 0xF5F7FA))
        static let label = DSStyle(base: Color(rgb: 0xD5D9DF))
        static let secondary = DSStyle(base: Color(rgb: 0xB4B9C1))
        /// Increase Contrast: muted becomes secondary.
        static let muted = DSStyle(base: Color(rgb: 0x868C95), highContrast: Color(rgb: 0xB4B9C1))
        /// Fails AA for body text (2.9:1 on card). Separators and 18 pt+ only.
        /// Increase Contrast: subtle becomes muted.
        static let subtle = DSStyle(base: Color(rgb: 0x5C636D), highContrast: Color(rgb: 0x868C95))
        /// Disabled controls only.
        static let disabled = DSStyle(base: Color(rgb: 0x5D6670))
        static let placeholder = DSStyle(base: Color(rgb: 0x868C95), highContrast: Color(rgb: 0xB4B9C1))
        static let onAccent = Color(rgb: 0x0C0E02)
        static let onSuccess = Color(rgb: 0x0B2416)
        static let onPhoto = Color.white
        static let onPhotoMuted = Color.white.opacity(0.78)
    }

    enum Accent {
        static let base = Color(rgb: 0xCDEF1E)
        static let bright = Color(rgb: 0xD4F140)
        static let soft = Color(rgb: 0xAECB1A)
        static let deep = Color(rgb: 0x718310)
        static let tint = base.opacity(0.12)
        static let tonal = base.opacity(0.17)
        static let border = base.opacity(0.45)
        static let glow = base.opacity(0.28)
        static let focusBorder = Color(rgb: 0xB8D71B)
    }

    /// The Go Pro invitation only: gold text, rim and glow on clear glass, so it can't be mistaken
    /// for a lime action button (Create ride) or the amber *tint* of the last-day trial badge.
    enum Pro {
        static let goldLight = Color(rgb: 0xFFE38A)
        static let gold = Color(rgb: 0xFFC247)
        static let goldDeep = Color(rgb: 0xF29A1F)
        static let glow = Color(rgb: 0xFFB22E)
        static var gradient: LinearGradient {
            LinearGradient(colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    enum Status {
        static let success = Color(rgb: 0x5EF7A6)
        static let successTint = success.opacity(0.12)
        static let successBorder = success.opacity(0.40)
        static let warning = Color(rgb: 0xFFCF70)
        static let warningTint = warning.opacity(0.12)
        static let danger = Color(rgb: 0xFBB0A9)
        static let dangerTint = danger.opacity(0.13)
        static let dangerBorder = danger.opacity(0.40)
        /// Fills and bold labels only; borderline (4.5:1) as text on a card.
        static let dangerStrong = Color(rgb: 0xE5484D)
        static let info = Color(rgb: 0x9DBEFF)
    }

    /// Regroup reasons. Always shown with an icon and a word, never colour alone.
    enum Category {
        static let fuel = Color(rgb: 0xFFB547)
        static let food = Color(rgb: 0xFF8A4C)
        static let scenic = Color(rgb: 0x5AB8FF)
        static let other = Color(rgb: 0xB58CFF)
        static let emergency = Status.danger
        static func color(forRegroup type: String) -> Color {
            switch type {
            case "FUEL":   return fuel
            case "FOOD":   return food
            case "SCENIC": return scenic
            default:       return other
            }
        }
    }

    enum Border {
        private static let tone: (Double) -> Color = { Color(rgb: 0xA0B4C8, opacity: $0) }
        static let strongColor = tone(0.28)
        // Increase Contrast lifts every hairline to the strong stroke.
        static let hairline = DSStyle(base: tone(0.10), highContrast: strongColor)
        static let subtle = DSStyle(base: tone(0.12), highContrast: strongColor)
        static let `default` = DSStyle(base: tone(0.18), highContrast: strongColor)
        static let strong = DSStyle(base: strongColor)
        static let divider = DSStyle(base: tone(0.10), highContrast: strongColor)
        static let focus = Accent.focusBorder
        static let leaderRow = Status.success.opacity(0.22)
    }

    /// Initial-only avatars get a solid colour picked from the rider id.
    static let avatarPalette: [Color] = [0xE53872, 0x7C5CFF, 0x2F9BFF, 0xF2994A, 0x27AE8F, 0xC2410C]
        .map { Color(rgb: $0) }

    /// Google dark map style colours (JSON `tokens.color.map`), for the map and its overlays.
    enum Map {
        static let background = Color(rgb: 0x11191D)
        static let park = Color(rgb: 0x17271F)
        static let roadMinor = Color(rgb: 0x252E33)
        static let roadMajor = Color(rgb: 0x38434A)
        static let roadStroke = Color(rgb: 0x0C1215)
        static let water = Color(rgb: 0x0B1418)
        static let label = Color(rgb: 0x8D969C)
        static let labelHalo = Color(rgb: 0x11191D)
        static let routeCore = Accent.base
        static let routeGlow = Accent.base.opacity(0.3)
        static let routePlanned = Accent.base.opacity(0.28)
        static let routeAlternative = Color(rgb: 0xB4B9C1, opacity: 0.40)
        static let routeConnector = Accent.base.opacity(0.75)
        static let startMarker = Status.success
        static let stopMarker = Accent.deep
        static let endMarker = Accent.base
        static let emergencyMarker = Status.dangerStrong
        static let markerPlate = Color(rgb: 0x0A1014, opacity: 0.86)
        static let riderRing = Accent.base
        static let edgeChipRing = Status.success
        /// Smallest text allowed on a map pin (iOS minimum).
        static let minLabelSize: CGFloat = 11
        static let routeRail = Color(rgb: 0x313838)
    }
}

// MARK: - Gradients

extension DS {
    enum Gradient {
        /// base → base (60%) → deep. Hero photos fade to `base`, so they meet this without a seam.
        static let appBackground = LinearGradient(
            stops: [
                .init(color: Background.base, location: 0),
                .init(color: Background.base, location: 0.6),
                .init(color: Background.deep, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )

        /// Every hero photo. Doubles as the ~35% dimming layer under glass buttons.
        static let photoFade = LinearGradient(
            stops: [
                .init(color: Color(rgb: 0x060C12, opacity: 0.10), location: 0),
                .init(color: Color(rgb: 0x060C12, opacity: 0.25), location: 0.35),
                .init(color: Color(rgb: 0x060C12, opacity: 0.80), location: 0.72),
                .init(color: Background.base, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )

        /// Home hero: keeps the left side dark under the headline.
        static let photoSideFade = LinearGradient(
            stops: [
                .init(color: Color(rgb: 0x060C12, opacity: 0.85), location: 0),
                .init(color: Color(rgb: 0x060C12, opacity: 0.35), location: 0.55),
                .init(color: Color(rgb: 0x060C12, opacity: 0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )

        /// Active-ride card and hero scrim (opaque content layer, no glass).
        static let cardPhotoScrim = LinearGradient(
            stops: [
                .init(color: Color(rgb: 0x04090E, opacity: 0.15), location: 0),
                .init(color: Color(rgb: 0x04090E, opacity: 0.25), location: 0.45),
                .init(color: Color(rgb: 0x04090E, opacity: 0.88), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )

        /// Fade above a sticky bottom action.
        static let bottomActionFade = LinearGradient(
            colors: [Background.base.opacity(0), Background.base],
            startPoint: .top, endPoint: .bottom
        )

        /// Membership and Splash.
        static func accentAura(endRadius: CGFloat) -> RadialGradient {
            RadialGradient(
                colors: [Accent.base.opacity(0.12), Accent.base.opacity(0)],
                center: .top, startRadius: 0, endRadius: endRadius
            )
        }

        /// The paywall's warm wash from the top (the Pro gold, not the lime accent).
        static func goldAura(endRadius: CGFloat) -> RadialGradient {
            RadialGradient(
                colors: [Pro.glow.opacity(0.16), Pro.glow.opacity(0)],
                center: .top, startRadius: 0, endRadius: endRadius
            )
        }

        static func dangerAura(endRadius: CGFloat) -> RadialGradient {
            RadialGradient(
                colors: [Status.danger.opacity(0.10), Status.danger.opacity(0)],
                center: .top, startRadius: 0, endRadius: endRadius
            )
        }
    }
}

// MARK: - Spacing, radius, borders, sizes

extension DS {
    /// 4-pt grid. `pN` is N × 4 (p14 = 56).
    enum Space {
        static let p1: CGFloat = 4
        static let p2: CGFloat = 8
        static let p3: CGFloat = 12
        static let p4: CGFloat = 16
        static let p5: CGFloat = 20
        static let p6: CGFloat = 24
        static let p7: CGFloat = 28
        static let p8: CGFloat = 32
        static let p9: CGFloat = 36
        static let p10: CGFloat = 40
        static let p12: CGFloat = 48
        static let p14: CGFloat = 56
        static let p16: CGFloat = 64

        static let screenInset: CGFloat = 20
        static let sectionGap: CGFloat = 24
        static let listGap: CGFloat = 12
        static let fieldGap: CGFloat = 8
        static let contentMaxWidth: CGFloat = 560
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let nav: CGFloat = 28
        static let pill: CGFloat = 999
        /// Primary buttons (the spec samples them at 18).
        static let button: CGFloat = 18
    }

    enum BorderWidth {
        static let hairline: CGFloat = 0.5
        static let `default`: CGFloat = 1
        static let emphasis: CGFloat = 1.5
        static let focus: CGFloat = 2
    }

    enum IconSize {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let `default`: CGFloat = 22
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let hero: CGFloat = 40
    }

    enum AvatarSize {
        static let xs: CGFloat = 24
        static let sm: CGFloat = 34
        static let stack: CGFloat = 28
        static let md: CGFloat = 40
        static let lg: CGFloat = 46
        static let xl: CGFloat = 72
        static let xxl: CGFloat = 96
    }

    /// Minimum tap targets.
    enum Target {
        static let minimum: CGFloat = 44
        static let hud: CGFloat = 48
        static let button: CGFloat = 56
    }

    enum Opacity {
        static let disabled = 0.42
        static let offline = 0.5
        static let pressed = 0.86
        static let inputDisabled = 0.48
    }
}

// MARK: - Shadows

struct DSShadow {
    var color: Color
    var x: CGFloat = 0
    var y: CGFloat
    /// CSS-style blur; SwiftUI's `radius` is half of it.
    var blur: CGFloat
}

extension DS {
    enum Shadow {
        static let card = DSShadow(color: .black.opacity(0.20), y: 8, blur: 24)
        static let floating = DSShadow(color: .black.opacity(0.30), y: 12, blur: 32)
        /// Primary actions only.
        static let accentGlow = DSShadow(color: Accent.glow, y: 6, blur: 28)
        static let focusGlow = DSShadow(color: Accent.base.opacity(0.14), y: 0, blur: 12)
        /// Any text drawn directly over a destination photo or map.
        static let textOnPhoto = DSShadow(color: .black.opacity(0.60), y: 2, blur: 12)
    }
}

extension View {
    func dsShadow(_ shadow: DSShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.blur / 2, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Motion

extension DS {
    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.12)
        static let standard: Animation = .timingCurve(0.2, 0, 0, 1, duration: 0.22)
        static let emphasized: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.32)
        static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.82)

        /// Looping ambient animations (all stop under Reduce Motion).
        static let livePulse: Animation = .easeInOut(duration: 1).repeatForever(autoreverses: true)
        static let glowBreath: Animation = .easeInOut(duration: 2).repeatForever(autoreverses: true)
        static let routeTrace: Animation = .linear(duration: 3).repeatForever(autoreverses: false)
    }
}

private struct DSAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that is skipped under Reduce Motion.
    func dsAnimation<V: Equatable>(_ animation: Animation = DS.Motion.standard, value: V) -> some View {
        modifier(DSAnimationModifier(animation: animation, value: value))
    }

    /// Transparent system navigation bar over a hero photo (plan §4.3). Toolbar items render as
    /// floating Liquid Glass; back button, swipe-back and the inline title on scroll come with it.
    func dsTransparentNavigationBar() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

// MARK: - Control strokes and fills (white-on-dark)

extension DS {
    /// Secondary buttons, join button, glass-ish controls on the base.
    enum Control {
        static let fill = Color.white.opacity(0.07)
        static let border = Color.white.opacity(0.14)
        static let onPhotoBorder = Color.white.opacity(0.10)
        static let metaFill = Color(rgb: 0x0A1016, opacity: 0.55)
        static let metaBorder = Color.white.opacity(0.16)
        static let addStopFill = Color.white.opacity(0.025)
        static let removeFill = Color.white.opacity(0.14)
        /// DotGridTexture: 1.2 pt dots every 24 pt.
        static let dotGrid = Color.white.opacity(0.05)
    }
}
