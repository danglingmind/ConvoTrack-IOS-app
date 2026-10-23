import SwiftUI

// MARK: - Map sheet

enum DSMapSheetDetent: Int, CaseIterable {
    case low, medium, large

    var accessibilityName: Text {
        switch self {
        case .low:    Text("Collapsed")
        case .medium: Text("Half height")
        case .large:  Text("Full height")
        }
    }
}

/// A resizable sheet resting over a full-bleed map, like the route card in Maps: nonmodal, so
/// the map behind it keeps working, and never dismissed, only lowered.
///
/// `header` is always on screen and sets the low detent's height, so the resting sheet grows
/// with Dynamic Type instead of clipping. `content` scrolls beneath it once the sheet is raised.
/// Drag the grabber or header to resize; tap the grabber to step through the detents; VoiceOver
/// adjusts it like a slider (`sheets.md › Mobile`: "Include a grabber in a resizable sheet").
///
/// Drawn in the view rather than presented with `.sheet`: these screens also present the paywall
/// and alerts, and `sheets.md › Best practices` asks for one sheet at a time.
struct DSMapSheet<Header: View, Content: View, Accessory: View>: View {
    @Binding var detent: DSMapSheetDetent
    /// Space kept clear under the sheet's content: the home indicator, or 0 while the keyboard
    /// covers it.
    var bottomInset: CGFloat
    /// The low detent's full height, for map padding: the map keeps its logo and its camera
    /// framing above the sheet's lowest resting position (`maps.md › Best practices`).
    var onRestingHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    /// Floats just above the sheet's top edge, trailing (the map's recentre button). Hidden once
    /// the sheet is fully raised.
    @ViewBuilder var accessory: Accessory

    @State private var headerHeight: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    /// The content is scrolled to its top, so a downward drag on it belongs to the sheet.
    @State private var contentAtTop = true
    /// This drag started on the content and is resizing the sheet rather than scrolling.
    @State private var contentDragsSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var grabberHeight: CGFloat { 22 }

    var body: some View {
        GeometryReader { geo in
            let heights = detentHeights(available: geo.size.height)
            let resting = heights[detent.rawValue]
            let height = min(max(resting - dragTranslation, heights[0] * 0.85), heights[2])

            sheet(height: height, heights: heights)
                .overlay(alignment: .topTrailing) {
                    accessory
                        .padding(.trailing, DS.Space.p3)
                        .offset(y: -(DS.Target.minimum + DS.Space.p3))
                        .opacity(detent == .large ? 0 : 1)
                        .allowsHitTesting(detent != .large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .onChange(of: heights[0], initial: true) { _, low in onRestingHeightChange(low) }
        }
    }

    private func sheet(height: CGFloat, heights: [CGFloat]) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: DS.Radius.nav, topTrailingRadius: DS.Radius.nav,
                                           style: .continuous)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                grabber(heights: heights)
                header
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            }
            .contentShape(Rectangle())
            .gesture(resizeGesture(heights: heights))

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Below full height the content doesn't scroll: dragging it resizes the sheet, as in
            // Maps. At full height it scrolls, and pulling down from its top lowers the sheet.
            //
            // The drag outranks the rows under the finger at half height (otherwise lifting after a
            // drag would tap whichever row it started on), and merely accompanies the scroll view
            // at full height, where the scroll view's own pan already cancels a row's tap.
            // Scrolling is never switched off mid-drag: that cancels the pan and the tap leaks.
            .scrollDisabled(detent != .large)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 0.5 } action: { _, atTop in
                contentAtTop = atTop
            }
            .highPriorityGesture(contentResizeGesture(heights: heights), isEnabled: detent == .medium)
            .simultaneousGesture(contentResizeGesture(heights: heights), isEnabled: detent == .large)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .opacity(detent == .low && dragTranslation >= 0 ? 0 : 1)
            .accessibilityHidden(detent == .low)
        }
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(DS.Surface.sheet, in: shape)
        .overlay(shape.stroke(DS.Border.subtle, lineWidth: DS.BorderWidth.hairline))
        .clipShape(shape)
        .dsShadow(DS.Shadow.floating)
    }

    private func grabber(heights: [CGFloat]) -> some View {
        Capsule()
            .fill(DS.Text.subtle)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: Self.grabberHeight)
            .contentShape(Rectangle())
            .onTapGesture { step(detent == .large ? -2 : 1) }
            .accessibilityElement()
            .accessibilityLabel(Text("Sheet grabber"))
            .accessibilityValue(detent.accessibilityName)
            .accessibilityHint(Text("Swipe up or down to resize"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
    }

    /// Low fits the header; medium is half the space; large is all of it. Ascending, and each at
    /// least the one below it, so a tall header at an accessibility text size never inverts them.
    private func detentHeights(available: CGFloat) -> [CGFloat] {
        let low = min(Self.grabberHeight + headerHeight + bottomInset + DS.Space.p2, available)
        let medium = min(max(low, available * 0.52), available)
        return [low, medium, available]
    }

    private func contentResizeGesture(heights: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !contentDragsSheet && dragTranslation == 0 {
                    // Decided once, at the start: scrolling and resizing never trade places mid-drag.
                    guard detent != .large || (contentAtTop && value.translation.height > 0) else { return }
                    contentDragsSheet = true
                }
                guard contentDragsSheet else { return }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard contentDragsSheet else { return }
                contentDragsSheet = false
                settle(heights: heights, predictedEnd: value.predictedEndTranslation.height)
            }
    }

    private func resizeGesture(heights: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { dragTranslation = $0.translation.height }
            .onEnded { value in
                settle(heights: heights, predictedEnd: value.predictedEndTranslation.height)
            }
    }

    /// Rests on the detent nearest to where the drag was heading.
    private func settle(heights: [CGFloat], predictedEnd: CGFloat) {
        let resting = heights[detent.rawValue]
        let projected = resting - predictedEnd
        let nearest = heights.indices.min { abs(heights[$0] - projected) < abs(heights[$1] - projected) } ?? 0
        withAnimation(reduceMotion ? nil : DS.Motion.spring) {
            detent = DSMapSheetDetent(rawValue: nearest) ?? .low
            dragTranslation = 0
        }
    }

    private func step(_ delta: Int) {
        let next = min(max(detent.rawValue + delta, 0), DSMapSheetDetent.allCases.count - 1)
        guard let target = DSMapSheetDetent(rawValue: next), target != detent else { return }
        DSHaptic.selection()
        withAnimation(reduceMotion ? nil : DS.Motion.spring) { detent = target }
    }
}
