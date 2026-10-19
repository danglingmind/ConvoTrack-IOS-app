# Store copy — 3-day free trial (approved 2026-10-19)

Facts every line below must stay true to (server is the source of truth):

- Every new account (one per device) gets **3 days free**, starting at first sign-in. No payment details.
- During those 3 days: up to **3 rides**, up to **5 riders per ride**.
- After the trial, **creating or joining a ride needs ConvoTrack Pro**. A ride already in progress can always be finished. History stays readable.
- Pro: unlimited rides, up to 25 riders (server `proPlan`), live stats and sync scores, 365-day history.
- Buying Pro during the trial starts the paid subscription **immediately**. There is no App Store / Play introductory trial.

---

## 1. App Store — description (en-US)

Replace the current `CONVOTRACK PRO` section and the paragraph under it in
`fastlane/metadata/en-US/description.txt` with:

```
3 DAYS FREE, THEN CONVOTRACK PRO
Every new account starts with 3 days free — up to 3 rides, up to 5 riders each, no payment details needed. After the free days, creating or joining rides needs ConvoTrack Pro. A ride you're already on can always be finished.

CONVOTRACK PRO
Unlimited rides, packs of up to 25 riders, live stats and sync scores, and a full 365-day ride history archive.

ConvoTrack Pro is an auto-renewable subscription, billed monthly or yearly. Payment is charged to your Apple Account at confirmation of purchase — subscribing during the free days starts the paid subscription right away. It renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel your subscription in your Apple Account settings.
```

## 2. App Store — promotional text (≤ 170 chars, can change without a release)

```
Start with 3 days free: track your whole group live on one map, regroup with a tap, get a full ride recap. Then go Pro for unlimited rides and packs of up to 25.
```
(161 chars)

## 3. App Store — What's New for the release that ships the trial

```
• New accounts now start with 3 days free. Your badge on Home shows how many days are left.
• After the free days, ConvoTrack Pro is needed to create or join rides — rides already in progress can always be finished.
• Your rider limit is shown while you plan a ride, and the lobby shows how full the pack is.
```

**Chosen: the existing-riders bullet below replaces the first bullet.** Existing riders: their 3 days start when the trial is switched on (not from their original sign-up), so the line "New accounts" undersells it for them. Alternative first bullet if you want existing riders addressed directly:

```
• Everyone gets 3 days free from today; new accounts get 3 days from sign-in. Your badge on Home shows how many days are left.
```

## 4. App Review notes (App Store Connect → App Review Information → Notes)

```
ConvoTrack has an app-level 3-day free trial that starts when a new account first signs in. It is not an App Store introductory offer and takes no payment details. During it a rider can join or create up to 3 rides of up to 5 riders. When it ends, creating or joining rides requires the ConvoTrack Pro auto-renewable subscription (monthly or yearly); viewing history and finishing a ride already in progress stay available.

Before the trial starts (right after sign-in) the app shows the trial length, what stops working when it ends, and the subscription prices. Every paywall can be closed with the X button. Buying during the trial starts the subscription immediately, and the paywall says so.

Demo account: <add review account email / password>. To see the post-trial state, contact <email> and we will expire the demo account's trial on request.
```

## 5. Google Play

**Short description (≤ 80 chars)**
```
Group ride tracker: live map, regroup & recap. 3 days free, then Pro.
```
(69 chars)

**Full description** — same section as §1, with the billing paragraph swapped:
```
ConvoTrack Pro is an auto-renewing subscription, billed monthly or yearly. Payment is charged to your Google Play account at confirmation of purchase — subscribing during the free days starts the paid subscription right away. It renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Google Play subscription settings.
```

**What's new (≤ 500 chars)** — same three bullets as §3.

## 6. Privacy disclosures (new in this release)

| Store | Add | Purpose | Linked | Tracking |
| --- | --- | --- | --- | --- |
| App Store privacy label | Identifiers → Device ID | App Functionality | Yes | No |
| App Store privacy label | Usage Data → Product Interaction | Analytics | Yes | No |
| Play data safety | Device or other IDs | App functionality, Fraud prevention | — | not shared |
| Play data safety | App activity → App interactions | Analytics | — | not shared |

Privacy policy addition: *"We store an identifier derived from your device to make sure each device gets one free trial. It is kept after you delete your account so the trial can't be restarted, and is not used for advertising or shared."*

## 7. After approval

1. ~~Apply §1–§3 to `en-US` and localize into the other 49 App Store locales~~ — done in `fastlane/metadata` (each locale keeps its own Pro heading and billing paragraph; `validate_metadata.py` passes).
2. Paste §4 into App Store Connect and §5 into Play Console (not in either repo).
3. Update the privacy labels/forms and the policy page (§6) before submitting.
