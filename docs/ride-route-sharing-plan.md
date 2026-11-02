# Shared ride routes: plan

**Goal:** after a ride ends, anyone in it can share a link (`https://convotrack.in/route/<token>`).
Opening it shows the ride on a map: the path the leader **actually rode**, the planned stops, and
the stops where the leader called a regroup. The viewer can edit that route in the planner and
create it as a new ride that they lead.

**Route source:** the server records the leader's actual track during the ride. The stored planned
route (`rides.route_polyline`) is used underneath it, and as the fallback for rides from before
recording ships. Without the actual track, the preview would show the plan rather than what was
ridden, and a leader's detour would leave regroup pins floating off the line.

Each phase can ship on its own. **Phase 1 should ship first and soon:** only rides that happen
after it ships will have an actual track.

---

## What exists today

| Piece | State |
| --- | --- |
| Planned route | `rides.route_polyline` (the leader-selected Google encoded polyline) plus `ride_waypoints` (START / WAYPOINT / DESTINATION). Both come back from `GET /rides/:rideId`. (CLAUDE.md says the polyline is "never returned to clients", but that's out of date.) Editing a ride mid-route replaces both, so a completed ride holds its final plan. |
| Leader's actual track | **Not stored.** `ride:location_update` keeps only `lastLeaderPoint` plus running totals (`maxLeaderProgress`, `detourMeters`, `leaderRawMeters`) in the in-memory `rideStore`, which a server restart loses. It already computes `p.offRoute` for every fix. |
| Regroup coordinates | **Already stored.** `regroup_events` (migration 008) has `ride_id, created_by, type, lat, lng, resolved_at, created_at`, from **every** rider. `lat/lng` is the meet point (the caller's position, or 100 m / 500 m ahead on the route). |
| Emergencies | Separate `emergency_events` table. `ride:regroup` already rejects `EMERGENCY`, so leaving emergencies out needs no filter. |
| How a regroup closed | Not stored. `closeRegroup(..., 'superseded' \| 'capped' \| 'dismissed')` only notifies clients, so a mis-tap replaced 3 s later looks like a real stop. |
| Summary | `GET /rides/:rideId/summary` returns stats and participants only. The screen has no map today (hero photo and stats only); the planned route is drawn only on the share-card image. Phase 2 adds a Route card. |
| Deep links | Only `/join/*`: website `app/aasa` + `app/join/[code]`, iOS `DeepLinkRouter`, Android intent-filter `pathPrefix="/join"`. |
| Planner seeding | `RidePlannerModel.init(ride:)` already builds the planner from a ride's waypoints and stored polyline (used by Edit Ride). Turn-by-turn works from a stored polyline (see "Turns for a saved route" in CLAUDE.md). |

---

## Phase 1: Record the data (backend only)

### 1a. Leader track
- Migration `018_create_ride_track_points.sql`:
  `ride_track_points (id BIGSERIAL PK, ride_id UUID FK CASCADE, lat, lng, off_route BOOLEAN, recorded_at TIMESTAMPTZ)` (`id` orders the points, so a rebuilt ride state after a restart can keep appending).
- Migration `019_alter_rides_add_actual_route.sql`: `rides.actual_route_polyline TEXT NULL`,
  `rides.actual_distance_meters DOUBLE PRECISION NULL`.
- In `ride:location_update`, leader branch: when a fix passes the existing jitter and jump guards
  (`LEADER_MIN_MOVE_METERS`, `LEADER_MAX_JUMP_METERS`) and is ≥ 20 m from the last kept point,
  push `{lat, lng, offRoute}` onto a new `state.trackBuffer`. Flush the buffer with one multi-row
  `INSERT` every 30 s or every 50 points, whichever comes first.
  - Points are written as the ride goes, so a server restart mid-ride loses at most 30 s.
  - Storage is about 10k rows for a 200 km ride, which is fine for Postgres at this scale.
  - Pausing the ride stops recording, because `location_update` already ignores rides that
    aren't `ACTIVE`.
- On `POST /rides/:rideId/end` (and in `generateFallbackSummary`):
  1. Flush the buffer.
  2. Read all points from the DB, not from memory, so a restart doesn't matter.
  3. Simplify with Douglas–Peucker at about 8 m tolerance (new `engines/trackSimplifier.ts`).
  4. Encode with the Google polyline format and store `actual_route_polyline`, plus
     `actual_distance_meters`.
  5. Keep the raw points, which Phase 4's "follow the ridden route" needs. A nightly job can
     delete points older than 90 days.
- Side benefit: the fallback summary can use the recorded track distance instead of the planned
  route distance when in-memory state was lost.
- Recording happens on the server, not the leader's phone. The leader already sends every fix,
  so this survives the leader's app being killed and works the same for iOS and Android leaders.
- **Not stored:** other riders' tracks.

### 1b. Leader regroups worth keeping
- Migration `020_alter_regroup_events_add_close_reason.sql`: add `close_reason TEXT NULL`
  (`RESOLVED | DISMISSED | SUPERSEDED | CAPPED | RIDE_ENDED`).
  - Set it in `closeRegroup` and `resolveIfEveryoneArrived`.
  - When the ride ends, close any regroups still open with `RIDE_ENDED`.
- New `regroupRepo.listLeaderStops(rideId)`. It returns rows where `created_by = rides.leader_id`
  and `close_reason IS DISTINCT FROM 'SUPERSEDED'`, ordered by `created_at`.
  - It's a read-time filter, so past rides get the leader's stops too.

---

## Phase 2: Show it in the ride summary (backend + iOS + Android)

- Add these fields to `GET /rides/:rideId/summary`, and update `openapi.json` to match:
  - `actualRoutePolyline: string | null` (null for rides from before Phase 1)
  - `leaderStops: [{ id, type: FUEL|FOOD|SCENIC|STOP, lat, lng, createdAt }]`
- iOS `RideSummaryView` / Android `RideSummaryScreen`:
  - Draw the actual track in lime and the planned route underneath, dimmed. If there's no actual
    track, draw only the planned route, as today.
  - Show regroup pins using the `RegroupReason` icons, plus the existing start, waypoint and
    destination pins.
  - Add the stop count to the stats.
- The share card map snapshot (`RideSummaryShareCard` / `ShareSummaryCard`) uses the actual track
  when there is one. Bump `styleVersion` so cached cards are regenerated.
- Models: `RideSummary` on both platforms gets both fields, optional.

---

## Phase 3: Share link

### Backend
- Migration `021_alter_rides_add_share_token.sql`: `rides.share_token VARCHAR(12) UNIQUE NULL`,
  `rides.share_enabled BOOLEAN NOT NULL DEFAULT true`.
- `POST /rides/:rideId/share` (auth; caller must be a participant; ride must be `COMPLETED`).
  It creates the token if needed (same alphabet as invite codes, 10 characters) and returns
  `{ token, url }`. Calling it again returns the same link.
  - The link uses a separate token, not the ride UUID, because `GET /rides/:rideId` returns
    participant names and the invite code to any signed-in user who has the UUID.
- `GET /shared-routes/:token`: **public, no auth**, so the website fallback and link previews can
  read it. Add a rate limit. It returns only route data:
  `title, plannedRoutePolyline, actualRoutePolyline, distanceMeters, durationSeconds, waypoints[], leaderStops[], viaPoints[], riderCount, endedAt, sharedBy: { firstName } | null`.
  It never returns participant ids, avatars, emails, the invite code or emergencies.
  `viaPoints` is defined in Phase 4.
- `DELETE /rides/:rideId/share` (leader only) sets `share_enabled = false`, which turns the
  link off.
- Analytics: `ride_route_shared` (server). Properties are ids only, per `docs/analytics.md`.

### Website (`convotrack-website`)
- `app/aasa`: add `{ "/": "/route/*", comment: "Shared ride routes" }`.
- New `app/route/[token]/page.tsx` fallback for people without the app: a static map image (actual
  track, stops, regroup pins), the title, distance and stop count, App Store and Play badges, and
  Open Graph tags so the link shows a map preview in WhatsApp and similar apps.
- Deploy this **before** the app release that handles `/route/`. Apple only reads the AASA file
  at install/update time.

### Apps
- Android manifest: add `<data android:pathPrefix="/route" />` on the same apex-only App Link
  filter. Verification is per host, so assetlinks doesn't change.
- iOS `AppURLs.routeLink(token:)` / Android `ApiClient.ROUTE_LINK_PATH`.
- "Share route" action on the summary screen and on completed rides in history. It calls
  `POST /share` and opens the share sheet with the URL and a short text.

---

## Phase 4: Preview and clone

### Opening the link
- iOS `DeepLinkRouter`: parse `https://convotrack.in/route/<token>`, validating the host and token
  characters the same way as join codes. Buffer it as `pendingRouteToken` for cold launch
  (splash → auth) and post `.convotrackOpenSharedRoute`.
- Android: `MainActivity` handles `intent.data` and passes it through `AppRoot` / `MainScreen`.
- New screen `SharedRoutePreviewView` / `SharedRoutePreviewScreen`:
  - Full map with the actual track (lime), the planned route (dim), waypoint pins and leader
    regroup pins.
  - Stats strip, and the "Shared by <first name>" line.
  - Primary button: **Ride this route**.
  - An expired or disabled link shows an empty state, not an error.
- Show the preview to signed-out users too, then require sign-in at **Ride this route**.

### Clone into the planner
A raw GPS track can't be used directly as a new ride's route. Turn-by-turn needs Directions
geometry, and the track contains GPS noise. So the ridden path is turned into stops, and
Directions draws the route through them:

- **Via points (server, computed at ride end):**
  1. Use the `off_route` flags on the stored track points to find each stretch where the leader
     left the planned route for more than 300 m.
  2. Add one via point at the middle of each stretch, and store them with the ride.
  3. If there were no detours, there are no via points, and the planned route already is the
     ridden route.
- New `RidePlannerModel.init(template: SharedRoute)`. It's the same idea as `init(ride:)`:
  - Stops = the shared waypoints in order, with the via points inserted at their position along
    the route.
  - Route:
    - With no via points, use the stored planned polyline as-is. Turn-by-turn works.
    - With via points, recalculate through `GoogleDirectionsService`. The result follows the
      roads the leader took.
  - Via points appear as plain "via" stops, so the user can remove one to go back to the
    planned road.
  - Leader regroup stops show as "Suggested stops: Fuel · Food · Scenic" chips. Tapping one
    inserts it as a waypoint.
  - The actual track stays visible as a faint reference line while the user edits.
  - Any edit recalculates exactly as the planner does today.
  - Title prefilled as the original title. Rider cap = the user's own plan limit.
  - `savedSnapshot = nil`, so the planner treats it as a new ride.
- Creating it goes through the normal `POST /rides` path, so quota, trial and Pro gating apply
  unchanged. Add an optional `sourceShareToken` to the body, store it as
  `rides.cloned_from_ride_id`, and add the analytics property `cloned: true`.
- Analytics: `shared_route_opened`, `shared_route_clone_started` (client) and
  `ride_created { cloned: true }` (server). Update `docs/analytics.md` and both
  `Analytics.Event` enums.

---

## Decisions with my defaults

| Question | Default |
| --- | --- |
| Who can share | Any participant of a completed ride. Only the leader can disable the link. |
| Which regroups count | Leader-created, not superseded. Emergencies are never included. |
| Start/end privacy | The ride usually starts at the leader's location, often their home. **Default: the public payload trims the first and last 500 m of the actual track. If START wasn't a named place, it also drops START and the planned route's first 500 m, and a clone starts from the viewer's location.** Needs your call. |
| Rides from before Phase 1 | Shareable with the planned route only. Leader stops still work, because `regroup_events` already has them. |
| Raw track retention | 90 days, then the points are deleted. The simplified polyline and via points stay on the ride. |
| Link lifetime | No expiry. The leader can disable it. |

## Order and dependencies

1. **Phase 1** (backend). Ship first, so data starts accumulating.
2. **Phase 2** (backend summary fields, then iOS + Android in parallel).
3. **Phase 3** (backend endpoints, website AASA and page, then apps). Deploy the website before
   the app release.
4. **Phase 4** (backend via points, then iOS + Android preview and clone).

Changes that must match on both platforms (CLAUDE.md parity rule): the link format, the preview
map layers, the via-point and suggested-stop behaviour, the clone defaults and the analytics
events.
