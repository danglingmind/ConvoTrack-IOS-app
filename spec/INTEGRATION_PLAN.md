# iOS ↔ Backend Integration Plan

Backend: `https://convoy-backend-hx3c.onrender.com`  
Status: Live ✅ | DB Migrations: Done ✅

---

## Phase 0 — Foundation
*Must be done before any screen integration. Everything else blocks on this.*

### 0.1 SPM Dependencies
Add via Xcode → File → Add Package Dependencies:

| Package | URL | Purpose |
|---|---|---|
| ClerkSDK | `https://github.com/clerk/clerk-ios` | Auth + JWT |
| SocketIO | `https://github.com/socketio/socket.io-client-swift` | Realtime |

### 0.2 New Files to Create

```
motorcade/
  Networking/
    APIClient.swift        — URLSession wrapper, auto-injects Clerk JWT
    SocketClient.swift     — Socket.IO singleton, typed event methods
    Models.swift           — All Codable structs matching backend shapes
  Services/
    LocationService.swift  — CLLocationManager wrapper (CoreLocation)
```

### 0.3 Expand AppState.swift

Current: `isRideActive: Bool`

New:
```swift
class AppState: ObservableObject {
    @Published var isRideActive = false
    @Published var currentUser: MotorcadeUser? = nil       // set after Clerk sign-in
    @Published var currentRideId: String? = nil         // set after create/join
    @Published var currentRide: Ride? = nil             // full ride from GET /rides/:id
    @Published var liveRideState: RideStateUpdate? = nil // from ride:state_update socket
    @Published var inviteCode: String? = nil            // set after create ride
}
```

### 0.4 Update motorcadeApp.swift
Configure Clerk with publishable key on app launch.

### 0.5 Models (Codable structs)

All structs needed — define once, used across all phases:

```swift
// Auth
struct MotorcadeUser: Codable { let id, name: String; let avatarUrl: String? }

// Rides
struct Ride: Codable {
    let id, title, status, leaderId, inviteCode: String
    let destinationName: String
    let destinationLat, destinationLng: Double
    let distanceMeters: Double
    let estimatedDurationSeconds: Int
    let maxAllowedParticipants: Int
    let startedAt, endedAt, createdAt: String?
    let waypoints: [Waypoint]
    let participants: [RideParticipant]
}
struct Waypoint: Codable {
    let id: String; let order: Int
    let name, type: String
    let lat, lng: Double
}
struct RideParticipant: Codable {
    let userId, name: String
    let avatarUrl: String?
    let status: String; let isLeader: Bool; let joinedAt: String
}

// Create Ride
struct CreateRideRequest: Codable {
    let title, destinationName: String
    let destinationLat, destinationLng, distanceMeters: Double
    let estimatedDurationSeconds, maxAllowedParticipants: Int
    let routePolyline: String
    let waypoints: [CreateWaypoint]
}
struct CreateWaypoint: Codable { let order: Int; let name, type: String; let lat, lng: Double }
struct CreateRideResponse: Codable { let rideId, inviteCode: String }

// Invite Code
struct InviteCodeResponse: Codable {
    let rideId, title, leaderName: String
    let participantCount, maxParticipants: Int
    let status: String
}

// Socket.IO State
struct RideStateUpdate: Codable {
    let rideId, status: String
    let participants: [LiveParticipant]
    let leaderboard: [LiveLeaderboardEntry]
}
struct LiveParticipant: Codable {
    let userId: String
    let lat, lng, speed, heading: Double?
    let progress: Double; let offRoute: Bool
    let updatedAt: String?
    let battery: Double?; let signalStrength: String?
}
struct LiveLeaderboardEntry: Codable {
    let rank: Int; let userId, name: String
    let progress, gapMeters: Double
    let positionDelta: Int; let title: String?
}

// Summary
struct RideSummary: Codable {
    let rideId: String
    let durationSeconds: Int
    let distanceMeters: Double; let avgSpeedKmh: Double?
    let maxGroupSplitMeters, compactnessScore: Double
    let totalRegroups, totalEmergencies: Int
    let createdAt: String
    let participants: [SummaryParticipant]
}
struct SummaryParticipant: Codable {
    let userId, name: String; let avatarUrl: String?
    let rideTitle: String?; let syncScore: Int?
}

// API Errors
struct APIError: Codable { let error: String }
```

