import SwiftUI

// MARK: - TextFieldCard

struct DSTextFieldCard: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var systemImage: String? = nil
    var isLoading = false
    var errorMessage: LocalizedStringKey? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            HStack(spacing: DS.Space.p3) {
                if let systemImage {
                    Image(systemName: systemImage).dsIcon(DS.IconSize.md).foregroundStyle(DS.Text.muted)
                        .accessibilityHidden(true)
                }
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DS.Text.placeholder))
                    .dsText(.input)
                    .foregroundStyle(DS.Text.primary)
                    .tint(DS.Accent.base)
                    .focused($focused)
                if isLoading { ProgressView().controlSize(.small).tint(DS.Accent.base) }
            }
            .padding(.horizontal, DS.Space.p4)
            .padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(focused ? DS.Surface.fieldFocused : DS.Surface.field,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(errorMessage != nil ? AnyShapeStyle(DS.Status.dangerBorder)
                            : focused ? AnyShapeStyle(DS.Border.focus) : AnyShapeStyle(DS.Border.default),
                            lineWidth: focused ? DS.BorderWidth.focus : DS.BorderWidth.default)
            )
            .dsShadow(focused ? DS.Shadow.focusGlow : DSShadow(color: .clear, y: 0, blur: 0))
            if let errorMessage { DSInlineError(message: errorMessage) }
        }
        .dsAnimation(DS.Motion.quick, value: focused)
    }
}

// MARK: - CodeInput

/// Invite code (A–Z 0–9, upper-cased while typing) or email OTP (digits, autofills from Mail/Messages).
struct DSCodeInput: View {
    enum Kind { case invite, emailOTP }

    @Binding var text: String
    var kind: Kind = .invite
    var length = 6
    var isVerifying = false
    @FocusState private var focused: Bool

    private var isComplete: Bool { text.count == length }

    var body: some View {
        HStack(spacing: DS.Space.p3) {
            TextField("", text: $text, prompt: Text(kind == .invite ? "A1B2C3" : "000000").foregroundStyle(DS.Text.placeholder))
                .dsText(kind == .invite ? .codeDisplay : .otpDisplay)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Text.primary)
                .tint(DS.Accent.base)
                .focused($focused)
                .keyboardType(kind == .invite ? .asciiCapable : .numberPad)
                .textContentType(kind == .emailOTP ? .oneTimeCode : nil)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: text) { _, new in
                    let allowed = kind == .invite ? new.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } : new.filter(\.isNumber)
                    let clipped = String(allowed.prefix(length))
                    if clipped != new { text = clipped }
                }
            if isVerifying {
                ProgressView().controlSize(.small).tint(DS.Accent.base)
            } else {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .dsIcon(DS.IconSize.lg)
                    .foregroundStyle(isComplete ? DS.Accent.base : DS.Text.subtle.base)
                    .accessibilityLabel(Text(isComplete ? "Code complete" : "Code incomplete"))
            }
        }
        .padding(.horizontal, DS.Space.p4)
        .frame(minHeight: kind == .invite ? 72 : 68)
        .background(focused ? DS.Surface.fieldFocused : DS.Surface.field,
                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isComplete ? AnyShapeStyle(DS.Accent.border)
                        : focused ? AnyShapeStyle(DS.Border.focus) : AnyShapeStyle(DS.Border.default),
                        lineWidth: focused ? DS.BorderWidth.focus : DS.BorderWidth.default)
        )
    }
}

// MARK: - LocationCard

struct DSLocationCard: View {
    enum Kind { case start, stop, destination }

    let kind: Kind
    let title: String
    var subtitle: String? = nil
    var isSelected = false
    var action: (() -> Void)? = nil

    private var icon: String {
        switch kind {
        case .start: "location.north.fill"
        case .stop: "mappin"
        case .destination: "flag.fill"
        }
    }

    var body: some View {
        let content = HStack(spacing: DS.Space.p3) {
            DSIconDisc(systemImage: icon, size: 40, iconSize: DS.IconSize.default)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsText(.locationTitle).foregroundStyle(DS.Text.primary).lineLimit(2)
                if let subtitle { Text(subtitle).dsText(.helper).foregroundStyle(DS.Text.muted).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.p3)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .dsSurfaceCard(.card, border: isSelected ? DS.Accent.border : DS.Border.default.base)
        .dsTimelineCardCenter()

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

struct DSAddStopButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle").dsIcon(18)
                Text("Add stop").dsText(.buttonWide)
            }
            .foregroundStyle(DS.Accent.base)
            .padding(.horizontal, 14)
            .frame(minHeight: DS.Target.minimum)
            .background(DS.Control.addStopFill, in: Capsule())
            .overlay(Capsule().stroke(DS.Border.strong, lineWidth: DS.BorderWidth.default))
            .contentShape(Capsule())
        }
        .buttonStyle(DSPressStyle(scale: 0.98))
    }
}

// MARK: - RouteTimeline (where the signature route line shows up in Create/Edit)

extension VerticalAlignment {
    private enum TimelineCardCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }
    /// The vertical centre of a timeline row's card, which its marker lines up with (not the
    /// centre of label + card, and not the centre of a dropdown opening below the card).
    static let timelineCardCenter = VerticalAlignment(TimelineCardCenter.self)
}

