import { useState } from "react";

// ─────────────────────────────────────────────
// GAP RESOLUTIONS (v1 carried forward + v2 additions)
// ─────────────────────────────────────────────
const GAP_RESOLUTIONS = {
  "DB-1": {
    title: "GET /rides/:rideId — Response Shape",
    decision: `Resolved response body:

{
  "id": "uuid",
  "title": "string",
  "status": "LOBBY | ACTIVE | PAUSED | COMPLETED",
  "leaderId": "uuid",
  "inviteCode": "string",
  "destinationName": "string",
  "destinationLat": number,
  "destinationLng": number,
  "distanceMeters": number,
  "estimatedDurationSeconds": number,
  "maxAllowedParticipants": number,
  "startedAt": "ISO8601 | null",
  "endedAt": "ISO8601 | null",
  "createdAt": "ISO8601",
  "waypoints": [
    {
      "id": "uuid",
      "order": number,
      "name": "string",
      "lat": number,
      "lng": number,
      "type": "STOP | FUEL | FOOD | SCENIC | DESTINATION"
    }
  ],
  "participants": [
    {
      "userId": "uuid",
      "name": "string",
      "avatarUrl": "string | null",
      "status": "JOINED | READY | ACTIVE | DISCONNECTED | LEFT",
      "isLeader": boolean,
      "joinedAt": "ISO8601"
    }
  ]
}

NOTE: routePolyline is intentionally ABSENT from this response.
Route drawing is fully client-side via MapKit MKDirections.
iOS clients reconstruct the route from waypoints[].
routePolyline is a server-internal field (used by ENG-1/ENG-2 only).
Participants array excludes LEFT users.`,
  },
  "ENG-5": {
    title: "Compactness Score — Algorithm",
    decision: `Resolved formula:

compactnessScore = average over all leaderboard ticks of:
  1 - (maxGap_i / totalRouteDistance)

Where:
  maxGap_i = leader.progress - lastRider.progress at tick i
  totalRouteDistance = ride.distance_meters
  Score range: 0.0 (always spread) → 1.0 (perfectly together)

Implementation:
  - Sample every location_update cycle (not time-based)
  - Store running sum + tick count in ActiveRideState
  - On ride end: finalScore = runningSum / tickCount
  - Cap maxGap at totalRouteDistance to avoid negative scores
    if a rider goes off-route

Store as: ride_summaries.compactness_score DOUBLE PRECISION
Display as: 0–100 on client (multiply by 100).`,
  },
  "SUM-1": {
    title: "Ride Title Assignment Rules",
    decision: `Resolved assignment logic (deterministic, one title per rider):

RIDE_LEADER
  → Assigned to ride.leader_id always.

PACE_KEEPER
  → Rider with smallest average gap to leader over entire ride.
  → Excludes the leader themselves.
  → Formula: avg(leader.progress_i - rider.progress_i) per tick.
  → Lowest average gap (excluding leader) wins.

TRAIL_GUARDIAN
  → Rider ranked last in final leaderboard at ride end.
  → If leader is last (solo ride edge case), skip this title.

FORMATION_RIDER
  → All remaining participants not assigned above.

Tie-breaking:
  → PACE_KEEPER tie: earliest joined_at wins.
  → TRAIL_GUARDIAN tie: lowest final progress wins.

Schema: ride_participants.ride_title stores enum string.
iOS display mapping:
  "RIDE_LEADER"    → "RIDE LEADER"
  "PACE_KEEPER"    → "PACE KEEPER"
  "TRAIL_GUARDIAN" → "TRAIL GUARDIAN"
  "FORMATION_RIDER" → "FORMATION RIDER"`,
  },
  "RT-3": {
    title: "ride:ready — Server Acknowledgment",
    decision: `Resolved: ride:ready uses Socket.IO callback ack pattern.

Client call:
  socket.emit('ride:ready', { rideId }, (ack) => { ... })

Server ack payload:
  Success: { ok: true, participantCount: number, allReady: boolean }
  Error:   { ok: false, error: "NOT_IN_RIDE | RIDE_NOT_LOBBY | UNAUTHORIZED" }

Server also broadcasts to room (excluding sender):
  Event: ride:participant_ready
  Payload: { userId: string, participantCount: number, allReady: boolean }

allReady = true when all JOINED participants are READY.
Leader can use allReady to show "Start Ride" CTA on iOS.`,
  },
  "INV-1": {
    title: "Invite Code System — Format & Endpoints",
    decision: `Resolved: 6-character uppercase alphanumeric invite code per ride.

Code format:
  Charset: ABCDEFGHJKMNPQRSTUVWXYZ23456789
  (32 chars — excludes ambiguous 0/O/I/L)
  Length: 6 characters
  Example: "A3MX7R"
  Generation: crypto.randomBytes(4) → base-32 encode → take first 6 chars
  Uniqueness: UNIQUE constraint on rides.invite_code; retry once on conflict

POST /rides — UPDATED response:
  { rideId: uuid, inviteCode: string }

New endpoint:
  GET /rides/join/:inviteCode
  Auth required.
  Response (LOBBY ride):
    {
      rideId: uuid,
      title: string,
      leaderName: string,
      participantCount: number,
      maxParticipants: number,
      status: "LOBBY"
    }
  Response (not found): 404 { error: "INVITE_CODE_NOT_FOUND" }
  Response (not LOBBY): 409 { error: "RIDE_NOT_IN_LOBBY", status: string }

Share link formats:
  Universal link: convotrack.app/join/{inviteCode}
  Deep link:      convotrack://join/{inviteCode}

iOS app flow:
  1. User taps link or enters 6-char code
  2. App calls GET /rides/join/:inviteCode → gets rideId
  3. App calls POST /rides/:rideId/join with rideId`,
  },
  "RT-7": {
    title: "Battery + Signal Strength in Location Payload",
    decision: `ride:location_update (client → server) — UPDATED payload:

{
  rideId: string,
  lat: number,
  lng: number,
  speed: number,              // km/h from CoreLocation
  heading: number,            // degrees 0–360
  timestamp: ISO8601,
  battery: number | null,     // 0–100 (UIDevice.current.batteryLevel * 100)
  signalStrength: "STRONG" | "MODERATE" | "WEAK" | null
}

battery and signalStrength are optional.
Server accepts null/undefined — omit from broadcast if null.

iOS signalStrength mapping (client-side):
  STRONG:   CTRadioAccessTechnology LTE/5G, or connected to WiFi
  MODERATE: 3G / HSPA / HSPA+
  WEAK:     2G / EDGE, or cellular data disabled

ride:state_update participant shape — UPDATED:
{
  userId, lat, lng, speed, heading, progress, offRoute, updatedAt,
  battery: number | null,
  signalStrength: "STRONG" | "MODERATE" | "WEAK" | null
}

If last received battery/signal was null, omit the field entirely
from the broadcast to save bandwidth.`,
  },
  "SUM-5": {
    title: "Average Speed in Ride Summary",
    decision: `Formula:
  avgSpeedKmh = (distanceMeters / durationSeconds) * 3.6
  Rounded to 1 decimal place.

Edge cases:
  durationSeconds = 0 → store NULL
  distanceMeters  = 0 → store 0.0

Stored as: ride_summaries.avg_speed_kmh DOUBLE PRECISION
Returned in: GET /rides/:rideId/summary as avgSpeedKmh: number | null`,
  },
  "SUM-6": {
    title: "Per-Rider Sync Score Algorithm",
    decision: `Per-rider sync score measures how closely each rider tracked the leader.

Formula:
  syncScore_i = clamp(round((1 - avgGap_i / totalRouteDistance) * 100), 0, 100)

Where:
  avgGap_i = gapAccumulator[userId].gapSum / gapAccumulator[userId].gapCount
  totalRouteDistance = ride.distance_meters
  gapSum and gapCount are accumulated per rider in ActiveRideState on every leaderboard tick

Special cases:
  Ride leader:    always 100 (no gap to themselves)
  Solo ride:      only leader at 100
  Late joiner:    computed from available ticks only (fewer ticks = fine)
  Rider ahead of leader (off-route detour): gap capped at 0 (not negative)

Storage: ride_participants.sync_score INTEGER (0–100)
Returned in: GET /rides/:rideId/summary participants[].syncScore: number`,
  },
  "MAP-1": {
    title: "Route Polyline — MapKit MKDirections (Client-Only)",
    decision: `Resolution: Route drawing is 100% client-side via Apple MapKit.
No polyline is ever fetched from the convotrack backend.

How it works:
  1. CREATE RIDE (iOS):
     - User picks destination via MKLocalSearch
     - iOS calls MKDirections.calculate() with source + all waypoints
     - MKRoute.polyline drawn immediately as MapPolyline in SwiftUI
     - MKRoute.distance + MKRoute.expectedTravelTime populate ride stats
     - iOS encodes the polyline (Google Polyline format) and sends it to
       POST /rides in the request body — backend stores it for ENG-1/ENG-2
       progress snapping. Backend never sends it back to clients.

  2. LOBBY + NAVIGATION (all clients):
     - Client fetches GET /rides/:rideId → receives waypoints[] (lat/lng only)
     - Client constructs MKDirections.Request from waypoints
     - MKDirections.calculate() → same route Apple Maps would show
     - MapPolyline drawn from MKRoute.polyline — no backend round-trip

  iOS code pattern:
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
    request.transportType = .automobile
    let response = try await MKDirections(request: request).calculate()
    let route = response.routes.first  // MKRoute
    // In SwiftUI Map:
    MapPolyline(route.polyline)
      .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round))

  For multi-waypoint rides:
    Set request.source + request.destination to the full span.
    Add intermediate stops by chaining requests or using
    MKDirections with source/destination pairs and compositing polylines.

POST /rides request body — UPDATED to include:
  routePolyline: string   // Google-encoded, sent by iOS after MKDirections.calculate()
  distanceMeters: number  // MKRoute.distance (metres)
  estimatedDurationSeconds: number  // MKRoute.expectedTravelTime (seconds)

GET /rides/:rideId response — routePolyline field REMOVED entirely.
Backend change required: store routePolyline from request body; never return it.`,
  },
  "NAVI-1": {
    title: "Turn-by-Turn Navigation — P1 Client-Side Feature",
    decision: `Resolution: Turn-by-turn navigation is implemented ENTIRELY on-device
using Apple MapKit's MKDirections API. No backend infrastructure required.

P1 client implementation plan:
  1. At ride start: construct MKDirections.Request with all route waypoints
  2. Await MKDirections().calculate() → MKRoute
  3. Cache MKRoute.steps[] locally (step.notice, step.distance, step.polyline)
  4. On each CLLocation update:
     - Find nearest step by comparing rider's progress to cumulative step distances
     - Display step.notice as instruction string
     - Display step.distance as "IN X.X KM"
  5. No server round-trip — all navigation is local MapKit.

Current app status: nav instruction banner removed from RideNavigationView.
The hardcoded placeholder banner was deleted. P1 ticket wires CoreLocation → MKDirections.

Backend change required: NONE.
Spec ticket: NAVI-1 in CLIENT epic.`,
  },
  "CLIENT-1": {
    title: "Distance to Goal — Client-Side Calculation",
    decision: `Backend sends (no change needed):
  ride.distanceMeters — total route length, from GET /rides/:rideId
  participant.progress — meters from start, in ride:state_update

Client computes:
  distanceToGoalMeters = ride.distanceMeters - participant.progress
  distanceToGoalKm     = (distanceToGoalMeters / 1000).toFixed(1)

RideNavigationView leaderboard card shows distanceToGoalKm as "X.X KM TO GO".

Backend change required: NONE.`,
  },
  "EMR-1": {
    title: "Emergency vs Regroup — Event Routing",
    decision: `App's RegroupBottomSheet shows 4 options: Fuel Stop, Food Stop, Scenic Stop, Emergency.

Routing rules:
  Fuel Stop  → socket.emit('ride:regroup', { rideId, type: 'FUEL', lat, lng })
  Food Stop  → socket.emit('ride:regroup', { rideId, type: 'FOOD', lat, lng })
  Scenic Stop → socket.emit('ride:regroup', { rideId, type: 'SCENIC', lat, lng })
  Emergency  → socket.emit('ride:emergency', { rideId, lat, lng, message: "Emergency broadcast" })

The iOS onBroadcast callback must check selectedReason:
  if reason == .emergency → emit ride:emergency
  else → emit ride:regroup with corresponding WaypointType

Backend RG-3 already implements ride:emergency separately.
No backend change required — only iOS routing logic update needed.`,
  },
};

