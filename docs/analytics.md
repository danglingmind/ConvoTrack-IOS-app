# Product analytics (PostHog)

One tool, three emitters. The **backend** records what actually happened (rides, safety, revenue),
the **apps** record what the rider did on screen (onboarding, sharing, permissions, sign-in), and
PostHog joins them on one rider id.

| Emitter | Code | Sends |
| --- | --- | --- |
| Backend | `convoy-backend/src/services/analytics.ts` | ride lifecycle, safety, subscription, account, **and the paywall funnel** (forwarded from `POST /events`) |
| iOS | `convotrack/Services/Analytics.swift` | interface events |
| Android | `app/.../data/analytics/Analytics.kt` | interface events (no onboarding events: Android has no onboarding flow) |

Paywall events (`paywall_*`, `nudge_*`, `home_card_dismissed`) are **not** sent by the apps to PostHog.
They keep going to `POST /events` (which also stores them in `paywall_events`) and the backend
forwards them. One path, so nothing is counted twice.

## Turning it on

Nothing is sent until a key is set. The PostHog project API key is public and write-only, the same
class of value as the Clerk publishable key and the Maps key.

1. Create a PostHog Cloud project. **Pick the region once** (US or EU); it can't be changed. The host
   is `https://us.i.posthog.com` or `https://eu.i.posthog.com`.
2. **Backend:** set `POSTHOG_API_KEY` (and `POSTHOG_HOST` if EU) on Render, redeploy.
3. **iOS:** set `Analytics.apiKey` / `Analytics.host` in `Services/Analytics.swift`.
4. **Android:** add `POSTHOG_API_KEY=` and `POSTHOG_HOST=` to `local.properties` (and CI env for release builds).
5. Debug builds send nothing by default. iOS: launch with `-analyticsDebug YES`. Android: set
   `Analytics.debugEnabled = true`. Use a separate PostHog project for that, or filter `$lib` + build.
6. Update **App Store privacy labels** (Product Interaction, Identifiers → User ID, linked to the user,
   not used for tracking) and the **Play Data safety** form to match. No ATT prompt is needed: nothing
   is shared with third parties for advertising and the id is first-party.

## Identity

- Before sign-in: a random per-install id (`analytics.anonId`), not the Keychain trial-device id.
- On sign-in: `$identify` merges that id into the **Clerk user id**, which is also what the backend
  uses. So onboarding → sign-up → first ride is one continuous journey.
- On sign-out: a fresh anonymous id starts.
- Never send: coordinates, place or ride names, invite codes, names, emails, phone numbers.
  Counts, enums, rounded distances only.

## Super-properties (on every event)

`platform` (ios/android), `$app_version`, `$app_build`, `$os`, `$os_version`, `$locale`, `source`
(client/server), `access` (pro / trial / trialExpired / free, client events only).
Server events carry the plan in `plan` where it matters.

## Event taxonomy

Names are past tense, `snake_case`. Add an event in **all** places: this table, `Analytics.Event`
(iOS), `Analytics.Event` (Android), or `capture(...)` on the server.

### Acquisition and onboarding
| Event | From | Properties | Meaning |
| --- | --- | --- | --- |
| `app_opened` | iOS, Android | `cold` | App launched or foregrounded |
| `onboarding_step_viewed` | iOS | `step`, `of` | A page of the intro was shown |
| `pack_size_selected` | iOS | `pack_size` (duo/small/medium/large/unsure/skipped) | Answered "how big is your group" |
| `onboarding_completed` | iOS | `last_step` | Reached the end or skipped |
| `sign_in_started` / `sign_in_succeeded` / `sign_in_failed` | iOS, Android | `method` (google/apple/email) | Auth funnel |
| `signed_up` | server | | First time the backend saw this rider. **The one true sign-up event.** |
| `signed_out` | iOS, Android | | |
| `account_deleted` | server | | |

### Core loop: rides
| Event | From | Properties |
| --- | --- | --- |
| `ride_created` | server | `distance_km`, `est_duration_min`, `waypoint_count`, `max_riders`, `plan` |
| `ride_joined` | server | `rider_count` (after joining), `rejoin`, `plan` |
| `ride_started` | server | `rider_count`, `distance_km`, `lobby_minutes` |
| `ride_ended` | server | `duration_min`, `rider_count`, `distance_km`, `max_split_km`, `server_state_lost` |
| `ride_completed` | server | `duration_min`, `rider_count`, `is_leader`. **One per rider still in the ride when it ends**, so joiners count too. Use this for "took part in a ride" retention and the north star |
| `ride_left` / `rider_removed` / `ride_deleted` | server | `ride_status` |
| `create_ride_failed` | iOS, Android | `plan_limit` |
| `join_failed` | iOS, Android | `reason` (server error code, or `request_failed`) |

