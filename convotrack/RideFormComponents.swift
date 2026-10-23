import SwiftUI
import CoreLocation

// Shared by Create Ride and Edit Ride: the route stop model, the place search field and the
// whole form body (title, route timeline, preview, metrics, max riders). Route calculation,
// saving and deleting stay in the two screens.

// MARK: - Route Stop Model

struct RouteStop: Identifiable {
    let id = UUID()
    var text: String = ""
    var place: PlaceResult? = nil
}

// MARK: - Stop Search Field

/// A place search that becomes a card once a place is chosen. Lives inside a timeline row, which
/// supplies the label, so `label` is only for use outside a timeline.
struct StopSearchField: View {
    let label: String
    let placeholder: LocalizedStringKey
    let icon: String
    let fieldID: String
    @Binding var text: String
    @Binding var place: PlaceResult?
    var onSelect: (() -> Void)? = nil
    var onResultsAppeared: ((String) -> Void)? = nil

    @State private var results: [PlaceResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !label.isEmpty {
                Text(LocalizedStringKey(label))
                    .dsText(.fieldLabel)
                    .foregroundStyle(DS.Text.secondary)
                    .padding(.bottom, DS.Space.p2)
            }

            if place != nil {
                confirmedRow
            } else {
                searchRow
                if !results.isEmpty {
                    dropdownResults
                        .id(fieldID + "_results")
                }
            }
        }
        .onChange(of: results) { _, newResults in
            if !newResults.isEmpty {
                onResultsAppeared?(fieldID + "_results")
            }
        }
    }

    /// The chosen place. Shared by Create Ride and Edit Ride, so both show the full name: a
    /// selected destination reading "Kempegowda International Airport Beng…" leaves the rider
    /// unable to confirm they picked the right one, which is the whole job of this row. Wraps
    /// rather than truncates, and the row grows with it instead of clipping.
    private var confirmedRow: some View {
        HStack(spacing: DS.Space.p3) {
            DSIconDisc(systemImage: icon, size: 40, iconSize: DS.IconSize.default)
            Text(place?.name ?? "")
                .dsText(.locationTitle)
                .foregroundStyle(DS.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.p2)
            Button {
                text = ""
                place = nil
                results = []
            } label: {
                Image(systemName: "xmark")
                    .dsIcon(DS.IconSize.sm, weight: .semibold)
                    .foregroundStyle(DS.Text.primary)
                    .frame(width: 26, height: 26)
                    .background(DS.Control.removeFill, in: Circle())
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Clear place"))
        }
        .padding(.leading, DS.Space.p3)
        .padding(.trailing, DS.Space.p1)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .dsSurfaceCard(.card, border: DS.Accent.border)
        .dsTimelineCardCenter()
    }

    private var searchRow: some View {
        HStack(spacing: DS.Space.p3) {
            Image(systemName: "magnifyingglass")
                .dsIcon(DS.IconSize.md)
                .foregroundStyle(DS.Text.muted)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DS.Text.placeholder))
                .dsText(.input)
                .foregroundStyle(DS.Text.primary)
                .tint(DS.Accent.base)
                .focused($focused)
                .onChange(of: text) { _, newValue in
                    searchTask?.cancel()
                    guard newValue.count >= 2 else { results = []; return }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        results = await GooglePlacesService.search(query: newValue, near: LocationService.shared.lastLocation)
                    }
                }
        }
        .padding(.horizontal, DS.Space.p4)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .background(focused ? DS.Surface.fieldFocused : DS.Surface.field,
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(focused ? AnyShapeStyle(DS.Border.focus) : AnyShapeStyle(DS.Border.default),
                        lineWidth: focused ? DS.BorderWidth.focus : DS.BorderWidth.default)
        )
        .dsTimelineCardCenter()
    }

    private var dropdownResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.prefix(4).enumerated()), id: \.offset) { index, item in
                Button {
                    text = item.name
                    place = item
                    results = []
                    onSelect?()
                } label: {
                    HStack(spacing: DS.Space.p3) {
                        Image(systemName: "mappin.circle.fill")
                            .dsIcon(DS.IconSize.sm)
                            .foregroundStyle(DS.Accent.base)
                        // Names wrap instead of truncating — a place name is the whole point of
                        // the row, and "Sri Krishna Temple Road Junc…" is not a choice you can make.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .dsText(.bodySmall)
                                .foregroundStyle(DS.Text.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let addr = item.formattedAddress, !addr.isEmpty {
                                Text(addr)
                                    .dsText(.helper)
                                    .foregroundStyle(DS.Text.muted)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let userLoc = LocationService.shared.lastLocation {
                            let dist = userLoc.distance(from: item.location)
                            Text(dist < 1000 ? "\(Int(dist)) m" : String(format: "%.1f km", dist / 1000))
                                .dsText(.dataMono)
                                .foregroundStyle(DS.Text.muted)
                                // Holds its width now that the name column is greedy.
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, DS.Space.p4)
                    .padding(.vertical, DS.Space.p3)
                    .frame(minHeight: DS.Target.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < min(results.count, 4) - 1 {
                    DSDivider().padding(.leading, 44)
                }
            }
        }
        .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
        .padding(.top, DS.Space.p1)
    }
}

// MARK: - Form

struct RideRouteForm: View {
    @Binding var title: String
    @Binding var startStop: RouteStop
    @Binding var middleStops: [RouteStop]
    @Binding var endStop: RouteStop
    @Binding var maxRiders: Int
    @Binding var scrollTarget: String?

    let riderCap: Int
    let isPremium: Bool
    let routeCoordinates: [CLLocationCoordinate2D]
    let routeAlternatives: [RouteOption]
    let selectedRouteIndex: Int
    let cameraCommand: MapCameraCommand?
    let confirmedStops: [PlaceResult]
    let distanceMeters: Double
    let durationSeconds: TimeInterval

    var onStopsChanged: () -> Void
    var onSelectRoute: (Int) -> Void
    var onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
            titleField
            routeSection
            previewSection
            ridersSection
        }
    }

    // MARK: Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: DS.Space.fieldGap) {
            Text("Ride title").dsText(.fieldLabel).foregroundStyle(DS.Text.secondary)
            DSTextFieldCard(placeholder: "e.g., Midnight Canyon Run", text: $title, systemImage: "pencil")
        }
    }

    // MARK: Route timeline

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Route")
            DSRouteTimeline {
                DSRouteTimelineRow(marker: .start, label: "Start location") {
                    StopSearchField(
                        label: "", placeholder: "Search start point…", icon: "location.north.fill", fieldID: "start",
                        text: $startStop.text, place: $startStop.place,
                        onSelect: onStopsChanged,
                        onResultsAppeared: { id in scrollTarget = id }
                    )
                }

                ForEach(Array($middleStops.enumerated()), id: \.element.id) { index, $stop in
                    DSRouteTimelineRow(marker: .stop, label: "Stop \(index + 1)") {
                        HStack(alignment: .top, spacing: DS.Space.p1) {
                            StopSearchField(
                                label: "", placeholder: "Search stop…", icon: "mappin", fieldID: "stop_\(stop.id)",
                                text: $stop.text, place: $stop.place,
                                onSelect: onStopsChanged,
                                onResultsAppeared: { id in scrollTarget = id }
                            )
                            // Outside the card, in the danger colour; 44 pt to tap.
                            Button {
                                middleStops.removeAll { $0.id == stop.id }
                                onStopsChanged()
                            } label: {
                                Image(systemName: "minus")
                                    .dsIcon(DS.IconSize.sm, weight: .bold)
                                    .foregroundStyle(DS.Surface.dangerContainer)
                                    .frame(width: 26, height: 26)
                                    .background(DS.Status.danger, in: Circle())
                                    .frame(width: DS.Target.minimum, height: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove stop \(index + 1)"))
                        }
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    DSAddStopButton { middleStops.append(RouteStop()) }
                    Spacer(minLength: 0)
                }

                DSRouteTimelineRow(marker: .destination, label: "Destination") {
                    StopSearchField(
                        label: "", placeholder: "Search destination…", icon: "flag.fill", fieldID: "destination",
                        text: $endStop.text, place: $endStop.place,
                        onSelect: onStopsChanged,
                        onResultsAppeared: { id in scrollTarget = id }
                    )
                }
            }
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Route preview")
            VStack(alignment: .leading, spacing: DS.Space.p3) {
                mapCard
                routeOptionChips
                DSAdaptiveStack(spacing: DS.Space.p3, verticalAlignment: .top) {
                    DSMetricCard(systemImage: "clock", label: "Est. time", value: durationText)
                    DSMetricCard(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: "Distance", value: distanceText)
                }
            }
        }
    }

    private var distanceText: String? {
        distanceMeters > 0 ? String(format: "%.1f km", distanceMeters / 1000) : nil
    }

    private var durationText: String? {
        guard durationSeconds > 0 else { return nil }
        return Self.durationString(Int(durationSeconds / 60))
    }

    private static func durationString(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var mapCard: some View {
        ZStack {
            routeMap
            if confirmedStops.count < 2 {
                ZStack {
                    Rectangle().fill(DS.Surface.cardQuiet)
                    VStack(spacing: DS.Space.p2) {
                        Image(systemName: "map").dsIcon(28).foregroundStyle(DS.Text.secondary)
                        Text("Add start & destination").dsText(.bodySmall).foregroundStyle(DS.Text.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Route preview map"))
        .accessibilityValue(Text(routeSummary))
    }

    /// Text summary of the route for the map (start, stops, destination, distance, time).
    private var routeSummary: String {
        let names = confirmedStops.map(\.name).joined(separator: ", ")
        return [names, distanceText, durationText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private var routeMap: some View {
        let stopPins: [MapPin] = confirmedStops.enumerated().map { index, stop in
            let isEnd = index == confirmedStops.count - 1
            let color: UIColor = isEnd
                ? UIColor(DS.Map.endMarker)
                : (index == 0 ? UIColor(DS.Map.startMarker) : UIColor(DS.Accent.base.opacity(0.6)))
            let size: CGFloat = isEnd ? 16 : 12
            return MapPin(id: "stop_\(index)", coordinate: stop.coordinate,
                          style: .simpleDot(color: color, size: size), anchorBottom: false)
        }
        return GoogleMapView(
            routeCoords:   routeCoordinates,
            pins:          stopPins,
            cameraCommand: cameraCommand,
            isInteractive: !routeAlternatives.isEmpty,   // enable taps to pick alternatives
            alternativeRoutes: routeAlternatives.map { $0.coordinates },
            selectedRouteIndex: selectedRouteIndex,
            onSelectRoute: onSelectRoute
        )
    }

    // Horizontally scrollable route options — shown only for a direct start→destination route
    // with more than one alternative. Tapping a chip (or the dim map line) selects it.
    @ViewBuilder
    private var routeOptionChips: some View {
        if routeAlternatives.count > 1 {
            let fastest = routeAlternatives.map(\.durationSeconds).min() ?? 0
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(routeAlternatives.enumerated()), id: \.element.id) { index, option in
                        let delta = Int((option.durationSeconds - fastest) / 60)
                        DSRouteOptionChip(
                            title: delta == 0 ? String(localized: "Fastest") : "+\(delta) \(String(localized: "min"))",
                            detail: "\(Self.durationString(Int(option.durationSeconds / 60))) · \(String(format: "%.1f km", option.distanceMeters / 1000))",
                            isSelected: index == selectedRouteIndex
                        ) { onSelectRoute(index) }
                    }
                }
            }
        }
    }

    // MARK: Max riders

    private var ridersSection: some View {
        RiderLimitSection(maxRiders: $maxRiders, riderCap: riderCap, isPremium: isPremium, onUpgrade: onUpgrade)
    }
}

// MARK: - Rider limit

/// Max riders stepper with the plan's limit under it. Shared by the route form and the ride
/// planner's sheet.
struct RiderLimitSection: View {
    @Binding var maxRiders: Int
    let riderCap: Int
    let isPremium: Bool
    var onUpgrade: () -> Void

    private var atRiderCap: Bool { maxRiders >= riderCap && !isPremium }

    /// The limit is always visible, not only once the rider walks into it. Free riders get a quiet
    /// way into the paywall; Pro riders just see what their plan allows.
    @ViewBuilder private var riderPlanLine: some View {
        if isPremium {
            Label { Text("Pro · up to \(riderCap) riders") } icon: { Image(systemName: "rosette") }
                .dsText(.helper)
                .foregroundStyle(DS.Text.muted)
        } else {
            Button(action: onUpgrade) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").dsIcon(11, weight: .semibold)
                    Text("Up to \(riderCap) riders on your plan").foregroundStyle(DS.Text.muted)
                    Text("Bigger packs with Pro").foregroundStyle(DS.Pro.gradient)
                }
                .dsText(.helper)
                .frame(minHeight: DS.Target.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Text.muted)
            .accessibilityHint(Text("Shows ConvoTrack Pro plans"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            DSStepperRow(
                title: "Max riders",
                value: maxRiders,
                onIncrement: {
                    if maxRiders < riderCap {
                        maxRiders += 1
                    } else if !isPremium {
                        onUpgrade()
                    }
                },
                onDecrement: { if maxRiders > 2 { maxRiders -= 1 } }
            )
            if atRiderCap {
                DSPromoBanner(eyebrow: "ConvoTrack Pro", message: "Pro unlocks bigger packs", actionTitle: "Go Pro", goProStyle: true, action: onUpgrade)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                riderPlanLine
            }
        }
        .dsAnimation(.spring(response: 0.3, dampingFraction: 0.8), value: atRiderCap)
    }
}
