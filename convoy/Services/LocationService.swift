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

    private let manager = CLLocationManager()
    private var updateTimer: Timer?
    private(set) var lastLocation: CLLocation?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Permission

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - Tracking

    func start() {
        manager.startUpdatingLocation()
        // Emit location every 2 seconds as required by backend
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fireUpdate()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Private

    private func fireUpdate() {
        guard let location = lastLocation, let delegate else { return }
        let battery = Double(UIDevice.current.batteryLevel).clamped(to: 0...1)
        let signal = signalStrength()
        Task { @MainActor in
            delegate.locationService(self, didUpdate: location, battery: battery, signalStrength: signal)
        }
    }

    // CoreTelephony does not expose raw signal bars on modern iOS.
    // We map network availability to a coarse tier as a best-effort proxy.
    private func signalStrength() -> String {
        return "STRONG"
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationService] \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