### Virality (the invite loop)
| Event | From | Properties |
| --- | --- | --- |
| `invite_share_opened` | iOS, Android | `method` (link/qr). Intent: the share sheet or QR was opened, not that a message was sent |
| `deep_link_opened` | iOS, Android | `kind` (join/ride) |
| `join_sheet_opened` | iOS, Android | `prefilled` |
| `qr_scan_opened` | Android | |

### In-ride safety and quality
| Event | From | Properties |
| --- | --- | --- |
| `regroup_called` | server | `reason` (FUEL/FOOD/SCENIC), `rider_count`, `by_leader` |
| `emergency_raised` | server | `rider_count`, `by_leader`, `has_message` |
| `group_split_detected` | server | `gap_km`, `rider_count` (attributed to the leader) |
| `voice_mute_toggled` | iOS, Android | `muted` |
| `permission_result` | iOS, Android | `kind` (location/camera), `status` |
| `ride_summary_viewed` | iOS, Android | `post_ride` (iOS only) |
| `ride_summary_shared` | iOS, Android | `post_ride` (iOS only) |
| `screen_viewed` | iOS, Android | `screen` (`tab_history` / `tab_home` / `tab_profile`) |

### Monetization
| Event | From | Properties |
| --- | --- | --- |
| `paywall_shown` | server (forwarded) | `source_screen`, `access`, `platform`, `app_version` |
| `paywall_purchase_started` | server (forwarded) | same |
| `paywall_converted` | server (forwarded) | same. Client-reported |
| `paywall_dismissed`, `nudge_shown`, `nudge_dismissed`, `home_card_dismissed` | server (forwarded) | same |
| `subscription_activated` | server | `provider`, `product_id`, `environment`; sets person property `plan=pro` |

**Revenue truth is `subscription_activated`**, not `paywall_converted`. It fires after the receipt or
Play token is verified. It can fire more than once per purchase (restore, re-activate), so count
**distinct users**, never events. Filter out `environment = Sandbox`.

## What to measure

**North-star metric: Weekly Group Rides**, i.e. distinct rides per week with `ride_ended` and
`rider_count >= 2`. For rider-level retention use `ride_completed` as the return event. It rises only when riders invite riders and rides actually happen.

### AARRR

| Stage | Metric | How |
| --- | --- | --- |
| Acquisition | Installs → `signed_up`, by `$locale` and platform | Trend of `signed_up` |
| Activation | **% of new riders who finish a ride with 2+ riders within 7 days** | Funnel below |
| Retention | Weekly retention of riders who ended a ride | Retention insight: start `signed_up`, return `ride_started` or `ride_joined` |
| Revenue | Trial → Pro conversion, time to convert, revenue by plan | Funnel + `subscription_activated` |
| Referral | Invites per ride leader, invite → join conversion | Funnel below |

### Funnels to build first (PostHog → Product analytics → Funnels)

1. **Activation:** `signed_up` → (`ride_created` or `ride_joined`) → `ride_started` → `ride_ended`. Window 7 days.
   Break down by `platform`, by first action (leader vs joiner), by `pack_size`.
2. **Invite loop:** `ride_created` → `invite_share_opened` → *(other rider)* `deep_link_opened` →
   `ride_joined`. The cross-rider step can't be a single-user funnel; track it as two trends
   (`invite_share_opened` per created ride, `ride_joined` per started ride) and watch the ratio.
3. **Onboarding:** `onboarding_step_viewed` (step 1) → … → `onboarding_completed` → `sign_in_started` →
   `signed_up`. Shows where intro viewers drop.
4. **Paywall:** `paywall_shown` → `paywall_purchase_started` → `subscription_activated`. Break down by
   `source_screen` to see which surface converts (`createBlocked`, `joinBlocked`, `appOpen`, `homeCard`, …)
   and by `access` (trial vs trialExpired vs free).
5. **Trial pressure:** riders with `access = trialExpired` who hit `paywall_shown` from `createBlocked`
   / `joinBlocked`, and what share buy within 24 h.