// ─────────────────────────────────────────────
// SCHEMA ADDITIONS (v1 + v2)
// ─────────────────────────────────────────────
const SCHEMA_ADDITIONS = [
  {
    table: "ride_participants",
    sql: "ALTER TABLE ride_participants\n  ADD COLUMN quota_consumed_at TIMESTAMP,\n  ADD COLUMN ride_title TEXT,\n  ADD COLUMN sync_score INTEGER;",
    reason: "quota_consumed_at: audit trail for when quota was charged. ride_title: gamification title enum string. sync_score: per-rider consistency score 0–100.",
    version: "v1+v2",
  },
  {
    table: "rides",
    sql: "ALTER TABLE rides\n  ADD COLUMN invite_code VARCHAR(6);\n\nCREATE UNIQUE INDEX rides_invite_code_idx ON rides (invite_code);",
    reason: "invite_code: 6-char code for join link and QR code. Unique index enables O(1) lookup by GET /rides/join/:inviteCode.",
    version: "v2",
  },
  {
    table: "ride_summaries",
    sql: "ALTER TABLE ride_summaries\n  ADD COLUMN avg_speed_kmh DOUBLE PRECISION;",
    reason: "avg_speed_kmh: computed as (distanceMeters / durationSeconds) * 3.6 on ride end. Exposed in GET /rides/:rideId/summary.",
    version: "v2",
  },
];

// ─────────────────────────────────────────────
// EPICS
// ─────────────────────────────────────────────
const EPICS = {
  INFRA:    { label: "Infrastructure",        color: "#3b82f6" },
  AUTH:     { label: "Auth",                  color: "#8b5cf6" },
  DB:       { label: "Database",              color: "#f59e0b" },
  RIDE:     { label: "Ride Lifecycle",        color: "#10b981" },
  REALTIME: { label: "Realtime / Socket.IO",  color: "#ef4444" },
  ENGINE:   { label: "Progress & Leaderboard",color: "#ec4899" },
  QUOTA:    { label: "Quota & Membership",    color: "#06b6d4" },
  SUMMARY:  { label: "Ride Summary",          color: "#84cc16" },
  REGROUP:  { label: "Regroup & Emergency",   color: "#f97316" },
  INVITE:   { label: "Invite System",         color: "#a855f7" },
  CLIENT:   { label: "Client Contract",       color: "#64748b" },
};

