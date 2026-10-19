import SwiftUI

// MARK: - Shared label

private struct DSButtonLabel: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var style: DSTextStyle = .button
    var iconSize: CGFloat = DS.IconSize.lg
    var spacing: CGFloat = DS.Space.p3

    var body: some View {
        HStack(spacing: spacing) {
            if let systemImage {
                Image(systemName: systemImage).dsIcon(iconSize, weight: .semibold)
            }
            Text(title)
                .dsText(style)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: - PrimaryButton

/// The one lime action on a screen: flat accent, dark label, glow. 56 pt minimum height.
struct DSPrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isLoading = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            DSHaptic.primary()
            action()
        } label: {
            ZStack {
                DSButtonLabel(title: title, systemImage: systemImage, spacing: DS.Space.p4)
                    .opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(DS.Text.onAccent) }
            }
            .foregroundStyle(DS.Text.onAccent)
            .frame(maxWidth: .infinity, minHeight: DS.Target.button)
            .padding(.horizontal, DS.Space.p4)
            .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .dsShadow(isEnabled ? DS.Shadow.accentGlow : DSShadow(color: .clear, y: 0, blur: 0))
        }
        .buttonStyle(DSPressStyle())
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : DS.Opacity.disabled)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

/// The primary button's look for labels that aren't a plain title (e.g. a price line that must
/// choose between layouts with `ViewThatFits`). Grows with the label instead of clipping it.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DS.Text.onAccent)
            .frame(maxWidth: .infinity, minHeight: DS.Target.button)
            .padding(.horizontal, DS.Space.p4)
            .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .dsShadow(isEnabled ? DS.Shadow.accentGlow : DSShadow(color: .clear, y: 0, blur: 0))
            .opacity(isEnabled ? 1 : DS.Opacity.disabled)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - SecondaryButton

struct DSSecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isLoading = false
    /// Shows the green "done" state (e.g. "You're ready").
    var isConfirmed = false
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            ZStack {
                DSButtonLabel(title: title, systemImage: isConfirmed ? "checkmark" : systemImage, iconSize: DS.IconSize.default, spacing: 10)
                    .opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(DS.Text.primary.base) }
            }
            .foregroundStyle(isConfirmed ? DS.Status.success : DS.Text.primary.base)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DS.Space.p4)
            .background(isConfirmed ? DS.Status.successTint : DS.Control.fill,
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(isConfirmed ? DS.Status.successBorder : DS.Control.border, lineWidth: DS.BorderWidth.default)
            )
        }
        .buttonStyle(DSPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - DestructiveButton

/// Never the primary role. Always behind a confirmation.
struct DSDestructiveButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.destructive()
            action()
        } label: {
            HStack(spacing: 0) {
                DSButtonLabel(title: title, systemImage: systemImage)
                if isLoading { Text("…").dsText(.button) }
            }
            .foregroundStyle(DS.Status.danger)
            .frame(maxWidth: .infinity, minHeight: DS.Target.button)
            .padding(.horizontal, DS.Space.p4)
            .background(DS.Status.dangerTint, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Status.dangerBorder, lineWidth: DS.BorderWidth.default)
            )
        }
        .buttonStyle(DSPressStyle())
        .disabled(isLoading)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - GhostButton

struct DSGhostButton: View {
    let title: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsText(.buttonPill)
                .foregroundStyle(DS.Text.secondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
    }
}

// MARK: - PillButton / TonalPill

struct DSPillButton: View {
    enum Variant { case primary, tonal, neutral, danger }

    let title: LocalizedStringKey
    var systemImage: String? = nil
    var variant: Variant = .primary
    /// 36 pt by default, 44 pt when `large`.
    var large = false
    var action: () -> Void

    private var foreground: Color {
        switch variant {
        case .primary: DS.Text.onAccent
        case .tonal: DS.Accent.base
        case .neutral: DS.Text.secondary.base
        case .danger: DS.Status.danger
        }
    }

    private var fill: Color {
        switch variant {
        case .primary: DS.Accent.base
        case .tonal: DS.Accent.tint
        case .neutral: DS.Surface.card.base
        case .danger: DS.Status.dangerTint
        }
    }

    private var stroke: Color? {
        switch variant {
        case .primary: nil
        case .tonal: DS.Accent.border
        case .neutral: DS.Border.default.base
        case .danger: DS.Status.dangerBorder
        }
    }

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            DSButtonLabel(title: title, systemImage: systemImage, style: .buttonPill, iconSize: DS.IconSize.sm, spacing: 6)
                .foregroundStyle(foreground)
                .padding(.horizontal, DS.Space.p4)
                .frame(minHeight: large ? DS.Target.minimum : 36)
                .background(fill, in: Capsule())
                .overlay { if let stroke { Capsule().stroke(stroke, lineWidth: DS.BorderWidth.default) } }
                .frame(minHeight: DS.Target.minimum)
                .contentShape(Capsule())
                .dsShadow(variant == .primary ? DS.Shadow.accentGlow : DSShadow(color: .clear, y: 0, blur: 0))
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(Text(title))
    }
}

/// Non-interactive 26 pt tag, e.g. RESUME on a ride row.
struct DSTonalPill: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .dsText(.buttonPill)
            .foregroundStyle(DS.Accent.base)
            .padding(.horizontal, 14)
            .frame(minHeight: 26)
            .background(DS.Accent.tonal, in: Capsule())
    }
}

