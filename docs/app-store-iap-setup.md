# App Store Connect — In-App Purchase Setup Guide

Follow these steps when you're ready to go live with ConvoTrack Pro subscriptions.

---

## Prerequisites

- Apple Developer Program membership ($99/year) — must be active
- Agreements, Tax, and Banking completed in App Store Connect (Payments & Financial Reports section)
- Bundle ID `danglingmind.convotrack` registered in the Apple Developer portal

---

## Step 1 — Register the Bundle ID (if not done)

1. Go to [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles → Identifiers
2. Click **+** → App IDs → App
3. Set Bundle ID: `danglingmind.convotrack`
4. Under Capabilities, check **In-App Purchase** ✓
5. Register

---

## Step 2 — Create the App in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+** → New App
2. Platform: iOS
3. Name: ConvoTrack
4. Bundle ID: `danglingmind.convotrack`
5. SKU: `convotrack-ios` (any unique string, internal only)
6. User Access: Full Access → Create

---

## Step 3 — Enable In-App Purchase Capability in Xcode

1. Open `convotrack.xcodeproj` in Xcode
2. Select the **convotrack** target → **Signing & Capabilities**
3. Click **+** → search **In-App Purchase** → Add
4. This adds the entitlement automatically (no code change needed)

---

## Step 4 — Create the Subscription Group

1. In App Store Connect → select the ConvoTrack app → **Monetization** → **Subscriptions**
2. Click **Create** next to Subscription Groups
3. Reference Name: `ConvoTrack Pro`
4. Save — note the Group ID (you'll need it for localizations)

---

## Step 5 — Add the Two Subscription Products

For each product below, click **+** inside the ConvoTrack Pro group:

### Monthly — `danglingmind.convotrack.membership.monthly`

| Field | Value |
|---|---|
| Reference Name | ConvoTrack Pro Monthly |
| Product ID | `danglingmind.convotrack.membership.monthly` |
| Price | $4.99 USD |
| Subscription Duration | 1 Month |
| Display Name (en-US) | ConvoTrack Pro Monthly |
| Description | Up to 25 riders, full ride history, and advanced analytics. |

### Yearly — `danglingmind.convotrack.membership.yearly`

| Field | Value |
|---|---|
| Reference Name | ConvoTrack Pro Yearly |
| Product ID | `danglingmind.convotrack.membership.yearly` |
| Price | $39.99 USD |
| Subscription Duration | 1 Year |
| Display Name (en-US) | ConvoTrack Pro Yearly |
| Description | Up to 25 riders, full ride history, and advanced analytics. Save 33% vs monthly. |

> **Critical**: the Product IDs must match exactly — the app hardcodes these strings.

---

## Step 6 — Add a Review Screenshot for Each Product

Apple requires a screenshot for IAP review. Use any screen that shows the paywall or a pro feature.
Size: 640×920 px minimum (any iOS screenshot works).

---

## Step 7 — Submit for Review

IAPs are reviewed alongside your first app submission (or a new app version):

1. Create a new version under the ConvoTrack app → **+** next to iOS App
2. In the **In-App Purchases** section of the version, add both subscriptions
3. Submit the version for review

Apple typically reviews in 1–3 days. IAPs enter **Ready for Sale** state automatically once the app version is approved.

---

## Step 8 — Test on a Real Device (before going live)

On TestFlight / a real device, StoreKit uses App Store Connect's **sandbox** environment automatically (no code change needed).

1. App Store Connect → Users & Access → **Sandbox Testers** → Add tester
2. On the device, sign out of the real App Store account (Settings → App Store → scroll down → sign out)
3. Run the app — it will prompt for a sandbox account at purchase time
4. Sandbox purchases are free and auto-renew every few minutes

---

## What changes in the code when you go live

**Nothing.** The product IDs, StoreKit 2 purchase flow, and server activation endpoint are all production-ready. The simulator uses `convotrack/convotrack.storekit` for local testing; real devices always use App Store Connect.

---

## Checklist

- [ ] Apple Developer membership active
- [ ] Tax & Banking forms completed in App Store Connect
- [ ] Bundle ID `danglingmind.convotrack` registered with In-App Purchase capability
- [ ] App created in App Store Connect
- [ ] In-App Purchase capability added in Xcode (Step 3)
- [ ] Subscription group "ConvoTrack Pro" created
- [ ] `danglingmind.convotrack.membership.monthly` product created at $4.99
- [ ] `danglingmind.convotrack.membership.yearly` product created at $39.99
- [ ] Review screenshots attached to each product
- [ ] App version submitted with both IAPs included
- [ ] Sandbox tester created and tested on real device
