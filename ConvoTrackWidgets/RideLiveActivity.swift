import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island presentation of an active ride. The app updates it locally
/// (see `RideLiveActivityController`); this file only draws what it is handed.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(Self.url(context.attributes))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: state)
                }
            } compactLeading: {
                CompactLeading(state: state)
            } compactTrailing: {
                CompactTrailing(state: state)
            } minimal: {
                Minimal(state: state)
            }
            .widgetURL(Self.url(context.attributes))
            .keylineTint(state.emergencyName == nil ? Brand.dark : Brand.danger)
        }
    }

    /// `convotrack://ride/<id>`; `DeepLinkRouter` opens navigation for that ride if it is current.
    static func url(_ attributes: RideActivityAttributes) -> URL? {
        URL(string: "convotrack://ride/\(attributes.rideId)")
    }
}

// MARK: - Palette

private enum Brand {
    /// Brand lime (#caf300): bold on the always-black Dynamic Island and dark Lock Screen.
    static let dark = Color(red: 0.792, green: 0.953, blue: 0)
    /// Darker olive of the same hue for the light Lock Screen, where lime would wash out.
    static let light = Color(red: 0.29, green: 0.36, blue: 0)
    static let danger = Color(red: 1, green: 0.30, blue: 0.27)
}

/// Accent that adapts to the appearance, and drops to the primary colour under Increase Contrast.
private struct AccentModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.foregroundStyle(contrast == .increased ? Color.primary : (scheme == .dark ? Brand.dark : Brand.light))
    }
}

private extension View {
    func brandAccent() -> some View { modifier(AccentModifier()) }
}

// MARK: - Pieces

/// Red warning triangle that replaces the turn arrow while an emergency is open.
private struct EmergencyGlyph: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Brand.danger)
    }
}

private struct ManeuverGlyph: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        if state.emergencyName != nil {
            EmergencyGlyph()
        } else {
            Image(systemName: state.symbolName)
                .fontWeight(.bold)
                .brandAccent()
        }
    }
}

/// The ConvoTrack mark with no container (HIG), tinted with the brand accent.
private struct BrandMark: View {
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.caption.weight(.bold))
            .brandAccent()
            .accessibilityHidden(true)
    }
}

// MARK: - Compact / minimal

private struct CompactLeading: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.emergencyName != nil || state.distanceText.isEmpty {
            // Graphic only: an emergency needs no distance, and with no turn there is none to show.
            ManeuverGlyph(state: state).font(.body)
        } else {
            HStack(spacing: 4) {
                ManeuverGlyph(state: state)
                Text(state.distanceText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct CompactTrailing: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.emergencyName != nil {
            Text("Help")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.danger)
        } else {
            Text(state.arrivalText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct Minimal: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        ManeuverGlyph(state: state)
            .font(.body)
            .accessibilityLabel(state.emergencyText ?? state.instruction)
    }
}

// MARK: - Expanded

private struct ExpandedLeading: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        if state.emergencyName != nil {
            EmergencyGlyph().font(.title)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ManeuverGlyph(state: state).font(.title)
                Text(state.distanceText)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .brandAccent()
            }
        }
    }
}

private struct ExpandedTrailing: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        if state.emergencyName == nil {
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.arrivalText)
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(state.timeLeftText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExpandedBottom: View {
    let state: RideActivityAttributes.ContentState
    var body: some View {
        if let text = state.emergencyText {
            Text(text)
                .font(.headline.weight(.bold))
                .foregroundStyle(Brand.danger)
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.instruction)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let convoy = state.convoyText {
                    Label(convoy, systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = state.emergencyText {
                HStack(spacing: 10) {
                    EmergencyGlyph().font(.title2)
                    Text(text)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Brand.danger)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ManeuverGlyph(state: state).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.distanceText)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .brandAccent()
                        Text(state.instruction)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(state.arrival, style: .time)
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text(state.timeLeftText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 6) {
                BrandMark()
                Text(attributes.destinationName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if state.emergencyName == nil, let convoy = state.convoyText {
                    Label(convoy, systemImage: "person.2.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }
}