// MARK: - TextButton

struct DSTextButton: View {
    enum Role { case confirm, dismiss, destructive }

    let title: LocalizedStringKey
    var role: Role = .dismiss
    var action: () -> Void

    private var color: Color {
        switch role {
        case .confirm: DS.Accent.base
        case .dismiss: DS.Text.secondary.base
        case .destructive: DS.Status.danger
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsText(.buttonPill)
                .foregroundStyle(color)
                .padding(.horizontal, DS.Space.p3)
                .frame(minHeight: DS.Target.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SquareIconButton

struct DSSquareIconButton: View {
    enum Variant { case standard, danger }
    enum Size { case regular, hud, hudLandscape }

    let systemImage: String
    let label: LocalizedStringKey
    var variant: Variant = .standard
    var size: Size = .regular
    var isBusy = false
    var action: () -> Void

    private var side: CGFloat {
        switch size {
        case .regular: DS.Target.minimum   // spec says 36; 44 pt is the tap-target floor
        case .hud: 52
        case .hudLandscape: DS.Target.hud
        }
    }

    var body: some View {
        Button {
            variant == .danger ? DSHaptic.destructive() : DSHaptic.selection()
            action()
        } label: {
            ZStack {
                Image(systemName: systemImage)
                    .dsIcon(DS.IconSize.default, weight: .medium)
                    .opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(variant == .danger ? DS.Status.danger : DS.Text.primary.base)
            .frame(width: side, height: side)
            .background(variant == .danger ? DS.Status.dangerTint : DS.Surface.card.base,
                        in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(variant == .danger ? DS.Status.dangerBorder : DS.Border.default.base, lineWidth: DS.BorderWidth.default)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle(scale: 0.96))
        .disabled(isBusy)
        .accessibilityLabel(label)
    }
}

// MARK: - ActionButtonPair (Home: CREATE / JOIN)

/// Two equal actions side by side; they stack at accessibility text sizes.
/// (Plain `if`/`else` stacks rather than `AnyLayout`: buttons inside an `AnyLayout` stopped
/// receiving taps.)
struct DSActionButtonPair: View {
    let createAction: () -> Void
    let joinAction: () -> Void
    /// Both actions need an upgrade first: icons become locks, the buttons still respond (they
    /// open the paywall) rather than going dead.
    var isLocked = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var createButton: some View {
        Button {
            DSHaptic.primary()
            createAction()
        } label: {
            HStack(spacing: DS.Space.p2) {
                Image(systemName: isLocked ? "lock.fill" : "plus.circle.fill").dsIcon(DS.IconSize.lg)
                Text("Create ride").dsText(.buttonWide).lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7).multilineTextAlignment(.center)
            }
            .foregroundStyle(DS.Text.onAccent)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, DS.Space.p3)
            .background(DS.Accent.base, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .dsShadow(DS.Shadow.accentGlow)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(isLocked ? Text("Needs ConvoTrack Pro") : Text(""))
    }

    private var joinButton: some View {
        Button {
            DSHaptic.selection()
            joinAction()
        } label: {
            HStack(spacing: DS.Space.p2) {
                Image(systemName: isLocked ? "lock.fill" : "person.badge.plus").dsIcon(DS.IconSize.default)
                Text("Join ride").dsText(.buttonWide).lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7).multilineTextAlignment(.center)
            }
            .foregroundStyle(DS.Text.primary.base)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, DS.Space.p3)
            .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous), clear: true, interactive: true)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(isLocked ? Text("Needs ConvoTrack Pro") : Text(""))
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                createButton
                joinButton
            }
        } else {
            HStack(spacing: 10) {
                createButton
                joinButton
            }
        }
    }
}

// MARK: - Preview

struct ButtonsGallery: View {
    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(spacing: DS.Space.p4) {
                    DSActionButtonPair(createAction: {}, joinAction: {})
                    DSPrimaryButton(title: "Start ride", systemImage: "arrow.turn.up.right") {}
                    DSPrimaryButton(title: "Create ride", isLoading: true) {}
                    DSPrimaryButton(title: "Waiting for riders") {}.disabled(true)
                    DSSecondaryButton(title: "Share summary", systemImage: "square.and.arrow.up") {}
                    DSSecondaryButton(title: "You're ready", isConfirmed: true) {}
                    DSDestructiveButton(title: "Remove from ride") {}
                    DSGhostButton(title: "Cancel request") {}
                    DSAdaptiveStack {
                        DSPillButton(title: "Upgrade", variant: .primary) {}
                        DSPillButton(title: "Active", variant: .tonal) {}
                        DSPillButton(title: "Retry", systemImage: "arrow.clockwise", variant: .neutral) {}
                    }
                    DSAdaptiveStack {
                        DSTonalPill(title: "Resume")
                        DSTextButton(title: "Cancel") {}
                        DSTextButton(title: "Delete", role: .destructive) {}
                    }
                    DSAdaptiveStack {
                        DSSquareIconButton(systemImage: "person.3.fill", label: "Regroup", size: .hud) {}
                        DSSquareIconButton(systemImage: "stop.fill", label: "End ride", variant: .danger, size: .hud) {}
                    }
                }
                .padding(DS.Space.screenInset)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Buttons") { ButtonsGallery() }
#Preview("Buttons AX3") { ButtonsGallery().dynamicTypeSize(.accessibility3) }
