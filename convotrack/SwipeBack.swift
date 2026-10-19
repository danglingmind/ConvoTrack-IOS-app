import SwiftUI
import UIKit

/// Edge-swipe-back for every pushed screen.
///
/// SwiftUI's `navigationBarBackButtonHidden(true)` (used by the lobby and the summary, which draw
/// their own back controls) and a hidden navigation bar (live navigation) both switch off UIKit's
/// interactive pop gesture as a side effect. This puts the gesture back everywhere, and lets a
/// screen opt out on purpose with `.swipeBackDisabled()`.
enum SwipeBack {
    /// Visible screens that forbid swiping back. The gesture is off while this is above zero.
    fileprivate(set) static var blockers = 0
}

private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard SwipeBack.blockers == 0 else { return false }
        // The pop gesture lives on the navigation controller's view. At the root there is nothing
        // to pop to, and letting it begin there freezes the stack.
        let nav = gesture.view?.next as? UINavigationController
        return (nav?.viewControllers.count ?? 0) > 1
    }
}

extension UINavigationController {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
    }
}

private struct SwipeBackBlocker: ViewModifier {
    let disabled: Bool
    @State private var isCounted = false

    func body(content: Content) -> some View {
        content
            .onAppear { sync(disabled) }
            .onChange(of: disabled) { _, now in sync(now) }
            .onDisappear { sync(false) }
    }

    /// Keeps the shared counter balanced however often the screen appears or the flag flips.
    private func sync(_ shouldBlock: Bool) {
        if shouldBlock && !isCounted {
            SwipeBack.blockers += 1
            isCounted = true
        } else if !shouldBlock && isCounted {
            SwipeBack.blockers -= 1
            isCounted = false
        }
    }
}

extension View {
    /// Turns the edge-swipe-back gesture off while this screen is visible. Live navigation uses it
    /// so a stray swipe can't drop a rider out of guidance; the post-ride summary uses it because
    /// "back" would land on a ride that has already ended.
    func swipeBackDisabled(_ disabled: Bool = true) -> some View {
        modifier(SwipeBackBlocker(disabled: disabled))
    }
}
