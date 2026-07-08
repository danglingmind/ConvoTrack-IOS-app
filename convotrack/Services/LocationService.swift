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
        manager.distanceFilter = 5          // fire every 5 m; ~0.15 s at 120 km/h
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
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - Private

    private func signalStrength() -> String {
        return "STRONG"
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location

        if !oneTimeLocationCallbacks.isEmpty {
            let callbacks = oneTimeLocationCallbacks
            oneTimeLocationCallbacks.removeAll()
            Task { @MainActor in callbacks.forEach { $0(location) } }
        }

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
        Task { @MainActor in cb?(heading) }
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