// ─────────────────────────────────────────────
// TASKS — v1 carried forward + v2 gaps resolved
// ─────────────────────────────────────────────
const TASKS = [

  // ── INFRA ──────────────────────────────────
  {
    id: "INFRA-1", epic: "INFRA", priority: "P0", status: "TODO",
    title: "Project scaffold",
    description: "Init Node.js 20 + Fastify 4 repo. TypeScript strict mode. Folder layout: /src/routes, /src/sockets, /src/engines, /src/db, /src/middleware, /src/types. Add ESLint (airbnb-ts), Prettier, tsconfig with path aliases. Add nodemon + ts-node-dev for dev. Add .env.example with all required vars.",
    acceptanceCriteria: [
      "npm run dev starts without errors",
      "npm run build produces /dist",
      "All required env vars documented in .env.example",
    ],
    dependencies: [],
    notes: [],
  },
  {
    id: "INFRA-2", epic: "INFRA", priority: "P0", status: "TODO",
    title: "PostgreSQL connection + migrations",
    description: "Wire up node-postgres pool (pg). Create /src/db/client.ts exporting pool. Use db-migrate or custom sequential migration runner in /migrations/. Migrations must run in numbered order. Include all CREATE TABLE statements from spec PLUS all schema additions (v1 + v2).",
    acceptanceCriteria: [
      "All 10 tables created on fresh DB",
      "ride_participants has quota_consumed_at, ride_title, sync_score",
      "rides has invite_code VARCHAR(6) with UNIQUE index",
      "ride_summaries has avg_speed_kmh",
      "npm run migrate:up runs idempotently",
    ],
    dependencies: ["INFRA-1"],
    notes: [
      "v2 schema additions: rides.invite_code, ride_participants.sync_score, ride_summaries.avg_speed_kmh",
    ],
  },
  {
    id: "INFRA-3", epic: "INFRA", priority: "P1", status: "TODO",
    title: "Railway deployment config",
    description: "Add railway.toml with build and start commands. Define all env vars in Railway dashboard: NODE_ENV, DATABASE_URL, CLERK_SECRET_KEY, CLERK_PUBLISHABLE_KEY, PORT. Configure health check route GET /health → 200 { ok: true }. Add Dockerfile for reproducible builds.",
    acceptanceCriteria: [
      "railway up deploys without errors",
      "GET /health returns 200",
      "DB connection works in production env",
    ],
    dependencies: ["INFRA-1", "INFRA-2"],
    notes: [],
  },
  {
    id: "INFRA-4", epic: "INFRA", priority: "P0", status: "TODO",
    title: "In-memory ride state store",
    description: "Create /src/store/rideStore.ts. Implement Map<string, ActiveRideState> singleton. Export: getRide(id), setRide(id, state), deleteRide(id), updateParticipant(rideId, userId, partial). ActiveRideState must include: spreadSamples tracking (ENG-5), perRiderGapAccumulator: Map<userId, { gapSum: number, gapCount: number }> (SUM-6 / ENG-7), and openRegroup reference.",
    acceptanceCriteria: [
      "TypeScript types match spec ActiveRideState exactly",
      "perRiderGapAccumulator initialised for all participants on ride start",
      "Interface is abstracted behind functions for Phase 2 Redis swap",
    ],
    dependencies: ["INFRA-1"],
    notes: [],
  },
  {
    id: "INFRA-5", epic: "INFRA", priority: "P1", status: "TODO",
    title: "Global error handler + request logging",
    description: "Register Fastify setErrorHandler. Log with pino including requestId, userId, rideId. Return typed error responses: { error: string, code: string, statusCode: number }. Never leak stack traces in production.",
    acceptanceCriteria: [
      "All 4xx/5xx responses return typed JSON error shape",
      "Stack traces absent from production responses",
    ],
    dependencies: ["INFRA-1"],
    notes: [],
  },

  // ── AUTH ───────────────────────────────────
  {
    id: "AUTH-1", epic: "AUTH", priority: "P0", status: "TODO",
    title: "Clerk JWT middleware for REST",
    description: "Create /src/middleware/auth.ts as a Fastify preHandler plugin. Use @clerk/backend verifyToken() to validate Authorization: Bearer <JWT>. On success: attach { userId, sessionId } to request.user. On failure: return 401. Register globally. Bypass only GET /health and GET /rides/join/:inviteCode (public preview allowed).",
    acceptanceCriteria: [
      "Valid Clerk JWT → request.user populated",
      "Invalid/expired JWT → 401",
      "GET /health bypasses auth",
    ],
    dependencies: ["INFRA-1"],
    notes: [],
  },
  {
    id: "AUTH-2", epic: "AUTH", priority: "P0", status: "TODO",
    title: "Socket.IO JWT auth on handshake",
    description: "Create io.use() middleware in /src/sockets/auth.ts. Client passes { auth: { token: '<JWT>' } } on connect. Validate with Clerk verifyToken(). On success: attach socket.data.userId. On failure: next(new Error('UNAUTHORIZED')). All socket handlers read userId from socket.data.userId only.",
    acceptanceCriteria: [
      "Connection without token is rejected",
      "socket.data.userId set for all authenticated connections",
    ],
    dependencies: ["INFRA-1"],
    notes: [],
  },
  {
    id: "AUTH-3", epic: "AUTH", priority: "P0", status: "TODO",
    title: "User upsert on first auth",
    description: "After verifying JWT in both REST and socket auth: INSERT INTO users ON CONFLICT DO NOTHING. Extract name and avatar_url from Clerk JWT claims.",
    acceptanceCriteria: [
      "First request creates users row",
      "Subsequent requests are no-ops",
    ],
    dependencies: ["AUTH-1", "AUTH-2", "INFRA-2"],
    notes: [],
  },

  // ── DB ─────────────────────────────────────
  {
    id: "DB-1", epic: "DB", priority: "P0", status: "RESOLVED",
    title: "GET /rides/:rideId — Response shape",
    description: "GAP RESOLVED. See Gap Resolutions tab. Updated in v2 to include inviteCode field in ride response.",
    acceptanceCriteria: ["Response shape documented", "RIDE-7 implements against this contract"],
    dependencies: [],
    notes: ["✅ Gap resolved — inviteCode added to response shape in v2"],
  },
  {
    id: "DB-2", epic: "DB", priority: "P0", status: "TODO",
    title: "Ride repository layer",
    description: "Create /src/db/rides.ts. Typed functions: createRide(data) → Ride, getRideById(id) → Ride | null, getRideWithDetails(id) → RideWithWaypointsAndParticipants, updateRideStatus(id, status), setRideStarted(id), setRideEnded(id). createRide must accept and store invite_code. getRideByInviteCode(code) → Ride | null for INV-2.",
    acceptanceCriteria: [
      "getRideByInviteCode added for invite lookup",
      "createRide stores invite_code",
      "No SQL strings outside this file",
    ],
    dependencies: ["INFRA-2", "DB-1"],
    notes: ["v2: getRideByInviteCode added"],
  },
  {
    id: "DB-3", epic: "DB", priority: "P0", status: "TODO",
    title: "Participant repository layer",
    description: "Create /src/db/participants.ts. Functions: addParticipant, getParticipants, updateParticipantStatus, markQuotaConsumed, countMonthlyParticipations, setRideTitle, setSyncScore(rideId, userId, score) → void (v2 addition).",
    acceptanceCriteria: [
      "setSyncScore added (v2)",
      "markQuotaConsumed is a single batch UPDATE in transaction",
    ],
    dependencies: ["INFRA-2"],
    notes: ["v2: setSyncScore added"],
  },
  {
    id: "DB-4", epic: "DB", priority: "P0", status: "TODO",
    title: "Membership repository layer",
    description: "Create /src/db/membership.ts. Functions: getActiveMembership, getMembershipPlan, getUserPlanLimits → { monthlyLimit: number | null, maxRidersPerRide: number }.",
    acceptanceCriteria: [
      "getUserPlanLimits returns FREE defaults when no membership",
    ],
    dependencies: ["INFRA-2"],
    notes: [],
  },
  {
    id: "DB-5", epic: "DB", priority: "P0", status: "TODO",
    title: "v2 Schema migrations",
    description: "Add three migrations for v2 additions: (1) ALTER rides ADD COLUMN invite_code VARCHAR(6) + UNIQUE index, (2) ALTER ride_participants ADD COLUMN sync_score INTEGER, (3) ALTER ride_summaries ADD COLUMN avg_speed_kmh DOUBLE PRECISION. These run after initial schema migrations.",
    acceptanceCriteria: [
      "All three migrations run idempotently",
      "rides.invite_code has UNIQUE index",
      "Migration order is numbered sequentially after v1 migrations",
    ],
    dependencies: ["INFRA-2"],
    notes: ["See Schema Additions tab for SQL"],
  },

  // ── INVITE ─────────────────────────────────
  {
    id: "INV-1", epic: "INVITE", priority: "P0", status: "TODO",
    title: "Invite code generation on ride create",
    description: "On POST /rides: generate 6-char uppercase alphanumeric code using charset ABCDEFGHJKMNPQRSTUVWXYZ23456789 (excludes ambiguous 0/O/I/L). Use crypto.randomBytes(4) → base-convert. Store in rides.invite_code. Retry once on UNIQUE constraint violation (collision probability < 0.001%). Return inviteCode in POST /rides response alongside rideId.",
    acceptanceCriteria: [
      "POST /rides response includes { rideId, inviteCode }",
      "invite_code is exactly 6 uppercase alphanumeric chars from safe charset",
      "Handles UNIQUE collision with single retry",
      "inviteCode exposed in GET /rides/:rideId response",
    ],
    dependencies: ["DB-2", "INFRA-2"],
    notes: ["✅ Gap resolved — see Gap Resolutions INV-1"],
  },
  {
    id: "INV-2", epic: "INVITE", priority: "P0", status: "TODO",
    title: "GET /rides/join/:inviteCode",
    description: "New public-ish endpoint (auth recommended but response is non-sensitive). Call getRideByInviteCode(code). Return 404 if not found. Return 409 with { error: 'RIDE_NOT_IN_LOBBY', status } if ride is ACTIVE/COMPLETED/PAUSED. On success return { rideId, title, leaderName, participantCount, maxParticipants, status: 'LOBBY' }. iOS uses this to resolve 6-char code → rideId before calling POST /rides/:rideId/join.",
    acceptanceCriteria: [
      "404 for unknown codes",
      "409 for non-LOBBY rides (prevents stale QR codes from joining mid-ride)",
      "leaderName joined from users table",
      "Response lets iOS show ride preview before confirming join",
    ],
    dependencies: ["DB-2", "AUTH-1"],
    notes: [],
  },

  // ── RIDE ───────────────────────────────────
  {
    id: "RIDE-1", epic: "RIDE", priority: "P0", status: "TODO",
    title: "POST /rides — Create Ride",
    description: "Validate request body (Zod schema). iOS sends: title, waypoints[], routePolyline (Google-encoded, calculated client-side via MKDirections), distanceMeters, estimatedDurationSeconds, maxAllowedParticipants. Checks: getUserPlanLimits, validate waypoints has exactly 1 DESTINATION type. Generate invite_code. Insert rides row (storing routePolyline as internal field — never returned to clients). Insert ride_waypoints. Insert leader into ride_participants (status: JOINED). Return { rideId, inviteCode }.",
    acceptanceCriteria: [
      "routePolyline accepted in request body and stored",
      "routePolyline is NEVER included in any GET response",
      "distanceMeters + estimatedDurationSeconds stored from iOS MKDirections output",
      "Response includes inviteCode",
      "membership_snapshot written at creation time",
      "Leader auto-added as participant",
      "Quota NOT consumed at create time",
    ],
    dependencies: ["AUTH-1", "DB-2", "DB-3", "DB-4", "QUOTA-1", "INV-1"],
    notes: ["v2: inviteCode generation + response", "v2: routePolyline sent by client (MKDirections), stored server-side only for ENG-1/ENG-2"],
  },
  {
    id: "RIDE-2", epic: "RIDE", priority: "P0", status: "TODO",
    title: "POST /rides/:rideId/join — Join Ride",
    description: "Checks in order: (1) ride exists → 404, (2) ride.status === LOBBY → 409, (3) user not already participant → 409, (4) participant count < max → 409 RIDE_FULL, (5) canUserParticipate() → 403 QUOTA_EXCEEDED. Insert into ride_participants. Return { ok: true }.",
    acceptanceCriteria: [
      "Each check returns distinct error code",
      "counted_toward_quota remains false at join",
    ],
    dependencies: ["AUTH-1", "DB-2", "DB-3", "QUOTA-2", "QUOTA-3"],
    notes: [],
  },
  {
    id: "RIDE-3", epic: "RIDE", priority: "P0", status: "TODO",
    title: "POST /rides/:rideId/start — Start Ride",
    description: "Leader only. Check ride.status === LOBBY. Transaction: (1) UPDATE rides SET status='ACTIVE', started_at=now(), (2) markQuotaConsumed. After commit: initialize ActiveRideState (including perRiderGapAccumulator keyed by all participantIds), decode + cache route polyline. Emit ride:state_update to room. Return { ok: true }.",
    acceptanceCriteria: [
      "DB update + quota in single transaction",
      "perRiderGapAccumulator initialized for all participants",
      "Socket broadcast fires after DB commit",
    ],
    dependencies: ["AUTH-1", "DB-2", "DB-3", "INFRA-4", "QUOTA-4", "ENG-1"],
    notes: ["v2: perRiderGapAccumulator initialization added"],
  },
  {
    id: "RIDE-4", epic: "RIDE", priority: "P1", status: "TODO",
    title: "POST /rides/:rideId/pause — Pause Ride",
    description: "Leader only. Validate ride.status === ACTIVE. UPDATE status='PAUSED'. Update ActiveRideState. Emit ride:paused { rideId, pausedAt } to room. Location updates received during PAUSED state stored but don't trigger leaderboard recalculation.",
    acceptanceCriteria: ["Non-leader gets 403", "Room broadcast fires"],
    dependencies: ["RIDE-3"],
    notes: [],
  },
  {
    id: "RIDE-5", epic: "RIDE", priority: "P1", status: "TODO",
    title: "POST /rides/:rideId/resume — Resume Ride",
    description: "Leader only. Validate ride.status === PAUSED. UPDATE status='ACTIVE'. Emit ride:resumed { rideId, resumedAt } to room.",
    acceptanceCriteria: ["Non-leader gets 403"],
    dependencies: ["RIDE-4"],
    notes: [],
  },
  {
    id: "RIDE-6", epic: "RIDE", priority: "P0", status: "TODO",
    title: "POST /rides/:rideId/end — End Ride",
    description: "Leader only. In order: (1) UPDATE status='COMPLETED', ended_at=now(), (2) generate ride summary incl. avg_speed_kmh (SUM-2), (3) assign ride titles (SUM-3), (4) assign sync scores (SUM-6), (5) deleteRide from rideStore, (6) emit ride:ride_ended to room. Return { ok: true, rideId }.",
    acceptanceCriteria: [
      "Summary written before broadcast",
      "Sync scores written before broadcast",
      "ActiveRideState removed from memory",
    ],
    dependencies: ["RIDE-3", "SUM-2", "SUM-3", "SUM-6"],
    notes: ["v2: SUM-6 sync score assignment added to end sequence"],
  },
  {
    id: "RIDE-7", epic: "RIDE", priority: "P1", status: "TODO",
    title: "GET /rides/:rideId",
    description: "Call getRideWithDetails(rideId). Return 404 if not found. Response includes waypoints[] (lat/lng/type/name) so iOS can reconstruct the route via MKDirections client-side. routePolyline is never included in the response — it is a server-internal field. Shape per DB-1.",
    acceptanceCriteria: [
      "inviteCode included in response",
      "routePolyline is NOT in response under any condition",
      "waypoints[] fully populated so iOS can call MKDirections",
    ],
    dependencies: ["AUTH-1", "DB-2", "DB-1"],
    notes: ["No polyline visibility rules needed — field absent entirely from response"],
  },

  // ── REALTIME ───────────────────────────────
  {
    id: "RT-1", epic: "REALTIME", priority: "P0", status: "TODO",
    title: "Socket.IO server setup",
    description: "Attach Socket.IO to Fastify HTTP server. Configure CORS from env ALLOWED_ORIGINS. Register auth middleware (AUTH-2). Room naming: ride:{rideId}. Export io instance for REST route handlers.",
    acceptanceCriteria: [
      "Socket.IO attaches to same port as Fastify",
      "CORS configured from env",
    ],
    dependencies: ["AUTH-2", "INFRA-1"],
    notes: [],
  },
  {
    id: "RT-2", epic: "REALTIME", priority: "P0", status: "TODO",
    title: "ride:join + ride:leave socket handlers",
    description: "ride:join { rideId }: validate user is DB participant. Join room. Update ActiveRideState. Emit ride:participant_joined to room. Send current ActiveRideState snapshot back. ride:leave: leave room, update status to LEFT in DB + memory, emit ride:participant_left.",
    acceptanceCriteria: [
      "Non-participant cannot join room",
      "Joining sends full current state snapshot to joiner",
    ],
    dependencies: ["RT-1", "INFRA-4", "DB-3"],
    notes: [],
  },
  {
    id: "RT-3", epic: "REALTIME", priority: "P1", status: "RESOLVED",
    title: "ride:ready socket handler",
    description: "GAP RESOLVED. Socket.IO ack pattern. Update status to READY. Compute allReady. Ack { ok, participantCount, allReady }. Broadcast ride:participant_ready to room excluding sender.",
    acceptanceCriteria: ["Ack and broadcast shapes per RT-3 resolution"],
    dependencies: ["RT-1", "DB-3"],
    notes: ["✅ Resolved"],
  },
  {
    id: "RT-4", epic: "REALTIME", priority: "P0", status: "TODO",
    title: "ride:location_update handler",
    description: "Receive { rideId, lat, lng, speed, heading, timestamp, battery?, signalStrength? }. Validate: ride ACTIVE. Update participant in ActiveRideState (including battery, signalStrength if provided). Run ENG-2 progress engine. Update participant.progress. Run ENG-3 leaderboard (which accumulates perRiderGapAccumulator). Run ENG-4 split detection. Run ENG-6 compactness sampling. Enqueue broadcast (throttled 1/sec). No DB writes.",
    acceptanceCriteria: [
      "battery and signalStrength stored in participant state",
      "No DB writes on location update",
      "Broadcast throttled to 1/sec per ride",
    ],
    dependencies: ["RT-1", "INFRA-4", "ENG-2", "ENG-3"],
    notes: ["v2: battery + signalStrength fields added per RT-7 resolution"],
  },
  {
    id: "RT-5", epic: "REALTIME", priority: "P0", status: "TODO",
    title: "Disconnect + reconnect handling",
    description: "On disconnect: set DISCONNECTED in memory. 30s timer before DB update. On reconnect (ride:join to active ride): restore full state, emit re-joined to room. If ride ended during disconnect, include ride:ride_ended in snapshot.",
    acceptanceCriteria: [
      "30s grace window before DB update",
      "Reconnect within grace period invisible to other riders",
    ],
    dependencies: ["RT-2", "INFRA-4"],
    notes: [],
  },
  {
    id: "RT-6", epic: "REALTIME", priority: "P0", status: "TODO",
    title: "ride:state_update broadcaster",
    description: "Create /src/sockets/broadcaster.ts. Per-ride 1s debounce timer. Broadcast shape: { rideId, status, participants: [{ userId, lat, lng, speed, heading, progress, offRoute, updatedAt, battery, signalStrength }], leaderboard: [{ rank, userId, name, progress, gapMeters, positionDelta, title }] }. Clear timer on ride end.",
    acceptanceCriteria: [
      "battery and signalStrength included per participant (null if unavailable)",
      "Max 1 broadcast/second per ride",
    ],
    dependencies: ["RT-1", "ENG-3"],
    notes: ["v2: battery + signalStrength in participant broadcast shape"],
  },
  {
    id: "RT-7", epic: "REALTIME", priority: "P1", status: "RESOLVED",
    title: "Battery + signal strength in location payload",
    description: "GAP RESOLVED. iOS sends battery (0–100) and signalStrength (STRONG | MODERATE | WEAK | null) in ride:location_update. Server stores in ActiveRideState and broadcasts in ride:state_update. Powers RiderDetailDrawer telemetry cards.",
    acceptanceCriteria: ["Payload contract per RT-7 resolution", "RT-4 and RT-6 updated to handle fields"],
    dependencies: ["RT-4", "RT-6"],
    notes: ["✅ Resolved — see Gap Resolutions RT-7"],
  },

  // ── ENGINE ─────────────────────────────────
  {
    id: "ENG-1", epic: "ENGINE", priority: "P0", status: "TODO",
    title: "Route polyline decode + cache",
    description: "On ride start (RIDE-3): read rides.route_polyline from DB (stored at ride creation, sent by iOS after MKDirections.calculate()). Decode using @mapbox/polyline into LatLng[]. Compute cumulative distance array using Haversine. Store both in ActiveRideState. Decoded once — not per location update. The polyline is never sent to or received from clients; it exists solely for server-side GPS snapping.",
    acceptanceCriteria: [
      "Polyline decoded once at ride start from DB",
      "Haversine cumulative distances precomputed",
      "Polyline never included in any socket broadcast or REST response",
    ],
    dependencies: ["INFRA-4"],
    notes: ["Polyline is iOS-calculated (MKDirections) and stored on ride create — see MAP-1 resolution"],
  },
  {
    id: "ENG-2", epic: "ENGINE", priority: "P0", status: "TODO",
    title: "Progress engine — snap GPS to route",
    description: "Create /src/engines/progressEngine.ts. Input: { lat, lng }, routePoints, cumulativeDist. Algorithm: nearest point-on-segment projection. Return { progress: meters, offRoute: boolean }. OFF_ROUTE_THRESHOLD = 75m (env-configurable).",
    acceptanceCriteria: ["Returns meters not percentage", "Unit tested"],
    dependencies: ["ENG-1"],
    notes: [],
  },
  {
    id: "ENG-3", epic: "ENGINE", priority: "P0", status: "TODO",
    title: "Leaderboard engine",
    description: "Create /src/engines/leaderboardEngine.ts. Filter ACTIVE+READY participants. Sort by progress DESC. Compute rank, gapMeters, positionDelta. On each compute: update ActiveRideState.perRiderGapAccumulator[userId].gapSum += gap, count++ for all non-leader riders. Return LeaderboardEntry[].",
    acceptanceCriteria: [
      "DISCONNECTED excluded",
      "perRiderGapAccumulator updated every tick (ENG-7 dependency)",
      "Leader always rank 1",
    ],
    dependencies: ["ENG-2", "INFRA-4"],
    notes: ["v2: perRiderGapAccumulator accumulation added here"],
  },
  {
    id: "ENG-4", epic: "ENGINE", priority: "P1", status: "TODO",
    title: "Group split detection",
    description: "After sort: if leader.progress - lastActiveRider.progress > SPLIT_THRESHOLD (2000m, env-configurable) and !splitActive: set splitActive=true, emit ride:split_detected. When gap drops below threshold: set splitActive=false, emit ride:split_resolved. Debounce re-emit.",
    acceptanceCriteria: ["No re-emission while splitActive=true", "Env-configurable threshold"],
    dependencies: ["ENG-3"],
    notes: [],
  },
  {
    id: "ENG-5", epic: "ENGINE", priority: "P0", status: "RESOLVED",
    title: "Compactness score — algorithm definition",
    description: "GAP RESOLVED. Average of (1 - maxGap_i/totalDist) over all ticks. Sampled every location_update cycle.",
    acceptanceCriteria: ["Algorithm documented"],
    dependencies: [],
    notes: ["✅ Resolved"],
  },
  {
    id: "ENG-6", epic: "ENGINE", priority: "P1", status: "TODO",
    title: "Compactness score computation",
    description: "In ENG-3: after each compute, record maxGap. Accumulate spreadSampleSum += (1 - min(maxGap, totalDist)/totalDist), spreadSampleCount++. On ride end: finalScore = sum/count. Solo ride = 1.0.",
    acceptanceCriteria: ["Score in [0.0, 1.0]", "Solo ride returns 1.0"],
    dependencies: ["ENG-3", "ENG-5"],
    notes: [],
  },
  {
    id: "ENG-7", epic: "ENGINE", priority: "P1", status: "TODO",
    title: "Per-rider gap accumulation",
    description: "Within ENG-3 leaderboard computation: for each non-leader participant (ACTIVE or READY), compute individualGap = leader.progress - rider.progress. Update ActiveRideState.perRiderGapAccumulator[userId].gapSum += individualGap, gapCount++. Cap individualGap at 0 minimum (don't penalise riders ahead of leader on off-route detours). Leader entry: gapSum stays 0.",
    acceptanceCriteria: [
      "All non-leader participants have accumulator entries",
      "Gap floored at 0 (not negative)",
      "Leader accumulator entry: gapSum=0, gapCount=tickCount (for sync score = 100)",
    ],
    dependencies: ["ENG-3", "INFRA-4"],
    notes: ["v2 addition — feeds SUM-6 per-rider sync score"],
  },

  // ── QUOTA ──────────────────────────────────
  {
    id: "QUOTA-1", epic: "QUOTA", priority: "P0", status: "TODO",
    title: "Membership plan seed data",
    description: "Seed FREE (limit=10, maxRiders=5) and PREMIUM (limit=NULL, maxRiders=25). Idempotent.",
    acceptanceCriteria: ["Both plan rows exist after fresh migration"],
    dependencies: ["INFRA-2"],
    notes: [],
  },
  {
    id: "QUOTA-2", epic: "QUOTA", priority: "P0", status: "TODO",
    title: "Participation quota check service",
    description: "canUserParticipate(userId): count rides where counted_toward_quota=true this month. Return { allowed, used, limit, planCode }. PREMIUM: always allowed=true.",
    acceptanceCriteria: ["PREMIUM always allowed", "FREE blocked at 10"],
    dependencies: ["DB-3", "DB-4", "QUOTA-1"],
    notes: [],
  },
  {
    id: "QUOTA-3", epic: "QUOTA", priority: "P0", status: "TODO",
    title: "Rider count limit enforcement",
    description: "In RIDE-2 and RIDE-1: compare active participant count against ride.max_allowed_participants. Return 409 RIDE_FULL if at limit. LEFT participants don't count.",
    acceptanceCriteria: ["Uses ride row's snapshotted limit, not current plan"],
    dependencies: ["DB-2", "DB-3"],
    notes: [],
  },
  {
    id: "QUOTA-4", epic: "QUOTA", priority: "P0", status: "TODO",
    title: "Batch quota consumption on ride start",
    description: "In RIDE-3: batch UPDATE ride_participants SET counted_toward_quota=true, quota_consumed_at=now() for all JOINED/READY participants inside the ride-start transaction.",
    acceptanceCriteria: ["Single UPDATE", "Atomic with status change", "Idempotent"],
    dependencies: ["DB-3", "INFRA-2"],
    notes: [],
  },

  // ── SUMMARY ────────────────────────────────
  {
    id: "SUM-1", epic: "SUMMARY", priority: "P0", status: "RESOLVED",
    title: "Ride title assignment rules",
    description: "GAP RESOLVED. RIDE_LEADER / PACE_KEEPER / TRAIL_GUARDIAN / FORMATION_RIDER. iOS maps enums to display strings. See Gap Resolutions SUM-1.",
    acceptanceCriteria: ["Rules and iOS display mapping documented"],
    dependencies: [],
    notes: ["✅ Resolved — iOS display names aligned in v2"],
  },
  {
    id: "SUM-2", epic: "SUMMARY", priority: "P0", status: "TODO",
    title: "Ride summary generator",
    description: "generateRideSummary(rideId, rideState): compute duration_seconds, distance_meters, avg_speed_kmh = (distanceMeters/durationSeconds)*3.6, max_group_split_meters, total_regroups, total_emergencies, compactness_score (ENG-6). INSERT into ride_summaries. Called by RIDE-6.",
    acceptanceCriteria: [
      "avg_speed_kmh computed and stored (v2)",
      "NULL stored if durationSeconds=0",
      "All fields populated before INSERT",
    ],
    dependencies: ["ENG-6", "DB-2"],
    notes: ["v2: avg_speed_kmh added"],
  },
  {
    id: "SUM-3", epic: "SUMMARY", priority: "P1", status: "TODO",
    title: "Assign ride titles to participants",
    description: "assignRideTitles(rideId, rideState). Use SUM-1 rules. Compute from perRiderGapHistory. Store enum strings (RIDE_LEADER, PACE_KEEPER, TRAIL_GUARDIAN, FORMATION_RIDER) in ride_participants.ride_title via setRideTitle(). Called from RIDE-6.",
    acceptanceCriteria: [
      "Every participant gets exactly one title",
      "Solo ride: only RIDE_LEADER",
    ],
    dependencies: ["SUM-1", "ENG-3", "DB-3"],
    notes: [],
  },
  {
    id: "SUM-4", epic: "SUMMARY", priority: "P1", status: "TODO",
    title: "GET /rides/:rideId/summary",
    description: "Return ride_summaries joined with participant titles and sync scores. Response: { rideId, durationSeconds, distanceMeters, avgSpeedKmh, maxGroupSplitMeters, compactnessScore (0–100), totalRegroups, totalEmergencies, createdAt, participants: [{ userId, name, avatarUrl, rideTitle, syncScore }] }. 404 if not found. 409 RIDE_NOT_COMPLETED if still active.",
    acceptanceCriteria: [
      "avgSpeedKmh included (v2)",
      "syncScore per participant included (v2)",
      "compactnessScore returned as 0–100",
      "409 for in-progress rides",
    ],
    dependencies: ["SUM-2", "SUM-3", "SUM-6", "AUTH-1"],
    notes: ["v2: avgSpeedKmh and syncScore added to response"],
  },
  {
    id: "SUM-5", epic: "SUMMARY", priority: "P1", status: "RESOLVED",
    title: "Average speed — algorithm",
    description: "GAP RESOLVED. avgSpeedKmh = (distanceMeters / durationSeconds) * 3.6, rounded to 1dp. NULL if durationSeconds=0. See Gap Resolutions SUM-5.",
    acceptanceCriteria: ["Formula documented"],
    dependencies: [],
    notes: ["✅ v2 addition — resolved"],
  },
  {
    id: "SUM-6", epic: "SUMMARY", priority: "P1", status: "RESOLVED",
    title: "Per-rider sync score — algorithm",
    description: "GAP RESOLVED. syncScore_i = clamp(round((1 - avgGap_i/totalDist) * 100), 0, 100). Leader always 100. Stored in ride_participants.sync_score. See Gap Resolutions SUM-6.",
    acceptanceCriteria: ["Algorithm documented", "SUM-7 implements against this"],
    dependencies: [],
    notes: ["✅ v2 addition — resolved"],
  },
  {
    id: "SUM-7", epic: "SUMMARY", priority: "P1", status: "TODO",
    title: "Assign per-rider sync scores",
    description: "assignSyncScores(rideId, rideState). After ride end: iterate perRiderGapAccumulator. For each userId: compute syncScore per SUM-6 formula. Call setSyncScore(rideId, userId, score). Leader's score hardcoded 100. Solo ride: only leader updated. Called from RIDE-6 alongside SUM-3.",
    acceptanceCriteria: [
      "Every participant gets a sync score",
      "Scores in [0, 100]",
      "Solo ride: leader=100 only",
    ],
    dependencies: ["SUM-6", "ENG-7", "DB-3"],
    notes: ["v2 addition"],
  },

  // ── REGROUP ────────────────────────────────
  {
    id: "RG-1", epic: "REGROUP", priority: "P1", status: "TODO",
    title: "ride:regroup socket handler",
    description: "Any participant can trigger (fuel/food/scenic — NOT emergency). Validate { rideId, type, lat, lng } — type must be FUEL | FOOD | SCENIC | STOP. INSERT into regroup_events. Store in ActiveRideState.openRegroup. Emit ride:regroup_started to room. Ack { ok, regroupId }.",
    acceptanceCriteria: [
      "type=EMERGENCY rejected (use ride:emergency instead)",
      "Only one open regroup at a time",
    ],
    dependencies: ["RT-1", "INFRA-4", "DB-2"],
    notes: ["v2: explicitly exclude EMERGENCY type — use RG-3 for that"],
  },
  {
    id: "RG-2", epic: "REGROUP", priority: "P1", status: "TODO",
    title: "Regroup auto-resolution",
    description: "In location_update (RT-4): if openRegroup exists, check Haversine distance ≤ 100m. Add to arrivedRiders set. If all ACTIVE participants arrived: UPDATE regroup_events SET resolved_at=now(), emit ride:regroup_resolved. Leader can also manually resolve.",
    acceptanceCriteria: ["100m radius", "DISCONNECTED excluded from arrival check"],
    dependencies: ["RG-1", "RT-4"],
    notes: [],
  },
  {
    id: "RG-3", epic: "REGROUP", priority: "P0", status: "TODO",
    title: "ride:emergency socket handler",
    description: "Separate event from ride:regroup. Payload: { rideId, lat, lng, message }. INSERT into emergency_events. Multiple simultaneous emergencies allowed. Emit ride:emergency_started { emergencyId, userId, lat, lng, message, createdAt, priority: 'CRITICAL' } to room. Ack { ok, emergencyId }. Works even when PAUSED.",
    acceptanceCriteria: [
      "Multiple concurrent emergencies each get unique IDs",
      "priority: 'CRITICAL' in broadcast",
      "Works during PAUSED state",
    ],
    dependencies: ["RT-1", "DB-2"],
    notes: ["v2: iOS RegroupBottomSheet routes Emergency selection to this event, not ride:regroup — see EMR-1 resolution"],
  },

  // ── CLIENT ─────────────────────────────────
  {
    id: "NAVI-1", epic: "CLIENT", priority: "P1", status: "RESOLVED",
    title: "Turn-by-turn navigation — P1 client feature",
    description: "GAP RESOLVED. Navigation is entirely on-device via Apple MapKit MKDirections. No backend involvement. Hardcoded nav instruction banner removed from RideNavigationView in v2. P1 client milestone: wire CoreLocation → MKDirections.calculate() → instruction display. See Gap Resolutions NAVI-1.",
    acceptanceCriteria: ["No backend ticket needed", "iOS P1 milestone documented"],
    dependencies: [],
    notes: ["✅ Resolved — removed from app UI, P1 client work only"],
  },
  {
    id: "CLIENT-1", epic: "CLIENT", priority: "P0", status: "RESOLVED",
    title: "Distance to goal — client-side calculation",
    description: "GAP RESOLVED. Client computes distanceToGoalKm = (ride.distanceMeters - participant.progress) / 1000. Backend sends both values already. No backend change needed.",
    acceptanceCriteria: ["Calculation documented", "No backend change needed"],
    dependencies: [],
    notes: ["✅ Resolved"],
  },
  {
    id: "CLIENT-2", epic: "CLIENT", priority: "P1", status: "RESOLVED",
    title: "Emergency routing from RegroupBottomSheet",
    description: "GAP RESOLVED. iOS RegroupBottomSheet must route Emergency selection to ride:emergency event (not ride:regroup). onBroadcast callback checks selectedReason: if .emergency → emit ride:emergency { rideId, lat, lng, message }. All other reasons → emit ride:regroup with corresponding WaypointType. See Gap Resolutions EMR-1.",
    acceptanceCriteria: ["Emergency uses separate socket event", "No backend change needed"],
    dependencies: ["RG-3"],
    notes: ["✅ Resolved — iOS routing logic update required"],
  },
];