### Dashboards

- **Growth:** `signed_up` trend, activation funnel, weekly retention.
- **Ride health:** rides started/ended per week, average `rider_count`, `duration_min`, `lobby_minutes`
  (long lobbies = friction), `max_split_km`, regroups and emergencies per 100 rides.
- **Monetization:** paywall funnel by source, `subscription_activated` distinct users per week by
  `product_id`, trial-expiry cohort conversion.
- **Quality:** `join_failed` by `reason`, `create_ride_failed`, location `permission_result` denied rate,
  `sign_in_failed` by `method`.

### Early questions this answers

- Where do new riders stall: before their first ride, or after it?
- Do riders who raise a regroup stay longer (retention by "used regroup" cohort)?
- Does the onboarding pack-size answer predict group size and conversion?
- Which paywall surface earns the revenue, and is the nudge worth its annoyance (`nudge_dismissed` rate)?
- Is the lobby the bottleneck (`lobby_minutes` vs riders who joined but never started)?

### Experiments (PostHog feature flags, when there's traffic)

`UpsellPolicy` timings and paywall copy are the obvious first tests. Gate each behind a flag, split on
the user id, and measure on `subscription_activated` distinct users, not `paywall_shown`.

## Known limits

- Client events are in-memory batched (5 s) and flushed on background. A force-kill can lose the last
  few seconds. Server events are the reliable record, which is why the core loop lives there.
- `invite_share_opened` is intent, not delivery; the OS share sheet doesn't tell us whether a message was sent.
- `app_opened` fires on every foreground, so use unique users or sessions, not event counts.
- No opt-out toggle in the UI yet. `Analytics.isOptedOut` (both apps) is the switch; a Profile row
  needs localized copy in all 50 locales.
- Not yet checked against a live PostHog project: no key has been set. Backend payload shape was
  verified against a local mock; both apps build.

## Meta app events (ad attribution)

Separate from PostHog: these exist so Meta ads can be attributed and optimised for something
better than installs. iOS `Services/MetaEvents.swift`, Android `data/analytics/MetaEvents.kt`;
keep the two in step. Uses the official SDKs (`FacebookCore` 18.1.1 via SPM, `facebook-core`
18.3.0 via Gradle). No user data is sent to Meta.

| Meta event | When | Params |
| --- | --- | --- |
| install / `fb_mobile_activate_app` | logged by the SDK itself | — |
| `fb_mobile_complete_registration` | first successful sign-in on the install (once per install) | `fb_registration_method` |
| `ride_created` (custom) | `POST /rides` succeeded | — |
| `ride_joined` (custom) | `POST /rides/:id/join` succeeded (not the "already joined" path) | — |
| `StartTrial` / `Subscribe` | store purchase verified; `StartTrial` when the offer opens with a free phase | value = plan price, `fb_currency`, `fb_content_id` = product id |

**Turning it on**

1. Create the app in Meta for Developers, add the iOS (`danglingmind.convotrack`) and Android
   (`com.danglingmind.convotrack`) platforms, and link it to the ad account.
2. Keys: iOS `MetaEvents.appID` / `MetaEvents.clientToken`; Android `META_APP_ID` /
   `META_CLIENT_TOKEN` in `local.properties`. Both are public. Empty = off.
3. In the Meta app dashboard turn **off** "Log in-app events automatically": purchases are
   logged by hand, so leaving it on counts every subscription twice.
4. iOS: configure the AEM / SKAdNetwork conversion schema in Events Manager (put `ride_created`
   and `StartTrial` high).

Same gates as PostHog: off in debug builds (unless `-analyticsDebug YES` on iOS /
`Analytics.debugEnabled` on Android) and when `Analytics.isOptedOut`. The Android SDK is never
started by its own init provider (removed in the manifest); `MetaEvents.start` is the only entry.

**Tracking consent.** iOS asks for App Tracking Transparency the first time the main tabs appear.
Declined = no IDFA; Meta still attributes through SKAdNetwork / AEM, delayed and aggregated.
Android adds the `AD_ID` permission (from the SDK).

**Store paperwork this creates:** App Store privacy labels gain "Identifiers → Device ID" and
"Usage data → Advertising data", both used for tracking (third-party advertising). The Play Data
Safety form gains "Device or other IDs" shared for advertising. Update the privacy policy to name Meta.
