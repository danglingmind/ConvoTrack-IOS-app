# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a pure SwiftUI iOS project — no package manager, no SPM dependencies, no Podfile.

**Run in simulator:**
```
xcodebuild -project convotrack.xcodeproj -scheme convotrack -destination 'platform=iOS Simulator,name=iPhone 17' build
```
### Backend Service Location
While integrating with backend always refer to the API spec first and make sure all the payloads and responses are according to the contracts.
#### Backend server code 
path: /Users/ricky/Workspace/convoy-backend
#### API contract location
path : /Users/ricky/Workspace/convoy-backend/openapi.json

### Android App Location
path: `/Users/ricky/Workspace/convotrack-android` — package root
`app/src/main/java/com/danglingmind/convotrack/`.

**NOT `convoy-android`.** That directory exists but is empty (an orphaned `.idea` folder, no
source). Anything referring to it is stale.

The Android app is a Compose port of this iOS app and is kept at feature parity with it. When
changing shared behaviour — socket events, route/navigation logic, ride lifecycle — check whether
the Android side needs the same change.

**Build:**
```
cd /Users/ricky/Workspace/convotrack-android
./gradlew assembleDebug -Dorg.gradle.java.installations.paths="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```
The `-D` flag is required: `gradle/gradle-daemon-jvm.properties` pins the daemon to a JetBrains
JDK 21, which only ships inside Android Studio and is not on the default toolchain search path.
Without it the build fails with "Unable to download toolchain matching the requirements".


**Open in Xcode (preferred for UI work):**
```
open convotrack.xcodeproj
```

**Key project settings:**
- Swift 5.0, iOS deployment target 26.2
- Bundle ID: `danglingmind.convotrack`
- No test targets exist yet

There are no lint, test, or CI commands — the project is pre-backend-integration prototype stage.

## Architecture

### App Launch Flow
`SplashView` (3.5s animated) → `AuthView` (Google/Apple/Rider ID) → `MainTabView`

`MainTabView` owns global state and navigation. It wraps three tabs in individual `NavigationStack`s and hosts the `JoinRideView` sheet. The bottom nav (`ConvoTrackBottomNav`) hides itself when `AppState.isRideActive == true` (set by `RideNavigationView.onAppear`).

### Screen Flow
```
MainTabView
├── [FLAGGED tab]  RideHistoryView
├── [TRACK tab]    HomeView
│     ├── → CreateRideView        (modal push)
│     ├── → RideLobbyView         (push)
│     │     └── → RideNavigationView  (push, sets isRideActive=true)
│     └── → RideSummaryView       (push)
└── [PROFILE tab]  ProfileView
                                  (sheet, from MainTabView)
JoinRideView ────────────────────── (global sheet, any tab)
```

The prototype `CoordinationOverlayView` is gone; `RegroupBottomSheet`/`RegroupReason` live in `RegroupSheet.swift` and `GroupSplitAlert` in `DesignSystem/HUD.swift`.

### State Management
- `AppState` (`@StateObject` in `MainTabView`, injected via `@EnvironmentObject`): single boolean `isRideActive` that drives bottom nav visibility. `RideNavigationView` sets it on appear/disappear.
- All other state is local `@State` — the app has no networking or persistent state yet; all data is hardcoded.

### Theme System (`ConvoTrackTheme.swift`)
All colors and fonts are defined as `extension Color` and `extension Font` — never use raw hex strings or `Font.system(...)` inline in views.

**Color palette** — dark-only, Material You-inspired:
- `primaryFixed` = `#caf300` (lime green) — the brand accent, used for all primary actions, highlights, and glows
- `onPrimaryFixed` = `#171e00` — dark text/icons on lime backgrounds
- `tertiaryFixed` = `#62ff96` — secondary accent (bright green), used sparingly for status and success states
- `errorColor` = `#ffb4ab`, `errorContainer` = `#93000a`
- Surface scale: `surfaceDim (#131313)` → `surfaceContainerLowest` → `Low` → `Container` → `High` → `Highest (#353535)`

