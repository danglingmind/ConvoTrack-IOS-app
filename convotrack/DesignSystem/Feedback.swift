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
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
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