---

## Phase 1 — Auth
*Clerk SDK → real sign-in → JWT available for all subsequent requests.*

### Files changed
- `motorcadeApp.swift` — configure Clerk
- `AuthView.swift` — wire Google + Apple buttons to real Clerk OAuth flows
- `APIClient.swift` — implement `getToken()` helper using `Clerk.shared.session`

### Done when
- Tapping "Continue with Google" opens OAuth sheet and lands on `MainTabView`
- `Clerk.shared.session?.getToken()` returns a valid JWT
- `GET /health` with that JWT header returns 200

---

## Phase 2 — Ride Creation
*CreateRideView becomes fully functional. First real backend call.*

### Files changed
- `CreateRideView.swift`
- `HomeView.swift` — `onChange(of: appState.currentRideId)` navigates to `RideLobbyView` after creation

### Route Stop Architecture
Three distinct stop types, displayed top-to-bottom with a connecting line:
```
● START LOCATION  (required, type: "START")
↕
● VIA [stop 1]   (optional, type: "WAYPOINT", order maintained by addition order)
↕
● VIA [stop 2]   (optional, can add more via "+ ADD STOP", can remove)
↕
● DESTINATION    (required, type: "DESTINATION")
```

Each stop field has:
- `MKLocalSearch` autocomplete that activates on 2+ characters (300ms debounce)
- Results dropdown that clears when item is selected
- ✕ button to clear selection and re-search (fixes re-edit bug: clearing `selectedItem` when `text` drifts from confirmed name)
- Confirmed stop shown with highlighted border + icon tint

### What changes
1. **Start field** — `MKLocalSearch` autocomplete, required
2. **Waypoints** — 0 or more middle stops, add via "+ ADD STOP" button, remove per-stop
3. **Destination field** — `MKLocalSearch` autocomplete, required
4. **Route calculation** — `MKDirections` calculated segment-by-segment (start→wp1, wp1→wp2, ..., wpN→dest), polylines joined without duplicate junction points
5. **Map preview** — `MapPolyline` of full joined route; colored dots for all stops (green=start, lime=waypoints, bright lime=destination)
6. **Stat cards** — sum of all segment distances and travel times
7. **Encode polyline** — joined coordinates → Google Polyline format for backend body
8. **Max riders** — stepper (2–50, default 10)
9. **CREATE RIDE button** → `APIClient.createRide(...)` → `POST /rides`
10. **On success** → set `AppState.currentRideId` + `inviteCode` + dismiss → `HomeView` detects change and pushes `RideLobbyView`

### Waypoints array sent to backend
```
order 0:        { name, lat, lng, type: "START" }
order 1..N-1:   { name, lat, lng, type: "WAYPOINT" }  ← one per middle stop (skipped if none)
order N:        { name, lat, lng, type: "DESTINATION" }
```
`destinationName / destinationLat / destinationLng` at request root = end stop values.

### Additional fixes applied (not in original plan)
- **Navigation race bug**: Using `NavigationPath` in `HomeView` — `navPath = NavigationPath([HomeRoute.rideLobby])` is atomic (no push/pop race). `HomeView` now owns its own `NavigationStack`; `MainTabView` no longer wraps it.
- **Participant name "unknown"**: Backend may return "unknown" if Clerk profile name is unset. Lobby overrides name client-side using `Clerk.shared.user?.firstName/lastName` for the current user.
- **Missing route polyline in lobby**: Backend never returns the polyline (spec). Lobby recalculates it via `MKDirections` from `ride.waypoints` on appear.

