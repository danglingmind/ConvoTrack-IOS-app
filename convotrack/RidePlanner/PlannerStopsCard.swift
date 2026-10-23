import SwiftUI

/// The planner's top card once a destination is chosen: every stop in riding order, each one
/// tappable to choose again. Swap for a two-stop ride; with stops between, drag handles and
/// remove buttons. Long lists fold to start, "N stops", destination so the card doesn't bury
/// the map.
struct PlannerStopsCard: View {
    @ObservedObject var model: RidePlannerModel
    var onBack: () -> Void
    var onEdit: (UUID) -> Void
    var onAddStop: () -> Void
    /// Owned by the planner: the card leaves the screen while a search is open, and the list
    /// should still be open when it comes back with the stop just added.
    @Binding var isExpanded: Bool

    @State private var draggingID: UUID?
    /// How far the dragged row sits from its current slot.
    @State private var dragOffset: CGFloat = 0
    /// Translation already spent on moving the row to a new slot during this drag.
    @State private var dragConsumed: CGFloat = 0
    @State private var rowHeight: CGFloat = DS.Target.minimum
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var rowSpacing: CGFloat { DS.Space.p1 }
    private var rowPitch: CGFloat { rowHeight + Self.rowSpacing }

    /// Folded once there are two or more stops between start and destination, until the rider
    /// opens the list.
    private var isFolded: Bool { model.stops.count > 3 && !isExpanded }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            backButton
            VStack(spacing: Self.rowSpacing) {
                if isFolded, let first = model.stops.first, let last = model.stops.last {
                    row(first, editable: false)
                    foldedRow
                    row(last, editable: false)
                } else {
                    ForEach(model.stops) { stop in
                        row(stop, editable: model.canRemoveStops)
                    }
                }
                footer
            }
            if model.stops.count == 2 {
                swapButton
                    .frame(height: rowHeight * 2 + Self.rowSpacing)
            }
        }
        .padding(.vertical, DS.Space.p2)
        .padding(.trailing, DS.Space.p2)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsAnimation(DS.Motion.spring, value: model.stops.map(\.id))
        .dsAnimation(DS.Motion.standard, value: isFolded)
    }

    // MARK: Rows

    private func row(_ stop: PlannerStop, editable: Bool) -> some View {
        let role = model.role(of: stop)
        let isDragging = draggingID == stop.id
        return HStack(spacing: 0) {
            Button { onEdit(stop.id) } label: {
                HStack(spacing: DS.Space.p3) {
                    PlannerStopMarker(role: role)
                    Text(stop.isChosen ? model.name(of: stop) : placeholder(for: role))
                        .dsText(.body)
                        .foregroundStyle(stop.isChosen ? AnyShapeStyle(DS.Text.primary) : AnyShapeStyle(DS.Text.placeholder))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DS.Space.p3)
                .frame(minHeight: DS.Target.minimum)
                .background(isDragging ? AnyShapeStyle(DS.Surface.fieldFocused) : AnyShapeStyle(DS.Surface.field),
                            in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityLabel(stop, role: role)))
            .accessibilityHint(Text("Choose a different place"))

            if editable {
                dragHandle(stop)
                removeButton(stop, role: role)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .offset(y: isDragging ? dragOffset : 0)
        // The dragged row tracks the finger: when it changes slot, its new layout position and
        // the offset that cancels it out land together, without an animation between them.
        .transaction { if isDragging { $0.animation = nil } }
        .zIndex(isDragging ? 1 : 0)
        .dsShadow(isDragging ? DS.Shadow.floating : DSShadow(color: .clear, y: 0, blur: 0))
        .accessibilityActions {
            if editable {
                if role != .start {
                    Button("Move up") { move(stop.id, by: -1) }
                }
                if role != .destination {
                    Button("Move down") { move(stop.id, by: 1) }
                }
                Button("Remove") { model.removeStop(stop.id) }
            }
        }
    }

    private func placeholder(for role: PlannerStopRole) -> String {
        switch role {
        case .start:       String(localized: "Choose a start point")
        case .stop:        String(localized: "Add a stop")
        case .destination: String(localized: "Choose a destination")
        }
    }

    private func accessibilityLabel(_ stop: PlannerStop, role: PlannerStopRole) -> String {
        let name = stop.isChosen ? model.name(of: stop) : placeholder(for: role)
        switch role {
        case .start:       return String(localized: "Start, \(name)")
        case .destination: return String(localized: "Destination, \(name)")
        case .stop:
            let number = (model.stops.firstIndex { $0.id == stop.id } ?? 1)
            return String(localized: "Stop \(number), \(name)")
        }
    }

    private var foldedRow: some View {
        Button { isExpanded = true } label: {
            HStack(spacing: DS.Space.p3) {
                Image(systemName: "ellipsis")
                    .dsIcon(DS.IconSize.sm, weight: .semibold)
                    .foregroundStyle(DS.Text.muted)
                    .frame(width: DS.IconSize.sm)
                Text("\(model.stops.count - 2) stops")
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
                Spacer(minLength: DS.Space.p2)
                Text("Show all")
                    .dsText(.link)
                    .foregroundStyle(DS.Accent.base)
            }
            .padding(.horizontal, DS.Space.p3)
            .frame(minHeight: DS.Target.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(model.stops.count - 2) stops on the way"))
        .accessibilityHint(Text("Shows every stop"))
    }

    private var footer: some View {
        HStack(spacing: DS.Space.p2) {
            if model.canAddStop {
                Button {
                    isExpanded = true
                    onAddStop()
                } label: {
                    Label("Add stop", systemImage: "plus")
                        .dsText(.link)
                        .foregroundStyle(DS.Accent.base)
                        .padding(.horizontal, DS.Space.p3)
                        .frame(minHeight: DS.Target.minimum - DS.Space.p2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if model.stops.count > 3 && isExpanded {
                Button("Done") { isExpanded = false }
                    .dsText(.link)
                    .foregroundStyle(DS.Text.secondary)
                    .padding(.horizontal, DS.Space.p3)
                    .frame(minHeight: DS.Target.minimum - DS.Space.p2)
                    .accessibilityHint(Text("Folds the stop list"))
            }
        }
    }

    // MARK: Controls

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .dsIcon(DS.IconSize.md, weight: .semibold)
                .foregroundStyle(DS.Text.primary)
                .frame(width: DS.Target.minimum + DS.Space.p1, height: DS.Target.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Change destination"))
    }

    private var swapButton: some View {
        Button {
            DSHaptic.selection()
            model.swapEnds()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .dsIcon(DS.IconSize.md, weight: .semibold)
                .foregroundStyle(DS.Text.primary)
                .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Swap start and destination"))
    }

    private func removeButton(_ stop: PlannerStop, role: PlannerStopRole) -> some View {
        Button {
            DSHaptic.selection()
            model.removeStop(stop.id)
        } label: {
            Image(systemName: "xmark")
                .dsIcon(DS.IconSize.sm, weight: .semibold)
                .foregroundStyle(DS.Text.secondary)
                .frame(width: DS.Target.minimum - DS.Space.p1, height: DS.Target.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove \(model.name(of: stop))"))
    }

    /// Drag to reorder. The row follows the finger and the list re-orders under it a slot at a
    /// time, so the rest of the card shows where it will land; the route is asked for once, on
    /// release.
    private func dragHandle(_ stop: PlannerStop) -> some View {
        Image(systemName: "line.3.horizontal")
            .dsIcon(DS.IconSize.sm, weight: .semibold)
            .foregroundStyle(DS.Text.muted)
            .frame(width: DS.Target.minimum - DS.Space.p1, height: DS.Target.minimum)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if draggingID != stop.id {
                            draggingID = stop.id
                            dragConsumed = 0
                            DSHaptic.selection()
                        }
                        var offset = value.translation.height - dragConsumed
                        let index = model.stops.firstIndex { $0.id == stop.id } ?? 0
                        if offset > rowPitch / 2, index < model.stops.count - 1 {
                            step(stop.id, by: 1)
                            dragConsumed += rowPitch
                            offset -= rowPitch
                        } else if offset < -rowPitch / 2, index > 0 {
                            step(stop.id, by: -1)
                            dragConsumed -= rowPitch
                            offset += rowPitch
                        }
                        dragOffset = offset
                    }
                    .onEnded { _ in
                        withAnimation(reduceMotion ? nil : DS.Motion.spring) {
                            draggingID = nil
                            dragOffset = 0
                        }
                        dragConsumed = 0
                        model.finishReorder()
                    }
            )
            .accessibilityHidden(true)
    }

    private func step(_ id: UUID, by delta: Int) {
        DSHaptic.selection()
        withAnimation(reduceMotion ? nil : DS.Motion.spring) {
            model.moveStop(id, by: delta, reroute: false)
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        withAnimation(reduceMotion ? nil : DS.Motion.spring) {
            model.moveStop(id, by: delta)
        }
    }
}

/// Start dot, stop ring, destination flag: the same marks as the map's pins.
struct PlannerStopMarker: View {
    let role: PlannerStopRole

    var body: some View {
        Group {
            switch role {
            case .start:
                Circle().fill(DS.Map.startMarker).frame(width: 10, height: 10)
            case .stop:
                Circle().fill(DS.Map.stopMarker)
                    .overlay(Circle().stroke(DS.Accent.base, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            case .destination:
                Image(systemName: "flag.fill").dsIcon(DS.IconSize.xs).foregroundStyle(DS.Accent.base)
            }
        }
        .frame(width: DS.IconSize.sm)
        .accessibilityHidden(true)
    }
}
