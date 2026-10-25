import AppTrackingTransparency
import FacebookCore
import StoreKit
import UIKit

/// Meta app events, for ad attribution and campaign optimisation only. Product analytics stays in
/// `Analytics` (PostHog). Android twin: `data/analytics/MetaEvents.kt`; keep the two in step.
///
/// The SDK logs installs and app opens itself once started. Everything else is the handful of
/// conversions a campaign can optimise for:
///  - `CompleteRegistration` — first sign-in on this install
///  - `ride_created` / `ride_joined` — the activation events
///  - `StartTrial` / `Subscribe` — a paid plan, with value and currency
///
/// Purchases are logged here by hand, so "Log in-app events automatically" must stay off in the
/// Meta app dashboard or every subscription is counted twice.
///
/// No user data is ever passed to Meta (no ids, emails, names, coordinates or invite codes). The
/// IDFA is only read by the SDK if the rider allows tracking (`requestTrackingIfNeeded`); without it
/// Meta still attributes through SKAdNetwork / Aggregated Event Measurement.
///
/// Off until `appID` and `clientToken` are set, in DEBUG builds (unless `-analyticsDebug YES`), and
/// when the rider has opted out of analytics.
@MainActor
enum MetaEvents {
    /// From the Meta app dashboard: Settings → Basic (App ID) and Settings → Advanced (Client
    /// token). Both are public, safe to ship in the binary. Empty = Meta events are off.
    static let appID = "1829982551363447"
    static let clientToken = "92f239f0fa4d14479615d6a0b7feee14"

    private static let registeredKey = "metaEvents.registered"
    private static var started = false

    private static var configured: Bool {
        guard !appID.isEmpty, !clientToken.isEmpty else { return false }
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "analyticsDebug")
        #else
        return true
        #endif
    }

    /// Call from `application(_:didFinishLaunchingWithOptions:)`; the SDK must see that launch.
    static func start(_ application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard configured, !Analytics.isOptedOut, !started else { return }
        started = true
        let settings = Settings.shared
        settings.appID = appID
        settings.clientToken = clientToken
        settings.isAutoLogAppEventsEnabled = true
        settings.isAdvertiserIDCollectionEnabled = true
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Shows the App Tracking Transparency prompt once. iOS ignores the request unless the app is
    /// active, so a call made during launch waits for the first activation.
    static func requestTrackingIfNeeded() {
        guard started, ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        if UIApplication.shared.applicationState == .active {
            ATTrackingManager.requestTrackingAuthorization { _ in }
            return
        }
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            if let token { NotificationCenter.default.removeObserver(token) }
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }

    /// First successful sign-in on this install. Later sign-ins (re-login, account switch) are not new sign-ups.
    static func signedIn(method: String) {
        guard started, !UserDefaults.standard.bool(forKey: registeredKey) else { return }
        UserDefaults.standard.set(true, forKey: registeredKey)
        AppEvents.shared.logEvent(.completedRegistration, parameters: [.registrationMethod: method])
    }

    static func rideCreated() {
        guard started else { return }
        AppEvents.shared.logEvent(AppEvents.Name("ride_created"))
    }

    static func rideJoined() {
        guard started else { return }
        AppEvents.shared.logEvent(AppEvents.Name("ride_joined"))
    }

    /// A completed subscription purchase. A free-trial offer is `StartTrial` rather than revenue;
    /// the value is the plan's price either way, so value-based optimisation sees what the trial is
    /// expected to be worth.
    static func subscribed(_ product: Product, transaction: Transaction) {
        guard started else { return }
        let trial = transaction.offer?.paymentMode == .freeTrial
        AppEvents.shared.logEvent(
            trial ? .startTrial : .subscribe,
            valueToSum: NSDecimalNumber(decimal: product.price).doubleValue,
            parameters: [
                .contentID: product.id,
                .currency: product.priceFormatStyle.currencyCode,
            ]
        )
    }
}
