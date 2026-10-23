import SwiftUI
import CoreLocation

/// The map-first ride planner (`design/CREATE_RIDE_REDESIGN.md`): a full-bleed map, a search pill
/// that becomes the stops card once a destination is picked, and a resizable sheet with the
/// route summary and the ride's details. The screen that hosts it supplies the primary action
/// (Create ride / Save changes) and does the saving.
struct RidePlannerView<PrimaryAction: View>: View {
    enum Mode {
        /// A new ride: Back from the route returns to the empty map, as in Google Maps.
        case create
        /// A saved ride: there's no empty map to go back to, so Back leaves the screen.
        case edit
    }

    @ObservedObject var model: RidePlannerModel
    let riderCap: Int
    let isPremium: Bool
    var mode: Mode = .create
    var onUpgrade: () -> Void
    var onClose: () -> Void
    /// Adds a ⋯ menu to the route summary with a destructive "Delete ride". Nil hides it.
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var primaryAction: PrimaryAction

    @State private var detent: DSMapSheetDetent = .low
    /// The stop whose search is open.
    @State private var searchStopID: UUID?
    @State private var stopsExpanded = false
    /// A category chip tapped on the empty map, handed to the search it opens.
    @State private var searchCategory: PlaceCategory?
    /// Where the camera last came to rest, so "near the map" means what's on screen.
    @State private var mapTarget: CLLocationCoordinate2D?
    /// A pin the rider dropped with a long-press, waiting for them to say what it is.
    @State private var droppedPin: PlaceCandidate?
    /// The stop being placed by moving the map under a fixed pin ("Choose on map").
    @State private var choosingStopID: UUID?
    /// The spot under that fixed pin, once the map comes to rest.
    @State private var mapCenter: PlaceCandidate?
    @State private var geocodeTask: Task<Void, Never>?
    @State private var topChromeBottom: CGFloat = 0
    @State private var sheetRestingHeight: CGFloat = 0
    /// The map's bottom padding: the resting sheet's height, except that it holds still while a
    /// dropped pin's card is up. Following the taller card would slide the map up and carry the
    /// pin away from the finger that dropped it; the card covering the logo for that moment is
    /// fine (`maps.md`: "It's fine when parts of your interface temporarily cover the logo").
    @State private var mapBottomPadding: CGFloat = 0
    /// The rider has panned or zoomed the map themselves; stop re-centring it on them.
    @State private var userMovedMap = false
    @State private var homeIndicatorInset: CGFloat = 0
    @State private var recents = RecentDestinations.load()
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // With the keyboard up the safe area's bottom is the keyboard, not the home indicator.
            let keyboardUp = proxy.safeAreaInsets.bottom > homeIndicatorInset + 1
            ZStack(alignment: .top) {
                map
                    .ignoresSafeArea()

                if searchStopID == nil {
                    topChrome
                        .padding(.horizontal, DS.Space.p3)
                        .padding(.top, DS.Space.p1)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                            topChromeBottom = $0
                        }
                        .transition(.opacity)

                    sheet(bottomInset: keyboardUp ? 0 : homeIndicatorInset)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.move(edge: .bottom))
                }

                if choosingStopID != nil {
                    crosshair
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let id = searchStopID, let stop = model.stops.first(where: { $0.id == id }) {
                    PlannerSearchOverlay(
                        role: model.role(of: stop),
                        offersCurrentLocation: model.offersCurrentLocation(for: id),
                        recents: recents,
                        onPick: { place in pick(place, for: id) },
                        onUseCurrentLocation: {
                            model.useCurrentLocation(for: id)
                            closeSearch()
                        },
                        onChooseOnMap: { startChoosingOnMap(for: id) },
                        onCancel: {
                            model.discardIfEmpty(id)
                            closeSearch()
                        },
                        searchCenter: mapTarget ?? model.userLocation?.coordinate,
                        route: model.role(of: stop) == .stop && model.hasRoute ? model.routeCoordinates : [],
                        measuresDetours: model.chosenStops.count == 2,
                        avoid: model.avoid,
                        initialCategory: searchCategory
                    )
                    .transition(.opacity)
                }
            }
        }
        .background {
            // The home indicator's inset, read where the keyboard can't change it.
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { homeIndicatorInset = $0 }
        }
        .dsAnimation(DS.Motion.standard, value: searchStopID)
        .dsAnimation(DS.Motion.standard, value: model.hasDestination)
        .dsAnimation(DS.Motion.standard, value: choosingStopID)
        .dsAnimation(DS.Motion.standard, value: droppedPin?.coordinate.latitude)
        .onAppear { model.locateUser() }
        // The opening view is the same one the recentre button gives: the rider, centred in the
        // part of the map between the top card and the sheet. That area isn't known until both
        // have been measured (and the rider's position can arrive after that), so re-centre as
        // each of them settles, until the rider moves the map themselves.
        .onChange(of: topChromeBottom) { _, _ in recenterOnUserIfIdle() }
        .onChange(of: mapBottomPadding) { _, _ in recenterOnUserIfIdle() }
        .onChange(of: model.userLocation?.coordinate.latitude) { _, _ in recenterOnUserIfIdle() }
    }

    // MARK: Map

    private var map: some View {
        GoogleMapView(
            routeCoords: model.routeCoordinates,
            pins: pins,
            cameraCommand: model.cameraCommand,
            isInteractive: true,
            onInteraction: { userMovedMap = true },
            alternativeRoutes: model.routes.map(\.coordinates),
            selectedRouteIndex: model.selectedRouteIndex,
            onSelectRoute: { index in
                DSHaptic.selection()
                model.selectRoute(index)
            },
            mapPadding: UIEdgeInsets(top: topChromeBottom + DS.Space.p2, left: 0,
                                     bottom: mapBottomPadding, right: 0),
            routeBubbles: routeBubbles,
            onLongPress: { dropPin(at: $0) },
            onTapMap: { _ in if droppedPin != nil { clearDroppedPin() } },
            onCameraIdle: { mapCameToRest(at: $0) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map"))
        .accessibilityValue(Text(routeSummary))
    }

    private func recenterOnUserIfIdle() {
        guard !userMovedMap, !model.hasDestination, searchStopID == nil, choosingStopID == nil,
              droppedPin == nil, model.userLocation != nil else { return }
        model.focusOnUser(animated: false)
    }

    private var pins: [MapPin] {
        var pins: [MapPin]
        if model.hasDestination {
            let chosen = model.chosenStops
            pins = chosen.enumerated().compactMap { i, stop in
                guard let coordinate = model.coordinate(of: stop) else { return nil }
                let style: MapPin.Style = i == 0 ? .lobbyStart
                    : (i == chosen.count - 1 ? .destination(name: model.name(of: stop)) : .waypoint(name: model.name(of: stop)))
                return MapPin(id: stop.id.uuidString, coordinate: coordinate, style: style)
            }
        } else if let me = model.userLocation?.coordinate {
            pins = [MapPin(id: "me", coordinate: me,
                           style: .simpleDot(color: UIColor(DS.Map.startMarker), size: 16), anchorBottom: false)]
        } else {
            pins = []
        }
        if let pin = droppedPin {
            pins.append(MapPin(id: "dropped", coordinate: pin.coordinate,
                               style: .simpleDot(color: UIColor(DS.Accent.base), size: 20), anchorBottom: false))
        }
        return pins
    }

    private var routeSummary: String {
        guard model.hasDestination else { return "" }
        var parts = model.chosenStops.map { model.name(of: $0) }
        if model.hasRoute {
            parts.append(RideDuration.inline(Int(model.durationSeconds)))
            parts.append(Self.distanceText(model.distanceMeters))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Top chrome

    @ViewBuilder
    private var topChrome: some View {
        if let id = choosingStopID {
            choosingPill(for: id)
        } else if model.hasDestination {
            PlannerStopsCard(
                model: model,
                onBack: { mode == .edit ? onClose() : model.clearDestination() },
                backLabel: mode == .edit ? "Back" : "Change destination",
                onEdit: { openSearch($0) },
                onAddStop: { if let id = model.addStop() { openSearch(id) } },
                isExpanded: $stopsExpanded
            )
        } else {
            searchPill
        }
    }

    /// The empty map's search, with the category chips under it.
    private var searchPill: some View {
        VStack(alignment: .leading, spacing: DS.Space.p1) {
            searchField
            PlannerCategoryChips(selected: nil, onSelect: { category in
                searchCategory = category
                openSearch(model.destinationID)
            }, onMap: true)
            .padding(.horizontal, -DS.Space.p3)
        }
    }

    private var searchField: some View {
        HStack(spacing: 0) {
            backButton(label: Text("Back"), action: onClose)
            Button { openSearch(model.destinationID) } label: {
                HStack(spacing: DS.Space.p2) {
                    Image(systemName: "magnifyingglass")
                        .dsIcon(DS.IconSize.md)
                        .foregroundStyle(DS.Text.muted)
                        .accessibilityHidden(true)
                    Text("Where are you riding?")
                        .dsText(.locationTitle)
                        .foregroundStyle(DS.Text.placeholder)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search for a destination"))
        }
        .padding(.trailing, DS.Space.p4)
        .dsGlass(in: Capsule(), interactive: true)
    }

    private func choosingPill(for id: UUID) -> some View {
        HStack(spacing: 0) {
            backButton(label: Text("Cancel")) { cancelChoosingOnMap() }
            Text(choosingPrompt(for: id))
                .dsText(.locationTitle)
                .foregroundStyle(DS.Text.primary)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
        .padding(.trailing, DS.Space.p4)
        .dsGlass(in: Capsule())
    }

    private func role(of id: UUID) -> PlannerStopRole {
        model.stops.first { $0.id == id }.map(model.role(of:)) ?? .stop
    }

    private func choosingPrompt(for id: UUID) -> LocalizedStringKey {
        switch role(of: id) {
        case .start:       "Move the map to the start"
        case .stop:        "Move the map to the stop"
        case .destination: "Move the map to the destination"
        }
    }

    /// The fixed pin for "Choose on map", its tip on the camera target: the centre of the map
    /// area left between the top chrome and the sheet, which is what the map padding defines.
    private var crosshair: some View {
        GeometryReader { geo in
            let top = topChromeBottom + DS.Space.p2
            let bottom = geo.size.height - mapBottomPadding
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(DS.Accent.base).frame(width: 30, height: 30)
                    Circle().fill(DS.Text.onAccent).frame(width: 10, height: 10)
                }
                Triangle().fill(DS.Accent.base).frame(width: 12, height: 8).offset(y: -1)
            }
            .dsShadow(DS.Shadow.card)
            // 37 pt of art: the tail's tip sits on the point.
            .position(x: geo.size.width / 2, y: (top + bottom) / 2 - 37 / 2)
        }
        .accessibilityHidden(true)
    }

    private func backButton(label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .dsIcon(DS.IconSize.md, weight: .semibold)
                .foregroundStyle(DS.Text.primary)
                .frame(width: DS.Target.minimum + DS.Space.p1, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Sheet

    private func sheet(bottomInset: CGFloat) -> some View {
        DSMapSheet(
            detent: $detent,
            bottomInset: bottomInset,
            onRestingHeightChange: { height in
                sheetRestingHeight = height
                if droppedPin == nil { mapBottomPadding = height }
            }
        ) {
            Group {
                if let id = choosingStopID {
                    chooseOnMapCard(for: id)
                } else if droppedPin != nil {
                    droppedPinCard
                } else if !model.hasDestination {
                    exploreHeader
                } else {
                    routeHeader
                }
            }
            .padding(.horizontal, DS.Space.screenInset)
            .padding(.bottom, DS.Space.p3)
        } content: {
            Group {
                if choosingStopID != nil || droppedPin != nil {
                    EmptyView()
                } else if !model.hasDestination {
                    recentRows(Array(recents.dropFirst(2)))
                } else {
                    detailsContent
                }
            }
            .padding(.horizontal, DS.Space.screenInset)
            .padding(.bottom, DS.Space.p6)
        } accessory: {
            DSFloatingButton(
                systemImage: model.hasRoute ? "arrow.up.left.and.arrow.down.right" : "location.fill",
                label: model.hasRoute ? "Show whole route" : "Show my location",
                variant: .accentIcon
            ) {
                if model.hasRoute { model.fitCameraToRoute() } else { model.focusOnUser() }
            }
        }
    }

    // Before a destination: an invitation and the last places the rider planned rides to.
    private var exploreHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.p1) {
            Text("Plan a ride")
                .dsText(.cardTitle)
                .foregroundStyle(DS.Text.primary)
                .accessibilityAddTraits(.isHeader)
            Text("Search for where the pack is heading.")
                .dsText(.bodySmall)
                .foregroundStyle(DS.Text.muted)
                .padding(.bottom, DS.Space.p2)
            recentRows(Array(recents.prefix(2)))
        }
    }

    private func recentRows(_ places: [PlaceResult]) -> some View {
        VStack(spacing: 0) {
            ForEach(places) { place in
                Button { pick(place, for: model.destinationID) } label: {
                    HStack(spacing: DS.Space.p3) {
                        Image(systemName: "clock")
                            .dsIcon(DS.IconSize.sm)
                            .foregroundStyle(DS.Text.muted)
                            .accessibilityHidden(true)
                        Text(place.name)
                            .dsText(.locationTitle)
                            .foregroundStyle(DS.Text.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let me = model.userLocation {
                            Text(Self.distanceText(me.distance(from: place.location)))
                                .dsText(.dataMono)
                                .foregroundStyle(DS.Text.muted)
                        }
                    }
                    .frame(minHeight: DS.Target.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { DSDivider() }
                .accessibilityHint(Text("Plans a ride to this place"))
            }
        }
    }

    // With a destination: the route at a glance, the ride's name, and the primary action.
    private var routeHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            HStack(alignment: .top, spacing: DS.Space.p2) {
                routeSummaryBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                moreMenu
            }
            titleRow
            primaryAction
        }
    }

    /// Destructive actions stay out of the way of the primary one: in a menu, behind a
    /// confirmation the host presents.
    @ViewBuilder
    private var moreMenu: some View {
        if let onDelete {
            Menu {
                Button("Delete ride", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .dsIcon(DS.IconSize.md, weight: .semibold)
                    .foregroundStyle(DS.Text.primary)
                    .frame(width: 36, height: 36)
                    .background(DS.Surface.field, in: Circle())
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More"))
        }
    }

    @ViewBuilder
    private var routeSummaryBlock: some View {
        if model.isRouting && !model.hasRoute {
            HStack(spacing: DS.Space.p2) {
                ProgressView().tint(DS.Accent.base)
                Text("Finding routes…").dsText(.body).foregroundStyle(DS.Text.secondary)
            }
            .frame(minHeight: 52, alignment: .leading)
        } else if model.routeFailed {
            VStack(alignment: .leading, spacing: DS.Space.p1) {
                Text("No route found").dsText(.rowTitle).foregroundStyle(DS.Text.primary)
                Text("Google couldn't find a road between these places. Try another destination or start.")
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.muted)
                Button("Try again") { model.recalculateRoute() }
                    .dsText(.link)
                    .foregroundStyle(DS.Accent.base)
                    .frame(minHeight: DS.Target.minimum)
            }
        } else if model.isWaitingForLocation {
            VStack(alignment: .leading, spacing: DS.Space.p1) {
                Text("Finding your location…").dsText(.rowTitle).foregroundStyle(DS.Text.primary)
                Text("Turn on Location Services for ConvoTrack, or choose a place instead.")
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.muted)
                Button("Choose a place") {
                    if let stop = model.stops.first(where: \.isCurrentLocation) { openSearch(stop.id) }
                }
                    .dsText(.link)
                    .foregroundStyle(DS.Accent.base)
                    .frame(minHeight: DS.Target.minimum)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.p2) {
                    Text(RideDuration.inline(Int(model.durationSeconds)))
                        .dsText(.metricValue)
                        .foregroundStyle(DS.Accent.base)
                    Text("(\(Self.distanceText(model.distanceMeters)))")
                        .dsText(.body)
                        .foregroundStyle(DS.Text.secondary)
                    if model.isRouting {
                        ProgressView().controlSize(.small).tint(DS.Accent.base)
                    }
                }
                Text(routeLabel)
                    .dsText(.bodySmall)
                    .foregroundStyle(DS.Text.muted)
                    // One line: a wrap would grow the resting sheet and nudge the map each time
                    // a different route is picked. The route list shows the full name.
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Which route is selected, and, while there's a choice, how to change it.
    /// Which route is selected and the road it takes, led by what it avoids.
    private var routeLabel: String {
        let avoiding: String? = switch (model.avoid.highways, model.avoid.tolls) {
        case (true, true):  String(localized: "No highways or tolls")
        case (true, false): String(localized: "No highways")
        case (false, true): String(localized: "No tolls")
        default:            nil
        }
        let stops = max(model.chosenStops.count - 2, 0)
        var parts: [String] = []
        if let avoiding { parts.append(avoiding) }
        if stops > 0 {
            parts.append(stops == 1 ? String(localized: "Via 1 stop") : String(localized: "Via \(stops) stops"))
            return parts.joined(separator: " · ")
        }
        let selected = model.routes.indices.contains(model.selectedRouteIndex) ? model.routes[model.selectedRouteIndex] : nil
        parts.append(selected.map(routeTag) ?? String(localized: "Best route"))
        if let summary = selected?.summary {
            parts.append(String(localized: "via \(summary)"))
        }
        return parts.joined(separator: " · ")
    }

    /// "Fastest route", or how much slower than the fastest.
    private func routeTag(_ option: RouteOption) -> String {
        let fastest = model.routes.map(\.durationSeconds).min() ?? option.durationSeconds
        let slower = Int(((option.durationSeconds - fastest) / 60).rounded())
        return slower <= 0 ? String(localized: "Fastest route") : String(localized: "\(slower) min slower")
    }

    // MARK: Alternatives

    /// The selected route's bubble reads its duration; the others read the difference from it,
    /// which is the number a rider is actually weighing.
    private var routeBubbles: [RouteBubble] {
        guard model.routes.count > 1, model.bubbleAnchors.count == model.routes.count else { return [] }
        let selected = model.durationSeconds
        return model.routes.indices.map { i in
            let isSelected = i == model.selectedRouteIndex
            let text: String
            if isSelected {
                text = RideDuration.inline(Int(model.routes[i].durationSeconds))
            } else {
                let delta = Int(((model.routes[i].durationSeconds - selected) / 60).rounded())
                text = delta == 0 ? String(localized: "Same time")
                    : delta > 0 ? "+\(delta) min" : "\u{2212}\(-delta) min"
            }
            return RouteBubble(routeIndex: i, coordinate: model.bubbleAnchors[i], text: text, isSelected: isSelected)
        }
    }

    /// The same choice as the bubbles, as a list: readable at any text size and reachable with
    /// VoiceOver, which can't touch a line on the map.
    @ViewBuilder
    private var routeList: some View {
        if model.routes.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                DSSectionHeading("Routes")
                    .padding(.bottom, DS.Space.p2)
                ForEach(Array(model.routes.enumerated()), id: \.element.id) { index, option in
                    routeRow(option, isSelected: index == model.selectedRouteIndex) {
                        DSHaptic.selection()
                        model.selectRoute(index)
                    }
                }
            }
        }
    }

    private var routeOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Route options")
                .padding(.bottom, DS.Space.p1)
            routeOptionToggle("Avoid highways", systemImage: "road.lanes", isOn: $model.avoid.highways)
            routeOptionToggle("Avoid tolls", systemImage: "banknote", isOn: $model.avoid.tolls)
        }
    }

    private func routeOptionToggle(_ title: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title).dsText(.body).foregroundStyle(DS.Text.primary)
            } icon: {
                // One width for every icon, so the labels line up whatever the glyph's shape.
                Image(systemName: systemImage).dsIcon(DS.IconSize.sm).foregroundStyle(DS.Text.muted)
                    .frame(width: DS.IconSize.lg)
            }
        }
        .tint(DS.Accent.base)
        .frame(minHeight: DS.Target.minimum)
        .overlay(alignment: .top) { DSDivider() }
    }

    private func routeRow(_ option: RouteOption, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.p3) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsIcon(DS.IconSize.md)
                    .foregroundStyle(isSelected ? AnyShapeStyle(DS.Accent.base) : AnyShapeStyle(DS.Text.subtle))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.p2) {
                        Text(RideDuration.inline(Int(option.durationSeconds)))
                            .dsText(.rowTitle)
                            .foregroundStyle(isSelected ? AnyShapeStyle(DS.Accent.base) : AnyShapeStyle(DS.Text.primary))
                        Text(Self.distanceText(option.distanceMeters))
                            .dsText(.bodySmall)
                            .foregroundStyle(DS.Text.secondary)
                    }
                    Text(option.summary.map { String(localized: "\(routeTag(option)) · via \($0)") } ?? routeTag(option))
                        .dsText(.helper)
                        .foregroundStyle(DS.Text.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DS.Space.p2)
            .frame(minHeight: DS.Target.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { DSDivider() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var titleRow: some View {
        HStack(spacing: DS.Space.p2) {
            HStack(spacing: DS.Space.p2) {
                Image(systemName: "pencil")
                    .dsIcon(DS.IconSize.sm)
                    .foregroundStyle(DS.Text.muted)
                    .accessibilityHidden(true)
                TextField("", text: $model.title, prompt: Text("Ride name").foregroundStyle(DS.Text.placeholder))
                    .dsText(.locationTitle)
                    .foregroundStyle(DS.Text.primary)
                    .tint(DS.Accent.base)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .accessibilityLabel(Text("Ride name"))
            }
            .padding(.horizontal, DS.Space.p3)
            .frame(minHeight: DS.Target.minimum + DS.Space.p1)
            .background(titleFocused ? DS.Surface.fieldFocused : DS.Surface.field,
                        in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(titleFocused ? AnyShapeStyle(DS.Border.focus) : AnyShapeStyle(DS.Border.default),
                            lineWidth: titleFocused ? DS.BorderWidth.focus : DS.BorderWidth.default)
            )

            // Shortcut to the rider limit, which lives further down the sheet.
            Button {
                titleFocused = false
                withAnimation(reduceMotion ? nil : DS.Motion.spring) { detent = .medium }
            } label: {
                HStack(spacing: DS.Space.p1) {
                    Image(systemName: "person.2.fill").dsIcon(DS.IconSize.sm)
                    Text("\(model.maxRiders)").dsText(.bodyStrong).monospacedDigit()
                }
                .foregroundStyle(DS.Text.primary)
                .padding(.horizontal, DS.Space.p3)
                .frame(minWidth: DS.Target.minimum, minHeight: DS.Target.minimum + DS.Space.p1)
                .background(DS.Surface.field, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Max riders, \(model.maxRiders)"))
            .accessibilityHint(Text("Shows the rider limit"))
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            DSDivider()
            routeList
            routeOptions
            RiderLimitSection(maxRiders: $model.maxRiders, riderCap: riderCap, isPremium: isPremium,
                              onUpgrade: onUpgrade)
        }
        .padding(.top, DS.Space.p1)
    }

    // MARK: Dropped pin

    private var droppedPinCard: some View {
        PlannerPlaceCard(eyebrow: "Dropped pin", candidate: droppedPin, actions: droppedPinActions,
                         onClose: clearDroppedPin)
    }

    /// With a route, the likely wish is a stop on the way; before one, it's where to ride to.
    private var droppedPinActions: [PlannerPlaceAction] {
        let setDestination = PlannerPlaceAction(id: "destination", title: "Set as destination", systemImage: "flag.fill") {
            usePin { model.choose($0, for: model.destinationID) }
        }
        let setStart = PlannerPlaceAction(id: "start", title: "Start here", systemImage: "location.fill") {
            usePin { model.choose($0, for: model.stops[0].id) }
        }
        guard model.hasDestination else { return [setDestination, setStart] }
        let endHere = PlannerPlaceAction(id: "destination", title: "End here", systemImage: "flag.fill") {
            usePin { model.choose($0, for: model.destinationID) }
        }
        guard model.canAddStop else { return [endHere, setStart] }
        let addStop = PlannerPlaceAction(id: "stop", title: "Add as stop", systemImage: "plus") {
            usePin { place in
                if let id = model.addStop() { model.choose(place, for: id) }
            }
        }
        return [addStop, setStart, endHere]
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        guard choosingStopID == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        titleFocused = false
        droppedPin = PlaceCandidate(coordinate: coordinate)
        withAnimation(reduceMotion ? nil : DS.Motion.spring) { detent = .low }
        lookUp(coordinate, after: .zero) { place in
            guard let pin = droppedPin, pin.coordinate.isSame(as: coordinate) else { return }
            droppedPin?.place = place
            droppedPin?.isResolving = false
        }
    }

    private func usePin(_ apply: (PlaceResult) -> Void) {
        guard let pin = droppedPin else { return }
        apply(pin.resolvedPlace)
        recents = RecentDestinations.load()
        clearDroppedPin()
    }

    private func clearDroppedPin() {
        geocodeTask?.cancel()
        droppedPin = nil
        mapBottomPadding = sheetRestingHeight
    }

    // MARK: Choose on map

    private func chooseOnMapCard(for id: UUID) -> some View {
        let (eyebrow, title, icon): (LocalizedStringKey, LocalizedStringKey, String) = switch role(of: id) {
        case .start:       ("Choose start", "Start here", "location.fill")
        case .stop:        ("Choose stop", "Add this stop", "plus")
        case .destination: ("Choose destination", "Set as destination", "flag.fill")
        }
        return PlannerPlaceCard(
            eyebrow: eyebrow,
            candidate: mapCenter,
            actions: [PlannerPlaceAction(id: "choose", title: title, systemImage: icon) { finishChoosingOnMap() }],
            onClose: cancelChoosingOnMap
        )
    }

    private func startChoosingOnMap(for id: UUID) {
        closeSearch()
        clearDroppedPin()
        mapCenter = nil
        choosingStopID = id
        detent = .low
        // Start from the stop's current spot, else the rider; moving the camera also reports
        // where it came to rest, which names the first spot.
        if let stop = model.stops.first(where: { $0.id == id }), let c = model.coordinate(of: stop) {
            model.cameraCommand = .focus(lat: c.latitude, lng: c.longitude, zoom: 15)
        } else if let c = model.userLocation?.coordinate {
            model.cameraCommand = .focus(lat: c.latitude, lng: c.longitude, zoom: 15)
        }
    }

    private func mapCameToRest(at target: CLLocationCoordinate2D) {
        mapTarget = target
        guard choosingStopID != nil else { return }
        mapCenter = PlaceCandidate(coordinate: target)
        lookUp(target, after: .milliseconds(250)) { place in
            guard let center = mapCenter, center.coordinate.isSame(as: target) else { return }
            mapCenter?.place = place
            mapCenter?.isResolving = false
        }
    }

    private func finishChoosingOnMap() {
        guard let id = choosingStopID, let center = mapCenter else { return }
        model.choose(center.resolvedPlace, for: id)
        recents = RecentDestinations.load()
        geocodeTask?.cancel()
        choosingStopID = nil
        mapCenter = nil
    }

    private func cancelChoosingOnMap() {
        guard let id = choosingStopID else { return }
        geocodeTask?.cancel()
        model.discardIfEmpty(id)
        choosingStopID = nil
        mapCenter = nil
        if model.hasRoute { model.fitCameraToRoute() }
    }

    /// Street name for a spot, a moment after the map settles so a pan doesn't fire a lookup per
    /// frame. A newer lookup cancels the one before.
    private func lookUp(_ coordinate: CLLocationCoordinate2D, after delay: Duration,
                        apply: @escaping (PlaceResult?) -> Void) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let place = await GooglePlacesService.reverseGeocode(coordinate)
            guard !Task.isCancelled else { return }
            apply(place)
        }
    }

    // MARK: Search

    private func openSearch(_ id: UUID) {
        titleFocused = false
        clearDroppedPin()
        searchStopID = id
    }

    private func closeSearch() {
        searchStopID = nil
        searchCategory = nil
    }

    private func pick(_ place: PlaceResult, for id: UUID) {
        model.choose(place, for: id)
        recents = RecentDestinations.load()
        detent = .low
        closeSearch()
    }

    private static func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }
}

private extension CLLocationCoordinate2D {
    func isSame(as other: CLLocationCoordinate2D) -> Bool {
        latitude == other.latitude && longitude == other.longitude
    }
}
