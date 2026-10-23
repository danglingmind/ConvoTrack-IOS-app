import SwiftUI
import CoreLocation

/// Full-screen place search over the planner's map, for one stop at a time. Results come in as
/// the rider types (`search-fields.md › Best practices`: "start search immediately when a person
/// types"); before that it offers recent destinations, and "Your location" when choosing a start.
struct PlannerSearchOverlay: View {
    let role: PlannerStopRole
    var offersCurrentLocation = false
    let recents: [PlaceResult]
    var onPick: (PlaceResult) -> Void
    var onUseCurrentLocation: () -> Void
    /// Place the stop by moving the map under a fixed pin, for spots search can't name.
    var onChooseOnMap: () -> Void
    var onCancel: () -> Void

    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var prompt: LocalizedStringKey {
        switch role {
        case .start:       "Choose a start point"
        case .stop:        "Add a stop"
        case .destination: "Where are you riding?"
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            field
                .padding(.horizontal, DS.Space.p3)
                .padding(.top, DS.Space.p1)
                .padding(.bottom, DS.Space.p3)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmedQuery.count < 2 {
                        if offersCurrentLocation {
                            row(icon: "location.fill", title: Text("Your location"), subtitle: nil, distance: nil,
                                action: onUseCurrentLocation)
                        }
                        chooseOnMapRow
                        if !recents.isEmpty {
                            DSSectionHeading("Recent")
                                .padding(.top, DS.Space.p3)
                            ForEach(recents) { place in placeRow(place, icon: "clock") }
                        }
                    } else if results.isEmpty && !isSearching {
                        Text("No places match “\(trimmedQuery)”. Check the spelling or try a nearby town.")
                            .dsText(.body)
                            .foregroundStyle(DS.Text.muted)
                            .padding(.vertical, DS.Space.p6)
                        chooseOnMapRow
                    } else {
                        ForEach(results) { place in placeRow(place, icon: "mappin") }
                        chooseOnMapRow
                    }
                }
                .padding(.horizontal, DS.Space.screenInset)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(DS.Background.base.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: query) { _, newValue in search(newValue) }
    }

    private var field: some View {
        HStack(spacing: DS.Space.p1) {
            Button(action: onCancel) {
                Image(systemName: "chevron.left")
                    .dsIcon(DS.IconSize.md, weight: .semibold)
                    .foregroundStyle(DS.Text.primary)
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            TextField("", text: $query, prompt: Text(prompt).foregroundStyle(DS.Text.placeholder))
                .dsText(.locationTitle)
                .foregroundStyle(DS.Text.primary)
                .tint(DS.Accent.base)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { if let first = results.first { onPick(first) } }

            if isSearching {
                ProgressView().controlSize(.small).tint(DS.Accent.base)
                    .frame(width: DS.Target.minimum)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsIcon(DS.IconSize.md)
                        .foregroundStyle(DS.Text.muted)
                        .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.trailing, DS.Space.p1)
        .frame(minHeight: 52)
        .background(DS.Surface.fieldFocused, in: Capsule())
        .overlay(Capsule().stroke(DS.Border.focus, lineWidth: DS.BorderWidth.emphasis))
    }

    private var chooseOnMapRow: some View {
        row(icon: "map", title: Text("Choose on map"), subtitle: nil, distance: nil, action: onChooseOnMap)
    }

    private func placeRow(_ place: PlaceResult, icon: String) -> some View {
        let distance = LocationService.shared.lastLocation.map { $0.distance(from: place.location) }
        return row(icon: icon, title: Text(place.name), subtitle: place.formattedAddress, distance: distance) {
            onPick(place)
        }
    }

    private func row(icon: String, title: Text, subtitle: String?, distance: CLLocationDistance?,
                     action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.p3) {
                DSIconDisc(systemImage: icon, size: 36, iconSize: DS.IconSize.sm)
                // Names wrap rather than truncate: the name is the whole choice.
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .dsText(.locationTitle)
                        .foregroundStyle(DS.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .dsText(.helper)
                            .foregroundStyle(DS.Text.muted)
                            .lineLimit(2)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let distance {
                    Text(Self.distanceText(distance))
                        .dsText(.dataMono)
                        .foregroundStyle(DS.Text.muted)
                        .fixedSize()
                }
            }
            .padding(.vertical, DS.Space.p3)
            .frame(minHeight: DS.Target.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { DSDivider().padding(.leading, 48) }
    }

    private static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.0f km", meters / 1000)
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = await GooglePlacesService.search(query: trimmed, near: LocationService.shared.lastLocation)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}
