# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a pure SwiftUI iOS project — no package manager, no SPM dependencies, no Podfile.

**Run in simulator:**
```
xcodebuild -project convoy.xcodeproj -scheme convoy -destination 'platform=iOS Simulator,name=iPhone 16' build
```
### Backend Service Location
While integrating with backend always refer to the API spec first and make sure all the payloads and responses are according to the contracts.
#### Backend server code 
path: /Users/ricky/Workspace/convoy-backend
#### API contract location
path : /Users/ricky/Workspace/convoy-backend/openapi.json


**Open in Xcode (preferred for UI work):**
```
open convoy.xcodeproj
```

**Key project settings:**
- Swift 5.0, iOS deployment target 26.2
- Bundle ID: `danglingmind.convoy`
- No test targets exist yet

There are no lint, test, or CI commands — the project is pre-backend-integration prototype stage.

## Architecture

### App Launch Flow
`SplashView` (3.5s animated) → `AuthView` (Google/Apple/Rider ID) → `MainTabView`

`MainTabView` owns global state and navigation. It wraps three tabs in individual `NavigationStack`s and hosts the `JoinRideView` sheet. The bottom nav (`ConvoyBottomNav`) hides itself when `AppState.isRideActive == true` (set by `RideNavigationView.onAppear`).

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

`CoordinationOverlayView` exists as a standalone overlay screen (currently not wired into the main nav flow).

### State Management
- `AppState` (`@StateObject` in `MainTabView`, injected via `@EnvironmentObject`): single boolean `isRideActive` that drives bottom nav visibility. `RideNavigationView` sets it on appear/disappear.
- All other state is local `@State` — the app has no networking or persistent state yet; all data is hardcoded.

### Theme System (`ConvoyTheme.swift`)
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

**Reusable modifiers/components** in `ConvoyTheme.swift`:
- `LimePrimaryButton` — full-width lime CTA (apply with `.modifier(LimePrimaryButton())`)
- `GlassCard` — semi-transparent surface with outline
- `ConvoyTopBar(title:)` — standard top bar with logo + antenna icon
- `ConvoyBottomNav` — 3-tab nav (FLAGGED / TRACK / PROFILE)
- `FloatingStatPill` — stat chip for map overlays
- `ShareSheetPresenter` — UIViewControllerRepresentable wrapper for `UIActivityViewController` with medium sheet detent

### Map Pattern
Both `RideLobbyView` and `RideNavigationView` use MapKit's `Map` with:
- `MapPolyline` stroked in `Color.primaryFixed`
- `Annotation` for rider pins and destination pin
- `Triangle` shape (defined in `RideNavigationView.swift`) as the pointer below map pins
- Lobby map uses `.allowsHitTesting(false)` for a non-interactive preview

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

### Component Locations (not in ConvoyTheme.swift)
- `Triangle` shape — defined in `RideNavigationView.swift`, used by map pins across lobby and navigation
- `DrawerButtonStyle` — defined locally in `RiderDetailDrawer.swift`
- `ShareSheetPresenter` — defined in `RideLobbyView.swift` (not ConvoyTheme despite being reusable)