### Done when
- Creating a ride stores it in DB and returns `inviteCode`
- Map shows real multi-segment route calculated by Apple Maps
- Re-editing any stop clears its selection and shows fresh autocomplete results

---

## Phase 3 — Joining a Ride ✅ DONE
*JoinRideView resolves invite code and joins the ride.*

### Files changed
- `JoinRideView.swift`

### What was implemented
1. Invite code auto-uppercases/sanitizes, caps at 6 chars
2. On 6th char → `GET /rides/join/:inviteCode` (debounced, spinner shown)
3. Toast shows real title, leader name, participant count from backend
4. JOIN RIDE button → `POST /rides/:rideId/join`
5. On success → sets `appState.currentRideId` + `inviteCode`, dismisses sheet
6. `HomeView.onChange(of: appState.currentRideId)` fires → `navPath = NavigationPath([HomeRoute.rideLobby])` pushes lobby
7. Error handling: RIDE_FULL, ALREADY_JOINED, NOT_FOUND with user-facing alerts
8. ALREADY_JOINED treated as success (just navigates to lobby)

### Note on tab context
`JoinRideView` is a global sheet from `MainTabView`, accessible from any tab. Navigation to lobby via `HomeView.onChange` only works when the user is on the TRACK tab. If they're on another tab, the lobby won't auto-open — this is acceptable for now (Phase 7 can add tab-switching).

### Done when
- Entering a valid code shows real ride info in the toast
- Tapping JOIN lands user in the lobby with their name in the roster

---

## Phase 4 — Lobby (First Realtime)
*RideLobbyView shows real participants, connects to socket room.*

### Already done (from Phase 2/3 work)
- `GET /rides/:rideId` on appear → real title, distance, waypoints
- Route polyline recalculated client-side from waypoints via `MKDirections`
- Map shows start/destination pins + lime polyline
- Participant roster with real names (Clerk name override for current user)
- Invite code in stat pill + QR modal + share sheet
- `ParticipantRiderRow` shows LEADER badge, status chip, initials fallback

### Files to change
- `RideLobbyView.swift`
- `SocketClient.swift`

### What remains
1. Connect socket on appear: `SocketClient.shared.joinRoom(rideId:)` with auth token
2. Listen `ride:state_update` → update `appState.liveRideState` → refresh participant list
3. Listen `ride:participant_joined` / `ride:participant_left` / `ride:participant_ready` → update roster live
4. **Ready button** (non-leaders only): tapping emits `ride:ready` ack → button shows "WAITING..." then "READY ✓"
5. **START RIDE button visibility**: leader only AND all participants ready. Currently always visible — gate it on `ride.leaderId == Clerk.shared.user?.id`
6. START RIDE → `POST /rides/:rideId/start` → on 200 navigate to `RideNavigationView`
7. Disconnect socket `onDisappear` when navigating away

### Missing pieces NOT in original plan
- **Participant name override**: Use `Clerk.shared.user` to fix "unknown" name (done ✓)
- **QR code content**: Show real invite code in QR modal (done ✓). Real QR generation (CoreImage/CIFilter) is a P2 enhancement.
- **Loading state**: No spinner while `GET /rides/:rideId` is in progress — add one
- **Error state**: If `GET /rides/:rideId` fails, show a retry prompt

### Done when
- Two devices can be in the same lobby and see each other's names appear live
- Non-leader taps Ready → status chip updates for all participants
- Leader sees START RIDE button only when all are ready

---

## Phase 5 — Live Navigation
*The core realtime experience. RideNavigationView goes live.*

### Files changed
- `RideNavigationView.swift`
- `LocationService.swift` (new — CoreLocation wrapper)
- `AppState.swift` — `liveRideState` consumed here

### What changes

