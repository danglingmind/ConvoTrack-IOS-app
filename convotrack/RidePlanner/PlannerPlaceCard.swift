import SwiftUI
import CoreLocation

/// A spot on the map the rider is pointing at: a dropped pin, or the centre of the map while
/// choosing on it. Its street name arrives a moment later from reverse geocoding.
struct PlaceCandidate: Equatable {
    let coordinate: CLLocationCoordinate2D
    var place: PlaceResult?
    var isResolving = true

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.place == rhs.place && lhs.isResolving == rhs.isResolving
    }

    /// What the stop is saved as. Falls back to a plain label when the lookup found nothing, so
    /// a spot in the middle of nowhere can still be a stop.
    var resolvedPlace: PlaceResult {
        place ?? PlaceResult(
            id: String(format: "pin_%.5f_%.5f", coordinate.latitude, coordinate.longitude),
            name: String(localized: "Pinned location"),
            coordinate: coordinate,
            formattedAddress: nil
        )
    }

    var coordinateText: String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}

struct PlannerPlaceAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    var action: () -> Void
}

/// Sheet header for a `PlaceCandidate`: its name and address, then what to do with it. The
/// first action is the primary one; the rest sit beside it as secondary buttons.
struct PlannerPlaceCard: View {
    let eyebrow: LocalizedStringKey
    let candidate: PlaceCandidate?
    /// Shown instead of a name until there's a spot to name.
    var emptyMessage: LocalizedStringKey = "Move the map to choose a spot"
    let actions: [PlannerPlaceAction]
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            HStack(alignment: .top, spacing: DS.Space.p2) {
                VStack(alignment: .leading, spacing: DS.Space.p1) {
                    Text(eyebrow)
                        .dsText(.eyebrow)
                        .foregroundStyle(DS.Accent.base)
                    nameBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .dsIcon(DS.IconSize.sm, weight: .semibold)
                        .foregroundStyle(DS.Text.primary)
                        .frame(width: 30, height: 30)
                        .background(DS.Control.removeFill, in: Circle())
                        .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            if let primary = actions.first {
                DSPrimaryButton(title: primary.title, systemImage: primary.systemImage, action: primary.action)
                    .disabled(candidate == nil || candidate?.isResolving == true)
            }
            if actions.count > 1 {
                DSAdaptiveStack(spacing: DS.Space.p2) {
                    ForEach(actions.dropFirst()) { action in
                        DSSecondaryButton(title: action.title, systemImage: action.systemImage, action: action.action)
                            .disabled(candidate == nil || candidate?.isResolving == true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nameBlock: some View {
        if let candidate {
            HStack(spacing: DS.Space.p2) {
                Text(candidate.place?.name ?? (candidate.isResolving ? String(localized: "Finding address…")
                                                                      : String(localized: "Pinned location")))
                    .dsText(.rowTitle)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(1)
                if candidate.isResolving {
                    ProgressView().controlSize(.small).tint(DS.Accent.base)
                }
            }
            // A fixed two lines, name on one: while choosing on the map the text changes on every
            // pan, and a card that changed height with it would move the map, and the spot under
            // the pin, each time.
            Text(candidate.place?.formattedAddress ?? candidate.coordinateText)
                .dsText(.helper)
                .foregroundStyle(DS.Text.muted)
                .lineLimit(2, reservesSpace: true)
        } else {
            Text(emptyMessage)
                .dsText(.rowTitle)
                .foregroundStyle(DS.Text.secondary)
        }
    }
}