// ─────────────────────────────────────────────
// UI COMPONENTS
// ─────────────────────────────────────────────

const PRIORITY_ORDER = { P0: 0, P1: 1, P2: 2 };
const STATUS_COLORS = {
  TODO:        "#64748b",
  IN_PROGRESS: "#f59e0b",
  DONE:        "#10b981",
  BLOCKED:     "#ef4444",
  RESOLVED:    "#6366f1",
};
const STATUSES = ["TODO", "IN_PROGRESS", "DONE", "BLOCKED"];

export default function TaskBoard() {
  const [tasks, setTasks] = useState(TASKS);
  const [statusFilter, setStatusFilter] = useState("ALL");
  const [epicFilter, setEpicFilter] = useState("ALL");
  const [priorityFilter, setPriorityFilter] = useState("ALL");
  const [expandedId, setExpandedId] = useState(null);
  const [activeTab, setActiveTab] = useState("TASKS");

  const filtered = tasks
    .filter(t => statusFilter === "ALL" || t.status === statusFilter)
    .filter(t => epicFilter === "ALL" || t.epic === epicFilter)
    .filter(t => priorityFilter === "ALL" || t.priority === priorityFilter)
    .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);

  const counts = [...STATUSES, "RESOLVED"].reduce((acc, s) => {
    acc[s] = tasks.filter(t => t.status === s).length;
    return acc;
  }, {});
  counts.ALL = tasks.length;

  const epicCounts = Object.keys(EPICS).reduce((acc, e) => {
    acc[e] = tasks.filter(t => t.epic === e).length;
    return acc;
  }, {});

  const updateStatus = (id, status) =>
    setTasks(prev => prev.map(t => t.id === id ? { ...t, status } : t));

  const doneCount = tasks.filter(t => t.status === "DONE").length;
  const progress = Math.round((doneCount / tasks.length) * 100);

  return (
    <div style={{
      minHeight: "100vh",
      background: "#080b12",
      color: "#e2e8f0",
      fontFamily: "'DM Mono', 'Fira Code', 'Courier New', monospace",
      fontSize: "13px",
    }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=DM+Mono:ital,wght@0,300;0,400;0,500;1,400&family=Syne:wght@700;800;900&display=swap');
        * { box-sizing: border-box; }
        ::-webkit-scrollbar { width: 3px; height: 3px; }
        ::-webkit-scrollbar-track { background: #080b12; }
        ::-webkit-scrollbar-thumb { background: #1e293b; border-radius: 2px; }
        .task-card { transition: background 0.1s, transform 0.1s; }
        .task-card:hover { background: #0f1520 !important; }
        .chip:hover { opacity: 0.9; }
        .sbtn { transition: all 0.1s; }
        .sbtn:hover { opacity: 1 !important; filter: brightness(1.2); }
        .tab:hover { color: #94a3b8 !important; }
        pre { white-space: pre-wrap; word-break: break-word; }
        .v2-badge { background: #a855f720; color: #d8b4fe; padding: 1px 6px; border-radius: 3px; font-size: 9px; letter-spacing: 1px; margin-left: 6px; }
      `}</style>

      {/* ── HEADER ── */}
      <div style={{ padding: "22px 28px 18px", borderBottom: "1px solid #111827" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "16px" }}>
          <div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontSize: "20px", fontWeight: 900, letterSpacing: "0.05em", color: "#f1f5f9" }}>
              CONVOTRACK RIDE <span style={{ color: "#3b82f6" }}>///</span> BACKEND SPEC <span style={{ color: "#a855f7" }}>v2</span>
            </div>
            <div style={{ color: "#334155", fontSize: "10px", letterSpacing: "3px", marginTop: "3px" }}>
              IMPLEMENTATION TASK REGISTRY — {tasks.length} TASKS — ALL UI GAPS RESOLVED
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "16px", flexWrap: "wrap" }}>
            {[...STATUSES, "RESOLVED"].map(s => (
              <div key={s} style={{ textAlign: "center" }}>
                <div style={{ fontSize: "17px", fontWeight: "500", color: STATUS_COLORS[s] }}>{counts[s]}</div>
                <div style={{ fontSize: "9px", color: "#334155", letterSpacing: "1px" }}>{s.replace("_"," ")}</div>
              </div>
            ))}
            <div style={{
              background: "#0f1520", border: "1px solid #1e293b", borderRadius: "6px",
              padding: "6px 14px", textAlign: "center"
            }}>
              <div style={{ fontSize: "17px", fontWeight: "500", color: progress === 100 ? "#10b981" : "#f1f5f9" }}>{progress}%</div>
              <div style={{ fontSize: "9px", color: "#334155", letterSpacing: "1px" }}>COMPLETE</div>
            </div>
          </div>
        </div>
        <div style={{ marginTop: "14px", height: "2px", background: "#111827", borderRadius: "1px" }}>
          <div style={{
            height: "100%", width: `${progress}%`,
            background: "linear-gradient(90deg, #3b82f6, #a855f7)",
            borderRadius: "1px", transition: "width 0.3s ease"
          }} />
        </div>
      </div>

      {/* ── TABS ── */}
      <div style={{ display: "flex", gap: "0", borderBottom: "1px solid #111827" }}>
        {[
          { key: "TASKS", label: `Tasks (${tasks.length})` },
          { key: "GAPS", label: `Gap Resolutions (${Object.keys(GAP_RESOLUTIONS).length})` },
          { key: "SCHEMA", label: `Schema Additions (${SCHEMA_ADDITIONS.length})` },
          { key: "CHANGELOG", label: "v2 Changelog" },
        ].map(tab => (
          <button key={tab.key} className="tab"
            onClick={() => setActiveTab(tab.key)}
            style={{
              padding: "10px 20px", border: "none", borderBottom: `2px solid ${activeTab === tab.key ? "#3b82f6" : "transparent"}`,
              background: "transparent", color: activeTab === tab.key ? "#93c5fd" : "#475569",
              cursor: "pointer", fontSize: "11px", letterSpacing: "1px", fontFamily: "inherit",
              transition: "color 0.1s",
            }}>
            {tab.label}
          </button>
        ))}
      </div>

      {/* ── CHANGELOG TAB ── */}
      {activeTab === "CHANGELOG" && (
        <div style={{ padding: "24px 28px", display: "flex", flexDirection: "column", gap: "16px" }}>
          <div style={{ color: "#475569", fontSize: "11px", letterSpacing: "1px", marginBottom: "4px" }}>
            V2 CHANGES — all gaps from iOS app ↔ backend compatibility audit resolved
          </div>
          {[
            {
              category: "iOS App Changes",
              color: "#10b981",
              items: [
                "Removed Push-to-Talk (PTT) button from RideNavigationView — no backend audio infrastructure",
                "Removed PTT button from CoordinationOverlayView",
                "Removed hardcoded turn-by-turn nav instruction banner from RideNavigationView (P1 client feature via MapKit)",
                "Regroup + End Ride buttons now fill space evenly (equal width) after PTT removal",
                "RideSummaryView: title names aligned — WINGMAN→PACE KEEPER, SWEEP→TRAIL GUARDIAN, SQUAD LEADER→RIDE LEADER",
              ],
            },
            {
              category: "New Backend Epics & Tasks",
              color: "#a855f7",
              items: [
                "INVITE epic: INV-1 (invite code generation on ride create), INV-2 (GET /rides/join/:inviteCode)",
                "CLIENT epic: NAVI-1 (navigation P1 client-side), CLIENT-1 (distance-to-goal calc), CLIENT-2 (emergency routing)",
                "ENG-7: Per-rider gap accumulation in leaderboard engine",
                "RT-7: Battery + signal strength in location payload",
                "SUM-5: Average speed computation",
                "SUM-6: Per-rider sync score algorithm",
                "SUM-7: Assign per-rider sync scores on ride end",
                "DB-5: v2 schema migrations",
              ],
            },
            {
              category: "New Gap Resolutions",
              color: "#6366f1",
              items: [
                "MAP-1: Route drawing is 100% MapKit MKDirections — iOS sends polyline on create, backend stores for ENG-1/ENG-2 only, never returned to clients",
                "INV-1: Invite code format (6-char, safe charset, retry on collision)",
                "RT-7: Battery/signal payload contract for RiderDetailDrawer telemetry",
                "SUM-5: Average speed formula",
                "SUM-6: Per-rider sync score formula (feeds RideSummaryView % SYNC display)",
                "NAVI-1: Turn-by-turn navigation is pure MapKit client work, no backend",
                "CLIENT-1: Distance to goal = totalDist - progress, computed client-side",
                "EMR-1: Emergency routes to ride:emergency not ride:regroup",
              ],
            },
            {
              category: "New Schema Additions",
              color: "#f59e0b",
              items: [
                "rides.invite_code VARCHAR(6) UNIQUE — enables GET /rides/join/:inviteCode lookup",
                "ride_participants.sync_score INTEGER — per-rider 0–100 consistency score",
                "ride_summaries.avg_speed_kmh DOUBLE PRECISION — powers summary screen",
              ],
            },
            {
              category: "Updated Existing Tasks",
              color: "#64748b",
              items: [
                "RIDE-1: Now returns { rideId, inviteCode } and generates invite_code on create",
                "RIDE-6: Now calls SUM-7 (sync score assignment) in end sequence",
                "RT-4: Accepts battery + signalStrength fields",
                "RT-6: Broadcasts battery + signalStrength per participant",
                "SUM-2: Computes and stores avg_speed_kmh",
                "SUM-4: Returns avgSpeedKmh + syncScore per participant",
                "ENG-3: Accumulates perRiderGapAccumulator on every tick",
                "DB-2: getRideByInviteCode() added",
                "DB-3: setSyncScore() added",
                "INFRA-4: ActiveRideState includes perRiderGapAccumulator",
                "RG-1: Explicitly rejects type=EMERGENCY (use ride:emergency)",
              ],
            },
            {
              category: "Explicitly Out of Scope (won't fix)",
              color: "#ef4444",
              items: [
                "Push-to-Talk / Voice comms — removed from app entirely",
                "ETA computation — computable client-side from speed + distance, no backend needed",
                "Per-rider battery history / analytics — telemetry snapshot only, not time-series",
              ],
            },
          ].map((section, i) => (
            <div key={i} style={{
              background: "#0b1120", border: "1px solid #1e293b",
              borderLeft: `3px solid ${section.color}`, borderRadius: "6px", padding: "16px 20px"
            }}>
              <div style={{ color: section.color, fontSize: "11px", letterSpacing: "2px", fontWeight: "bold", marginBottom: "12px" }}>
                {section.category.toUpperCase()}
              </div>
              <ul style={{ margin: 0, padding: "0 0 0 16px", display: "flex", flexDirection: "column", gap: "6px" }}>
                {section.items.map((item, j) => (
                  <li key={j} style={{ color: "#94a3b8", fontSize: "12px", lineHeight: "1.6" }}>{item}</li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}

      {/* ── GAP RESOLUTIONS TAB ── */}
      {activeTab === "GAPS" && (
        <div style={{ padding: "24px 28px", display: "flex", flexDirection: "column", gap: "20px" }}>
          {Object.entries(GAP_RESOLUTIONS).map(([taskId, gap]) => {
            const isV2 = !["DB-1", "ENG-5", "SUM-1", "RT-3"].includes(taskId);
            return (
              <div key={taskId} style={{
                background: "#0b1120", border: "1px solid #1e293b",
                borderLeft: `3px solid ${isV2 ? "#a855f7" : "#6366f1"}`, borderRadius: "6px", padding: "18px 20px"
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
                  <span style={{ background: `${isV2 ? "#a855f7" : "#6366f1"}30`, color: isV2 ? "#d8b4fe" : "#a5b4fc", padding: "2px 8px", borderRadius: "3px", fontSize: "11px", letterSpacing: "0.5px" }}>{taskId}</span>
                  <span style={{ color: isV2 ? "#d8b4fe" : "#a5b4fc", fontSize: "13px", fontWeight: "500" }}>{gap.title}</span>
                  {isV2 && <span style={{ background: "#a855f720", color: "#d8b4fe", padding: "1px 6px", borderRadius: "3px", fontSize: "9px", letterSpacing: "1px" }}>v2</span>}
                  <span style={{ marginLeft: "auto", background: "#166534", color: "#86efac", padding: "2px 8px", borderRadius: "3px", fontSize: "10px", letterSpacing: "1px" }}>RESOLVED</span>
                </div>
                <pre style={{
                  background: "#060910", border: "1px solid #1e293b", borderRadius: "4px",
                  padding: "14px 16px", color: "#94a3b8", fontSize: "12px", lineHeight: "1.7",
                  margin: 0, overflowX: "auto"
                }}>{gap.decision}</pre>
              </div>
            );
          })}
        </div>
      )}

      {/* ── SCHEMA ADDITIONS TAB ── */}
      {activeTab === "SCHEMA" && (
        <div style={{ padding: "24px 28px", display: "flex", flexDirection: "column", gap: "16px" }}>
          <div style={{ color: "#475569", fontSize: "11px", letterSpacing: "1px", marginBottom: "4px" }}>
            SCHEMA ADDITIONS — run after initial CREATE TABLE statements
          </div>
          {SCHEMA_ADDITIONS.map((s, i) => (
            <div key={i} style={{
              background: "#0b1120", border: "1px solid #1e293b",
              borderLeft: `3px solid ${s.version === "v2" ? "#a855f7" : "#f59e0b"}`, borderRadius: "6px", padding: "18px 20px"
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "10px" }}>
                <span style={{ background: `${s.version === "v2" ? "#a855f7" : "#f59e0b"}20`, color: s.version === "v2" ? "#d8b4fe" : "#fcd34d", padding: "2px 8px", borderRadius: "3px", fontSize: "11px" }}>{s.table}</span>
                <span style={{ background: "#1e293b", color: "#64748b", padding: "1px 6px", borderRadius: "3px", fontSize: "9px", letterSpacing: "1px" }}>{s.version}</span>
                <span style={{ color: "#64748b", fontSize: "11px" }}>{s.reason}</span>
              </div>
              <pre style={{
                background: "#060910", border: "1px solid #1e293b", borderRadius: "4px",
                padding: "12px 16px", color: "#86efac", fontSize: "12px", lineHeight: "1.6",
                margin: 0, fontFamily: "inherit"
              }}>{s.sql}</pre>
            </div>
          ))}
        </div>
      )}

      {/* ── TASKS TAB ── */}
      {activeTab === "TASKS" && (
        <>
          <div style={{
            padding: "12px 28px", borderBottom: "1px solid #0d1525",
            display: "flex", gap: "6px", flexWrap: "wrap", alignItems: "center"
          }}>
            <span style={{ color: "#334155", fontSize: "9px", letterSpacing: "2px", marginRight: "2px" }}>STATUS</span>
            {["ALL", ...STATUSES, "RESOLVED"].map(s => (
              <button key={s} className="chip"
                onClick={() => setStatusFilter(s)}
                style={{
                  padding: "3px 9px", borderRadius: "3px", border: `1px solid ${statusFilter === s ? (STATUS_COLORS[s] || "#3b82f6") : "#111827"}`,
                  background: statusFilter === s ? "#0f1520" : "transparent",
                  color: statusFilter === s ? "#f1f5f9" : "#334155",
                  cursor: "pointer", fontSize: "10px", letterSpacing: "0.5px", fontFamily: "inherit",
                }}>
                {s.replace("_"," ")}
              </button>
            ))}
            <span style={{ color: "#334155", fontSize: "9px", letterSpacing: "2px", marginLeft: "8px", marginRight: "2px" }}>EPIC</span>
            {["ALL", ...Object.keys(EPICS)].map(e => (
              <button key={e} className="chip"
                onClick={() => setEpicFilter(e)}
                style={{
                  padding: "3px 9px", borderRadius: "3px",
                  border: `1px solid ${epicFilter === e ? (EPICS[e]?.color || "#3b82f6") : "#111827"}`,
                  background: epicFilter === e ? "#0f1520" : "transparent",
                  color: epicFilter === e ? (EPICS[e]?.color || "#f1f5f9") : "#334155",
                  cursor: "pointer", fontSize: "10px", letterSpacing: "0.5px", fontFamily: "inherit",
                }}>
                {e === "ALL" ? "ALL" : EPICS[e].label}
                {e !== "ALL" && <span style={{ marginLeft: "4px", opacity: 0.5 }}>{epicCounts[e]}</span>}
              </button>
            ))}
            <span style={{ color: "#334155", fontSize: "9px", letterSpacing: "2px", marginLeft: "8px", marginRight: "2px" }}>PRIORITY</span>
            {["ALL", "P0", "P1"].map(p => (
              <button key={p} className="chip"
                onClick={() => setPriorityFilter(p)}
                style={{
                  padding: "3px 9px", borderRadius: "3px",
                  border: `1px solid ${priorityFilter === p ? (p === "P0" ? "#ef4444" : p === "P1" ? "#78716c" : "#3b82f6") : "#111827"}`,
                  background: priorityFilter === p ? "#0f1520" : "transparent",
                  color: priorityFilter === p ? "#f1f5f9" : "#334155",
                  cursor: "pointer", fontSize: "10px", letterSpacing: "0.5px", fontFamily: "inherit",
                }}>
                {p}
              </button>
            ))}
          </div>

          <div style={{ padding: "16px 28px 32px", display: "flex", flexDirection: "column", gap: "4px" }}>
            {filtered.map(task => {
              const epic = EPICS[task.epic];
              const isExpanded = expandedId === task.id;
              const isResolved = task.status === "RESOLVED";
              const isV2New = ["INV-1", "INV-2", "RT-7", "ENG-7", "SUM-5", "SUM-6", "SUM-7", "NAVI-1", "CLIENT-1", "CLIENT-2", "DB-5", "MAP-1"].includes(task.id);

              return (
                <div key={task.id} className="task-card"
                  style={{
                    background: isExpanded ? "#0b1120" : "#09101a",
                    border: `1px solid ${isExpanded ? "#1e293b" : "#0d1525"}`,
                    borderLeft: `3px solid ${isResolved ? "#6366f1" : epic.color}`,
                    borderRadius: "5px", padding: "10px 14px", cursor: "pointer",
                    opacity: isResolved ? 0.75 : 1,
                  }}
                  onClick={() => setExpandedId(isExpanded ? null : task.id)}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
                    <span style={{
                      fontFamily: "'Syne', sans-serif", fontSize: "11px", fontWeight: 800,
                      color: isResolved ? "#6366f1" : epic.color, letterSpacing: "0.5px", minWidth: "72px"
                    }}>{task.id}</span>

                    <span style={{
                      padding: "1px 6px", borderRadius: "2px", fontSize: "9px", letterSpacing: "1px",
                      background: task.priority === "P0" ? "#ef444420" : "#78716c20",
                      color: task.priority === "P0" ? "#f87171" : "#a8a29e",
                    }}>{task.priority}</span>

                    <span style={{ color: "#64748b", fontSize: "10px" }}>{epic.label}</span>

                    {isV2New && (
                      <span style={{ background: "#a855f720", color: "#d8b4fe", padding: "1px 6px", borderRadius: "3px", fontSize: "9px", letterSpacing: "1px" }}>v2</span>
                    )}

                    <span style={{
                      flex: 1, color: isResolved ? "#6366f1" : "#cbd5e1", fontSize: "13px",
                      fontWeight: "500", minWidth: "120px"
                    }}>{task.title}</span>

                    <span style={{
                      padding: "2px 8px", borderRadius: "3px", fontSize: "9px", letterSpacing: "1px",
                      background: `${STATUS_COLORS[task.status]}15`,
                      color: STATUS_COLORS[task.status],
                    }}>{task.status.replace("_"," ")}</span>

                    <div style={{ display: "flex", gap: "4px" }} onClick={e => e.stopPropagation()}>
                      {STATUSES.map(s => (
                        <button key={s} className="sbtn"
                          onClick={() => updateStatus(task.id, s)}
                          style={{
                            width: "6px", height: "24px", border: "none", borderRadius: "2px",
                            background: task.status === s ? STATUS_COLORS[s] : "#1e293b",
                            cursor: "pointer", opacity: task.status === s ? 1 : 0.4,
                          }} title={s} />
                      ))}
                    </div>
                  </div>

                  {isExpanded && (
                    <div style={{ marginTop: "14px", display: "flex", flexDirection: "column", gap: "12px" }}>
                      <p style={{ color: "#94a3b8", margin: 0, lineHeight: "1.7", fontSize: "12px" }}>{task.description}</p>

                      {task.acceptanceCriteria.length > 0 && (
                        <div>
                          <div style={{ color: "#475569", fontSize: "9px", letterSpacing: "2px", marginBottom: "6px" }}>ACCEPTANCE CRITERIA</div>
                          {task.acceptanceCriteria.map((ac, i) => (
                            <div key={i} style={{ display: "flex", gap: "8px", marginBottom: "4px" }}>
                              <span style={{ color: "#10b981", fontSize: "11px", marginTop: "1px" }}>→</span>
                              <span style={{ color: "#94a3b8", fontSize: "12px", lineHeight: "1.6" }}>{ac}</span>
                            </div>
                          ))}
                        </div>
                      )}

                      {task.dependencies.length > 0 && (
                        <div style={{ display: "flex", gap: "6px", flexWrap: "wrap", alignItems: "center" }}>
                          <span style={{ color: "#334155", fontSize: "9px", letterSpacing: "2px" }}>DEPS</span>
                          {task.dependencies.map(d => (
                            <span key={d} style={{
                              background: "#0f1a2e", border: "1px solid #1e293b",
                              color: "#64748b", padding: "1px 7px", borderRadius: "3px", fontSize: "10px"
                            }}>{d}</span>
                          ))}
                        </div>
                      )}

                      {task.notes.length > 0 && (
                        <div>
                          {task.notes.map((n, i) => (
                            <div key={i} style={{
                              background: "#0a1628", border: "1px solid #1e2d45",
                              borderRadius: "4px", padding: "8px 12px",
                              color: "#64748b", fontSize: "11px", lineHeight: "1.6"
                            }}>{n}</div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}