**Typography scale** (all defined as `Font` static vars):
- `.displayMetrics` — 48pt bold, for hero numbers
- `.headlineLg` / `.headlineMd` — 32pt bold / 24pt semibold
- `.bodyLg` / `.bodyMd` — 18pt medium / 16pt regular
- `.labelCaps` — 12pt bold monospaced (used for all-caps labels, status tags)
- `.dataMono` — 14pt medium monospaced (live telemetry numbers)

**Reusable modifiers/components** in `ConvoTrackTheme.swift`:
- `LimePrimaryButton` — full-width lime CTA (apply with `.modifier(LimePrimaryButton())`)
- `GlassCard` — semi-transparent surface with outline
- `ConvoTrackTopBar(title:)` — standard top bar with logo + antenna icon
- `ConvoTrackBottomNav` — 3-tab nav (FLAGGED / TRACK / PROFILE)
- `FloatingStatPill` — stat chip for map overlays
- `ShareSheetPresenter` — UIViewControllerRepresentable wrapper for `UIActivityViewController` with medium sheet detent

### Map Pattern
Both `RideLobbyView` and `RideNavigationView` use MapKit's `Map` with:
- `MapPolyline` stroked in `Color.primaryFixed`
- `Annotation` for rider pins and destination pin
- `Triangle` shape (defined in `RideNavigationView.swift`) as the pointer below map pins
- Lobby map uses `.allowsHitTesting(false)` for a non-interactive preview

### Demo / live-tracking recordings
Recording a multi-rider demo on simulators is covered by the **`ride-demo` skill**
(`.claude/skills/ride-demo/`) — it boots N sims, drives the UI by coordinate, moves riders
along a real Google route at an exact fixed spacing, records, and encodes.