extension View {
    /// Marks this view as the card whose centre the timeline marker aligns to.
    func dsTimelineCardCenter() -> some View {
        alignmentGuide(.timelineCardCenter) { $0[VerticalAlignment.center] }
    }
}

private struct TimelineMarkerKey: PreferenceKey {
    static var defaultValue: [Anchor<CGPoint>] = []
    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value += nextValue()
    }
}

/// A rail through every marker. Each marker reports its centre, so the line joins them exactly
/// whatever the rows' heights (a card that grows with wrapped text, a dropdown that opens).
struct DSRouteTimeline<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .backgroundPreferenceValue(TimelineMarkerKey.self) { anchors in
                GeometryReader { proxy in
                    Path { path in
                        for (index, anchor) in anchors.enumerated() {
                            let point = proxy[anchor]
                            index == 0 ? path.move(to: point) : path.addLine(to: point)
                        }
                    }
                    .stroke(DS.Map.routeRail, lineWidth: 2)
                }
            }
    }
}

/// One row on the rail: marker on the left, field label and card on the right.
struct DSRouteTimelineRow<Card: View>: View {
    enum Marker { case start, stop, destination }

    let marker: Marker
    let label: LocalizedStringKey
    @ViewBuilder var card: Card

    private var markerColor: Color {
        switch marker {
        case .start: DS.Status.success
        case .stop: DS.Accent.deep
        case .destination: DS.Accent.base
        }
    }

    var body: some View {
        HStack(alignment: .timelineCardCenter, spacing: DS.Space.p3) {
            Circle()
                .fill(markerColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(DS.Background.base, lineWidth: 3))
                .anchorPreference(key: TimelineMarkerKey.self, value: .center) { [$0] }
                .alignmentGuide(.timelineCardCenter) { $0[VerticalAlignment.center] }
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(label).dsText(.fieldLabel).foregroundStyle(DS.Text.muted)
                card
            }
        }
    }
}

// MARK: - Stepper row (system Stepper, tinted) and route option chip

/// Max-riders style row. Uses the system `Stepper`; handlers (not a bound range) let the caller
/// turn the plan cap into a paywall instead of a dead button.
struct DSStepperRow: View {
    let title: LocalizedStringKey
    let value: Int
    var suffix: LocalizedStringKey = "riders"
    var onIncrement: () -> Void
    var onDecrement: () -> Void

    var body: some View {
        Stepper(onIncrement: onIncrement, onDecrement: onDecrement) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).dsText(.fieldLabel).foregroundStyle(DS.Text.secondary)
                Spacer(minLength: DS.Space.p2)
                Text("\(value)").dsText(.metricValue).foregroundStyle(DS.Text.primary)
                Text(suffix).dsText(.body).foregroundStyle(DS.Text.muted)
            }
        }
        .tint(DS.Accent.base)
        .padding(.horizontal, DS.Space.p4)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(DS.Surface.field, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Border.default, lineWidth: DS.BorderWidth.default))
    }
}

struct DSRouteOptionChip: View {
    let title: String
    let detail: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsText(.buttonPill).foregroundStyle(isSelected ? DS.Text.onAccent : DS.Text.primary.base)
                Text(detail).dsText(.helper).foregroundStyle(isSelected ? DS.Text.onAccent : DS.Text.muted.base)
            }
            .padding(.horizontal, DS.Space.p3)
            .padding(.vertical, DS.Space.p2)
            .frame(minHeight: DS.Target.minimum)
            .background(isSelected ? DS.Accent.base : DS.Surface.card.base, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : DS.Border.default.base, lineWidth: DS.BorderWidth.default))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

struct InputsGallery: View {
    @State private var title = ""
    @State private var code = "A1B"
    @State private var otp = ""
    @State private var riders = 5

    var body: some View {
        ZStack {
            DSScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.p4) {
                    DSTextFieldCard(placeholder: "e.g. Midnight Canyon Run", text: $title, systemImage: "pencil")
                    DSCodeInput(text: $code)
                    DSCodeInput(text: $otp, kind: .emailOTP)
                    DSRouteTimeline {
                        DSRouteTimelineRow(marker: .start, label: "Start location") {
                            DSLocationCard(kind: .start, title: "Current location", subtitle: "Indiranagar, Bengaluru")
                        }
                        DSRouteTimelineRow(marker: .stop, label: "Stop 1") {
                            DSLocationCard(kind: .stop, title: "Kanakapura Rd")
                        }
                        HStack { Spacer(); DSAddStopButton {}; Spacer() }
                        DSRouteTimelineRow(marker: .destination, label: "Destination") {
                            DSLocationCard(kind: .destination, title: "Nandi Hills", isSelected: true)
                        }
                    }
                    DSStepperRow(title: "Max riders", value: riders, onIncrement: { riders += 1 }, onDecrement: { riders -= 1 })
                    DSAdaptiveStack { DSRouteOptionChip(title: "Fastest", detail: "1h 12m", isSelected: true) {}; DSRouteOptionChip(title: "Scenic", detail: "1h 30m", isSelected: false) {} }
                }
                .padding(DS.Space.screenInset)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Inputs") { InputsGallery() }
#Preview("Inputs AX3") { InputsGallery().dynamicTypeSize(.accessibility3) }
