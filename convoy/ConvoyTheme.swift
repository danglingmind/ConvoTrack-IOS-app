import SwiftUI

// MARK: - Color Palette
extension Color {
    // Primary
    static let primaryFixed = Color(hex: "caf300")       // Lime green accent
    static let primaryFixedDim = Color(hex: "b0d500")
    static let onPrimaryFixed = Color(hex: "171e00")      // Dark text on lime
    static let onPrimaryFixedVariant = Color(hex: "3e4c00")
    static let primaryContainer = Color(hex: "caf300")
    static let onPrimaryContainer = Color(hex: "596c00")

    // Surface
    static let surfaceDim = Color(hex: "131313")
    static let surface = Color(hex: "131313")
    static let surfaceContainerLowest = Color(hex: "0e0e0e")
    static let surfaceContainerLow = Color(hex: "1b1b1b")
    static let surfaceContainer = Color(hex: "20201f")
    static let surfaceContainerHigh = Color(hex: "2a2a2a")
    static let surfaceContainerHighest = Color(hex: "353535")
    static let surfaceBright = Color(hex: "393939")
    static let surfaceVariant = Color(hex: "353535")

    // On Surface
    static let onSurface = Color(hex: "e5e2e1")
    static let onSurfaceVariant = Color(hex: "c5c9ac")
    static let onBackground = Color(hex: "e5e2e1")

    // Secondary
    static let secondary = Color(hex: "c8c6c5")
    static let secondaryContainer = Color(hex: "4a4949")
    static let onSecondaryContainer = Color(hex: "bab8b7")
    static let secondaryFixed = Color(hex: "e5e2e1")

    // Tertiary
    static let tertiaryFixed = Color(hex: "62ff96")
    static let tertiaryFixedDim = Color(hex: "00e475")
    static let tertiaryContainer = Color(hex: "62ff96")
    static let onTertiaryContainer = Color(hex: "007438")

    // Outline
    static let outline = Color(hex: "8f9378")
    static let outlineVariant = Color(hex: "444932")

    // Error
    static let errorColor = Color(hex: "ffb4ab")
    static let errorContainer = Color(hex: "93000a")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
extension Font {
    static let displayMetrics = Font.system(size: 48, weight: .bold, design: .default).leading(.tight)
    static let headlineLg = Font.system(size: 32, weight: .bold)
    static let headlineMd = Font.system(size: 24, weight: .semibold)
    static let bodyLg = Font.system(size: 18, weight: .medium)
    static let bodyMd = Font.system(size: 16, weight: .regular)
    static let labelCaps = Font.system(size: 12, weight: .bold, design: .monospaced)
    static let dataMono = Font.system(size: 14, weight: .medium, design: .monospaced)
}

// MARK: - View Modifiers
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surfaceContainerHigh.opacity(0.7))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.4), lineWidth: 1))
    }
}

struct LimePrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.primaryFixed)
            .foregroundColor(Color.onPrimaryFixed)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.primaryFixed.opacity(0.3), radius: 20)
    }
}

// MARK: - Common Components
struct ConvoyTopBar: View {
    let title: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack {
            if showBack {
                Button(action: { onBack?() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.primaryFixed)
                        .frame(width: 44, height: 44)
                }
            }
            Text(title)
                .font(.headlineLg)
                .foregroundColor(Color.primaryFixed)
                .tracking(showBack ? 0 : -0.5)
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundColor(Color.primaryFixed)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color.surfaceContainer.opacity(0.9))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.outlineVariant.opacity(0.4)), alignment: .bottom)
    }
}

struct ConvoyBottomNav: View {
    enum Tab { case garage, track, profile }
    @Binding var activeTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            navItem(icon: "house.and.flag", label: "GARAGE", tab: .garage)
            Spacer()
            navItem(icon: "location.north.fill", label: "TRACK", tab: .track, isPrimary: true)
            Spacer()
            navItem(icon: "person", label: "PROFILE", tab: .profile)
        }
        .padding(.horizontal, 32)
        .frame(height: 80)
        .background(Color.surfaceContainerLowest.opacity(0.95))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.outlineVariant.opacity(0.5)), alignment: .top)
    }

    private func navItem(icon: String, label: String, tab: Tab, isPrimary: Bool = false) -> some View {
        Button(action: { activeTab = tab }) {
            if isPrimary {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                    Text(label)
                        .font(.labelCaps)
                        .tracking(1)
                }
                .foregroundColor(Color.onPrimaryFixed)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.primaryFixed)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                    Text(label)
                        .font(.labelCaps)
                        .tracking(1)
                }
                .foregroundColor(activeTab == tab ? Color.primaryFixed : Color.onSurfaceVariant.opacity(0.6))
            }
        }
    }
}