Non-obvious constraints it encodes (all established by measurement, don't rediscover them):
- **Record ONE device only.** Three concurrent `simctl` encoders drop >50% of frames
  (130 s of a 241 s take frozen). One encoder → zero dropped frames. Multiple angles = multiple passes.
- **GPS: `--distance=2`, never `--interval=1`** — the latter teleports the rider 20 m once per second.
- **Riders must start at route km 0.** Summary distance is the leader's *route progress*, so a
  mid-route start credits the teleport as ridden (one run reported 151 km/h, 7.8 km split).
- **Verify place names via Places Autocomplete before typing** — "Kanavepura" resolves to
  "Kanakapura", 93 km away.
- Switching Google accounts on a sim requires `simctl erase`; signing out in-app leaves the
  Safari/ASWebAuthenticationSession cookie and silently re-signs the same account.

### Backend Spec
The planned backend (Node.js/Fastify + Socket.IO + PostgreSQL + Clerk auth) is documented at `spec/BackendSpecV2.jsx` — a self-contained React task board. Open it in a browser or any JSX-capable preview. Key contracts:
- REST: `POST /rides`, `GET /rides/:rideId`, `GET /rides/join/:inviteCode`, etc.
- Socket.IO: `ride:location_update`, `ride:state_update` (broadcast), `ride:ready` (ack pattern)
- Auth: Clerk JWT in `Authorization: Bearer` header (REST) and `socket.auth.token` (Socket.IO)
- Invite codes: 6-char uppercase from safe charset (no 0/O/I/L), returned in `POST /rides` response
- Route polyline: iOS calculates via `MKDirections` and sends encoded polyline in `POST /rides` body. Backend stores it for server-side GPS snapping (ENG-1/ENG-2) only — never returned to clients. All route drawing is client-side MapKit.

The app is currently entirely hardcoded (dummy riders, coordinates, stats). Backend integration has not started.

### Architectural Decisions
- **PTT removed** — Push-to-Talk is out of scope permanently. No audio/voice feature in backend spec.
- **Route polyline** — client-only via `MKDirections`. iOS sends encoded polyline in `POST /rides` body; backend stores for GPS snapping only, never returns it. `GET /rides/:rideId` has no `routePolyline` field.
- **Emergency vs Regroup** — `RegroupBottomSheet` "Emergency" option must emit `ride:emergency` socket event, not `ride:regroup`. The other three reasons (fuel/food/scenic) emit `ride:regroup`.
- **Turn-by-turn nav** — P1 client-side via `MKDirections` → `MKRoute.steps`. No backend involvement. Banner currently removed from `RideNavigationView`.
- **Rider titles** — backend stores enum strings (`RIDE_LEADER`, `PACE_KEEPER`, `TRAIL_GUARDIAN`, `FORMATION_RIDER`); iOS maps to display strings client-side.
- **Invite/join links** — shared links are HTTPS Universal / App Links, `https://convotrack.in/join/CODE` (`AppURLs.joinLinkHost` + path on iOS, `ApiClient.JOIN_LINK_HOST` on Android), **not** the `convotrack://` custom scheme (kept only for legacy/QR back-compat). Custom schemes aren't tappable in messaging apps and have no not-installed fallback. iOS: `associated-domains` entitlement `applinks:convotrack.in` + `DeepLinkRouter` in `ConvoTrackApp.swift` parses both forms (host-validated). Android: App Link intent-filter on the apex only, `autoVerify=true`; `MainActivity` reads `intent.data` → `AppRoot`/`MainScreen` prefill join sheet.
  - **Who serves the domain:** `convotrack.in` is the Vercel project `convotrack-website` (`/Users/ricky/Workspace/convotrack-website`, Next.js), not the backend. It serves `/.well-known/apple-app-site-association` (`app/aasa`), `/.well-known/assetlinks.json` (`app/assetlinks`, both via rewrites in `next.config.ts`) and the not-installed fallback page at `/join/[code]`. Pushing to its `main` deploys. The backend's `routes/deeplink.ts` (onrender host) is the old setup and is not what devices check.
  - **assetlinks fingerprints** are hardcoded in `app/assetlinks/route.ts` (env `ANDROID_SHA256_FINGERPRINTS` overrides): Play app-signing key `34:FE:22:37:…:F6:46:6E` (every Play install) and upload key `BF:C6:6C:F8:…:71:B5:31` (sideloaded release builds). Debug builds use the debug key and never verify. A signing-key change means updating that file.
  - **The apex must serve, not redirect.** Android doesn't follow redirects when verifying, and the intent-filter host is the apex. Vercel Domains: `convotrack.in` → Production, `www.convotrack.in` → 308 → `convotrack.in`. Never flip it back. Check with Google: `https://digitalassetlinks.googleapis.com/v1/assetlinks:check?source.web.site=https://convotrack.in&relation=delegate_permission/common.handle_all_urls&target.android_app.package_name=com.danglingmind.convotrack&target.android_app.certificate.sha256_fingerprint=<SHA256>` → `"linked": true`.
- **Ride summary stats** — computed 100% server-side (`convoy-backend` `summaryService.ts`); iOS `RideSummaryView` / Android `RideSummaryScreen` are thin renderers. Correct semantics: duration = actual wall-clock (`endedAt − startedAt`), NOT the planned ETA; distance = leader's `maxLeaderProgress` + jitter-guarded off-route `detourMeters`, NOT the planned route distance; `maxGroupSplitMeters` = running max tracked per-tick in `leaderboardEngine.ts`, NOT the final snapshot.

- **Product analytics (PostHog)** — full taxonomy, KPIs and setup in `docs/analytics.md`. Three emitters: backend `services/analytics.ts` (ride lifecycle, safety, `subscription_activated`, and the paywall funnel forwarded from `POST /events`), iOS `Services/Analytics.swift`, Android `data/analytics/Analytics.kt` (interface events only). No SDK: each posts to PostHog `/batch/` directly. Off until a key is set (backend `POSTHOG_API_KEY`, iOS `Analytics.apiKey`, Android `local.properties`); debug builds send nothing. Identify by Clerk user id only — never coordinates, place names, invite codes, names, emails or phone numbers in a property. Paywall events stay on `PaywallAnalytics` → `POST /events` and are *not* also sent client-side. New event = update the doc, both `Analytics.Event` enums, or a server `capture(...)`.
- **Meta app events (ad attribution)** — separate from PostHog, official Meta SDKs: iOS `Services/MetaEvents.swift` (`FacebookCore` via SPM, ATT prompt from `MainTabView`), Android `data/analytics/MetaEvents.kt` (`facebook-core`; its init provider is removed in the manifest so only `MetaEvents.start` starts it). Events: SDK install/activate, `CompleteRegistration`, `ride_created`, `ride_joined`, `StartTrial`/`Subscribe`. Off until the app ID + client token are set. Setup and store-privacy paperwork in `docs/analytics.md`.

### Live navigation: values that must match on both platforms
These are implemented twice (iOS `RideNavigationView` / `Services/NavVoiceGuide.swift`, Android `ui/ride/*` / `data/audio/NavVoiceGuide.kt`). Change one, change the other. Android has unit tests for the voice guide and split-alert logic (`./gradlew testDebugUnitTest`).

| What | Value |
| --- | --- |
| Spoken turn prompts | far heads-up only if the turn is ≥ 800 m away; main prompt at 500 m or speed × 20 s (whichever is larger); reminder at 100 m or speed × 6 s; "now" at 15 m (30 m for arrival). A level is spoken at most once per maneuver; a new route or step resets it |
| "Then …" | appended to the reminder when the next maneuver is within 150 m |
| Voice priority | turn < alert (regroup, split, ride-updated reroute) < emergency. Off-route is never spoken (visual status line only). Higher interrupts lower; lower queues behind higher. Mute silences everything except emergencies |
| Spoken after a siren | start after the siren's own length + 200 ms (`SirenPlayer.Sound.duration` / `durationMs`) |
| Alert slot priority | emergency > group split > regroup called > regroup complete; "+N more" chip cycles the rest; off-route and reconnecting are a turn-card status line, not alerts |
| Peek (Show / edge-chip tap) | camera flies to the point; follow camera returns after ~10 s of riding |
| Turns for a saved route | the stored polyline is matched to an alternative's steps, trying in order: default traffic-aware, default traffic-unaware, then traffic-aware avoiding highways, tolls, both (the planner's route options aren't stored with the ride). Start-to-destination rides only; no match → no turns, "Follow route" |
| Convoy gap | (my distance to goal − their distance to goal); "Level" within 25 m; shown only when both riders have posted a position (`hasPosition`), otherwise "--" |
| Arrival | device clock + time left; 12/24 h from the system setting (Android) / locale (iOS); "42m left" beneath |
| Live Activity / notification updates | at most one per 5 s, immediately on a step change or an emergency start/end |
| Image cache TTL | static map 30 days (iOS) / server max-age floored at 5 min (Android); avatars 24 h with ETag revalidation; place photos 30 days (7 days for "no photo"); disk cap 100 MB |
| Access (trial-first freemium) | Pro > enforced trial running > trial expired (create/join blocked, server 403 `TRIAL_EXPIRED`) > free (enforcement off). From `/users/me` `trial { endsAt, enforced }`; days left = ceil, "today" under 24 h |
| App-open nudge | iOS `UpsellPolicy` / Android `data/upsell/UpsellPolicy.kt` (20 shared test cases). Trial day 1 none; day 2 once per calendar day; last 24 h once + once more in the final 6 h; expired every open, ≥ 4 h apart; free: ≥ 3 opens, ≥ 48 h since first, ≥ 72 h apart, 14 days after 3 dismissals, never after 6, a completed ride triggers early. Never within 24 h of the onboarding paywall, for Pro, during a ride, over a deep link or another sheet. An "open" needs ≥ 30 min in the background |
| Home Pro card | trial > 1 day: countdown, ✕ snoozes 24 h; last day: not dismissible; trial expired: no card (locks + badge + nudge carry it); free: ✕ snoozes 7 days (30 after the 3rd). Hidden during a ride. Every paywall entry is labelled "Go Pro" (the nudge's own button is "See plans") |

### Component Locations (not in ConvoTrackTheme.swift)
- `Triangle` shape — defined in `RideNavigationView.swift`, used by map pins across lobby and navigation
- `DrawerButtonStyle` — defined locally in `RiderDetailDrawer.swift`
- `ShareSheetPresenter` — defined in `RideLobbyView.swift` (not ConvoTrackTheme despite being reusable)