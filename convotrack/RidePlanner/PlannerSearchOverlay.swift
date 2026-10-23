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
    /// Where the category chips look: along this route when it's given (adding a stop), else
    /// around `searchCenter`. No chips for a start.
    var searchCenter: CLLocationCoordinate2D? = nil
    var route: [CLLocationCoordinate2D] = []
    /// Show each hit's detour. Only a clean figure against a direct route: with other stops
    /// between, the hit's legs skip them.
    var measuresDetours = false
    /// The route options in force, so the detour baseline is timed on the same roads.
    var avoid: RouteAvoidances = .none
    /// A chip already picked on the map before the search opened.
    var initialCategory: PlaceCategory? = nil

    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var category: PlaceCategory?
    @State private var categoryHits: [PlaceSearchHit] = []
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

    private var showsChips: Bool { role != .start }
    private var searchesAlongRoute: Bool { role == .stop && route.count >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            field
                .padding(.horizontal, DS.Space.p3)
                .padding(.top, DS.Space.p1)
                .padding(.bottom, DS.Space.p3)

            if showsChips && trimmedQuery.count < 2 {
                PlannerCategoryChips(selected: category, onSelect: selectCategory)
                    .padding(.bottom, DS.Space.p2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let category, trimmedQuery.count < 2 {
                        categorySection(category)
                    } else if trimmedQuery.count < 2 {
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
        .onAppear {
            if let initialCategory {
                selectCategory(initialCategory)
            } else {
                focused = true
            }
        }
        .onChange(of: query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespaces).count >= 2 { category = nil }
            search(newValue)
        }
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

    // MARK: Categories

    @ViewBuilder
    private func categorySection(_ category: PlaceCategory) -> some View {
        Text(searchesAlongRoute ? "\(Text(category.title)) along your route" : "\(Text(category.title)) near the map")
            .dsText(.sectionLabel)
            .foregroundStyle(DS.Text.label)
            .padding(.vertical, DS.Space.p2)
            .accessibilityAddTraits(.isHeader)
        if isSearching && categoryHits.isEmpty {
            ProgressView().tint(DS.Accent.base)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.p6)
        } else if categoryHits.isEmpty {
            Text(searchesAlongRoute ? "Nothing found close to this route." : "Nothing found here. Move the map and try again.")
                .dsText(.body)
                .foregroundStyle(DS.Text.muted)
                .padding(.vertical, DS.Space.p6)
        } else {
            ForEach(categoryHits) { hit in
                placeRow(hit.place, icon: category.systemImage, detour: hit.detourSeconds)
            }
        }
        chooseOnMapRow
    }

    private func selectCategory(_ picked: PlaceCategory) {
        searchTask?.cancel()
        query = ""
        focused = false
        guard category != picked else {
            category = nil
            categoryHits = []
            isSearching = false
            return
        }
        DSHaptic.selection()
        category = picked
        categoryHits = []
        isSearching = true
        searchTask = Task {
            let hits: [PlaceSearchHit]
            if searchesAlongRoute {
                hits = await GooglePlacesService.searchAlongRoute(picked.query, route: route,
                                                                  measuresDetours: measuresDetours, avoiding: avoid)
            } else {
                hits = await GooglePlacesService.searchText(picked.query, near: searchCenter ?? LocationService.shared.lastLocation?.coordinate)
                    .map { PlaceSearchHit(place: $0) }
            }
            guard !Task.isCancelled else { return }
            categoryHits = hits
            isSearching = false
        }
    }

    private var chooseOnMapRow: some View {
        row(icon: "map", title: Text("Choose on map"), subtitle: nil, distance: nil, action: onChooseOnMap)
    }

    private func placeRow(_ place: PlaceResult, icon: String, detour: TimeInterval? = nil) -> some View {
        let distance = LocationService.shared.lastLocation.map { $0.distance(from: place.location) }
        // Along a route the detour is the number that matters; distance from here isn't.
        let subtitle: String? = detour.map { seconds in
            let minutes = Int((seconds / 60).rounded())
            let detourText = minutes < 1 ? String(localized: "No detour") : String(localized: "+\(minutes) min detour")
            return [detourText, place.formattedAddress].compactMap { $0 }.joined(separator: " · ")
        } ?? place.formattedAddress
        return row(icon: icon, title: Text(place.name), subtitle: subtitle, distance: detour == nil ? distance : nil) {
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

/// Fuel, Food, Viewpoints: one tap to the searches riders make most. Shared by the search screen
/// and the empty map.
struct PlannerCategoryChips: View {
    let selected: PlaceCategory?
    var onSelect: (PlaceCategory) -> Void
    /// Over the map the chips are floating controls (glass); in the search screen, plain fills.
    var onMap = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.p2) {
                ForEach(PlaceCategory.allCases) { category in
                    chip(category)
                }
            }
            .padding(.horizontal, onMap ? DS.Space.p3 : DS.Space.screenInset)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(_ category: PlaceCategory) -> some View {
        let isSelected = selected == category
        let label = Button { onSelect(category) } label: {
            Label { Text(category.title) } icon: { Image(systemName: category.systemImage) }
                .dsText(.buttonPill)
                .foregroundStyle(isSelected ? AnyShapeStyle(DS.Text.onAccent) : AnyShapeStyle(DS.Text.primary))
                .padding(.horizontal, DS.Space.p3)
                .frame(minHeight: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(DSPressStyle(scale: 0.96))
        .frame(minHeight: DS.Target.minimum)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if isSelected {
            label.background(DS.Accent.base, in: Capsule().inset(by: 4))
        } else if onMap {
            label.dsGlass(in: Capsule().inset(by: 4), interactive: true)
        } else {
            label.background(DS.Surface.field, in: Capsule().inset(by: 4))
                .overlay(Capsule().inset(by: 4).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
        }
    }
}
