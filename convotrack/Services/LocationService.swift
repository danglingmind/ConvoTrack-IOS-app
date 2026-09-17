import Foundation
import CoreLocation
import UIKit

protocol LocationServiceDelegate: AnyObject {
    @MainActor
    func locationService(_ service: LocationService, didUpdate location: CLLocation, battery: Double, signalStrength: String)
}

final class LocationService: NSObject {
    static let shared = LocationService()

    weak var delegate: LocationServiceDelegate?
    var onHeadingUpdate: ((Double) -> Void)?

    private let manager = CLLocationManager()
    private(set) var lastLocation: CLLocation?
    private var oneTimeLocationCallbacks: [(CLLocation?) -> Void] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // No distance filter. It reads like a harmless rate cap, but `distanceFilter` gates
        // DELIVERY, not the GPS itself — CoreLocation withholds the callback until the device has
        // moved that far. At any riding speed 5 m is crossed every fix, so the filter changed
        // nothing while moving; the moment the rider stopped it silenced the delegate completely,
        // and everything downstream of a fix simply froze at its last value. The speed readout
        // stuck at whatever it read rolling up to the light, the ETA countdown stopped counting,
        // and the distance to the next turn held still — all until the rider pulled away and the
        // updates resumed. Full 1 Hz delivery is what a navigation app wants, and with
        // `BestForNavigation` the receiver is already running flat out either way, so this costs
        // callbacks, not battery.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - One-shot location

    func requestCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        if let last = lastLocation {
            completion(last)
            return
        }
        oneTimeLocationCallbacks.append(completion)
        manager.requestLocation()
    }

    // MARK: - Permission

    // Staged request, per Apple's guidance: ask for When-In-Use first, then
    // escalate to Always only once the user has already granted When-In-Use.
    // Calling this again after the first grant surfaces the Always upgrade prompt.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - Tracking

    func start() {
        // allowsBackgroundLocationUpdates throws NSInvalidArgumentException if UIBackgroundModes
        // doesn't include "location" — check the plist at runtime before enabling.
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
           modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            // Show the blue background-location indicator so users always know
            // tracking is active — expected by Guideline 2.5.4.
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        Task { @MainActor in self.syncHeadingOrientation() }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - Heading reference frame

    /// Keeps `headingOrientation` pointing at whichever edge of the phone the rider is actually
    /// looking "through".
    ///
    /// `CLHeading` is not reported relative to the phone's physical top — it is reported relative
    /// to whichever edge `headingOrientation` nominates, and that property defaults to
    /// `.portrait`, meaning the top. Nothing here ever set it, so the compass spent its whole life
    /// answering "where is the TOP OF THE PHONE pointing?" when the question navigation actually
    /// asks is "where is the RIDER pointing?". Those are the same question only while the screen
    /// is upright. Turn the phone sideways on the mount — either way round — and they differ by
    /// exactly 90°, so the heading-up camera and the direction chevron, which both read this one
    /// value, sat a quarter-turn askew for as long as the rider stayed in landscape.
    ///
    /// The reference is the *interface* orientation rather than `UIDevice.current.orientation`,
    /// for three reasons: it is the top of the UI that faces the way the rider is facing; it
    /// already respects a rotation lock, so a screen that stays portrait keeps a portrait heading
    /// instead of chasing a phone that merely tipped over; and it cannot report `.faceUp` or
    /// `.faceDown`, which are not headings at all and which a device-orientation reading would
    /// have to discard by hand.
    ///
    /// The two landscape cases cross over. UIKit defines
    /// `UIInterfaceOrientationLandscapeLeft == UIDeviceOrientationLandscapeRight` (and vice
    /// versa), and `CLDeviceOrientation` follows the *device* convention, so mapping the names
    /// straight across would leave landscape 180° out — a worse bug than the one being fixed,
    /// and one that looks correct in portrait testing.
    @MainActor
    private func syncHeadingOrientation() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return }

        let reference: CLDeviceOrientation
        switch scene.interfaceOrientation {
        case .portrait:             reference = .portrait
        case .portraitUpsideDown:   reference = .portraitUpsideDown
        case .landscapeLeft:        reference = .landscapeRight
        case .landscapeRight:       reference = .landscapeLeft
        default:
            // `.unknown` during a rotation transition. Hold the last good reference rather than
            // snapping back to portrait, which would flick the map a quarter-turn mid-rotation.
            return
        }

        guard manager.headingOrientation != reference else { return }
        manager.headingOrientation = reference
    }

    // MARK: - Private

    private func signalStrength() -> String {
        return "STRONG"
    }

    /// Whether a fix is good enough to steer navigation with.
    ///
    /// Everything downstream is debounced but nothing was ever filtered, so any fix
    /// `CLLocationManager` produced went straight into a 40 m off-route decision and onto the
    /// map as the rider's position. Three kinds are simply unusable:
    ///
    /// - `horizontalAccuracy < 0` is CoreLocation's explicit "this coordinate is invalid".
    /// - Beyond `maxUsableAccuracy` the fix cannot support a 40 m judgement at all. The bound is
    ///   deliberately loose so a tunnel or a deep urban canyon still moves the puck rather than
    ///   freezing it — this is aimed at the genuinely wild fix, not at merely mediocre ones.
    /// - A fix older than `maxFixAge` is the cached one iOS replays the moment updates start. It
    ///   can be minutes stale and hundreds of metres away, and handing it to the navigation
    ///   screen flagged the rider off-route and fired a reroute before they had moved at all.
    private static func isUsableForNavigation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxUsableAccuracy else { return false }
        return abs(location.timestamp.timeIntervalSinceNow) <= maxFixAge
    }

    private static let maxUsableAccuracy: CLLocationAccuracy = 100
    private static let maxFixAge: TimeInterval = 5
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // One-shot requests take whatever arrives, filtered or not. A coarse fix is perfectly
        // good enough for "what's starting near me", and dropping it here would strand the
        // caller's continuation waiting on a callback that never comes.
        if !oneTimeLocationCallbacks.isEmpty {
            let callbacks = oneTimeLocationCallbacks
            oneTimeLocationCallbacks.removeAll()
            Task { @MainActor in callbacks.forEach { $0(location) } }
        }

        guard Self.isUsableForNavigation(location) else { return }
        lastLocation = location

        guard let del = delegate else { return }
        let battery = Double(UIDevice.current.batteryLevel).clamped(to: 0...1)
        let signal = signalStrength()
        Task { @MainActor in
            del.locationService(self, didUpdate: location, battery: battery, signalStrength: signal)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let cb = onHeadingUpdate
        Task { @MainActor in
            // Re-checked per tick rather than driven off a rotation notification. The device
            // notification fires before UIKit has settled the new interface orientation, so a
            // one-shot handler reads the value it is trying to replace; polling here is immune to
            // that ordering, costs a couple of property reads a second, and self-heals within one
            // sample of any rotation.
            self.syncHeadingOrientation()
            cb?(heading)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !oneTimeLocationCallbacks.isEmpty {
            let callbacks = oneTimeLocationCallbacks
            oneTimeLocationCallbacks.removeAll()
            Task { @MainActor in callbacks.forEach { $0(nil) } }
        }
        print("[LocationService] \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            // Go through start() so allowsBackgroundLocationUpdates is enabled
            start()
        case .authorizedWhenInUse:
            // Foreground-only; background updates won't work.
            // The ride flow calls start() explicitly after the user begins a ride.
            manager.startUpdatingLocation()
            Task { @MainActor in self.syncHeadingOrientation() }
            manager.startUpdatingHeading()
        default:
            break
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