**Sending location:**
1. `LocationService` starts `CLLocationManager` on ride start
2. Every 2 seconds: emit `ride:location_update { rideId, lat, lng, speed, heading, timestamp, battery, signalStrength }`
3. `UIDevice.current.batteryMonitoringEnabled = true` → get battery level
4. CoreTelephony → derive `signalStrength` (STRONG/MODERATE/WEAK)

**Receiving state:**
1. Listen `ride:state_update` → update `AppState.liveRideState`
2. Rider pins → positions from `liveRideState.participants[].lat/lng`
3. Leaderboard strip → `liveRideState.leaderboard[]`
4. My rank badge → find own `userId` in leaderboard
5. Rider count → `liveRideState.participants.count`
6. "Distance to goal" per rider → `(ride.distanceMeters - participant.progress) / 1000`

**Controls:**
7. REGROUP button → `SocketClient.shared.emit(.regroup(rideId, type, lat, lng))`
8. Emergency (from regroup sheet) → `SocketClient.shared.emit(.emergency(rideId, lat, lng, message))`
9. END RIDE button (leader only) → `POST /rides/:rideId/end` → navigate to `RideSummaryView`

**Alerts:**
10. Listen `ride:split_detected` → show `GroupSplitAlert` (already in `CoordinationOverlayView`)
11. Listen `ride:split_resolved` → dismiss alert
12. Listen `ride:emergency_started` → show critical alert overlay

### Done when
- Two moving devices see each other's pins update on the map in real time
- Leaderboard reflects actual GPS progress along the route

---

## Phase 6 — Ride Summary
*RideSummaryView shows real post-ride data.*

### Files changed
- `RideSummaryView.swift`

### What changes
1. On appear → `GET /rides/:rideId/summary`
2. Metrics grid → real `durationSeconds`, `distanceMeters`, `avgSpeedKmh`, `maxGroupSplitMeters`
3. Leaderboard → real `participants[]` with `rideTitle` (mapped to display string) + `syncScore`
4. Format duration: `durationSeconds` → "H:MM" string
5. Format distance: `distanceMeters / 1000` → "XXX.X KM"
6. `compactnessScore` already 0-100 from backend

### Title display mapping (client-side)
```swift
func displayTitle(_ raw: String?) -> String {
    switch raw {
    case "RIDE_LEADER":     return "RIDE LEADER"
    case "PACE_KEEPER":     return "PACE KEEPER"
    case "TRAIL_GUARDIAN":  return "TRAIL GUARDIAN"
    case "FORMATION_RIDER": return "FORMATION RIDER"
    default:                return raw ?? ""
    }
}
```

### Done when
- Summary screen shows real distance, duration, avg speed, and per-rider titles/sync scores

---

## Phase 7 — Ride History
*RideHistoryView and ProfileView show past rides.*

### Files changed
- `RideHistoryView.swift`
- `ProfileView.swift`

### Requires new backend endpoint
`GET /rides?userId={id}&status=COMPLETED` — not in v2 spec yet, add as P1.

---

## Execution Order Summary

```
Phase 0 (Foundation)     ← start here, 1 session
Phase 1 (Auth)           ← unblocks everything
Phase 2 (Create Ride)    ← validates full stack
Phase 3 (Join Ride)      ← parallel with Phase 2 after auth works
Phase 4 (Lobby)          ← first socket usage
Phase 5 (Navigation)     ← hardest, needs real device for GPS
Phase 6 (Summary)        ← quick, read-only
Phase 7 (History)        ← needs new backend endpoint
```

---

## Info Needed Per Phase

| Phase | Needs |
|---|---|
| 0 | Nothing — start immediately |
| 1 | Clerk publishable key (already in env) |
| 2 | Nothing new |
| 3 | Nothing new |
| 4 | Two devices or two simulator instances |
| 5 | Physical device (GPS), or simulate location in Xcode |
| 6 | Completed ride in DB |
| 7 | New backend endpoint |
