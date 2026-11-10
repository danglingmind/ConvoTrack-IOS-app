# Push notifications: contract and checkpoints

Framework for push notifications. First two types: `RIDE_STARTED`, `RIDE_ENDED`.
Setup that only the owner can do (APNs key, Firebase project, Render env vars) is NOT part of
the build: sending stays off until the env vars exist, like analytics.

## Contract (all three repos must match)

**Register device** (Clerk-authenticated, add to `openapi.json`)
- `PUT /devices` body `{ token: string, platform: "ios" | "android", locale?: string, appVersion?: string }` -> `204`. Upsert by `token`; if the token already belongs to another user, move it to the caller.
- `DELETE /devices/:token` -> `204`. Only deletes the caller's own token.
- Table: migration `018_create_device_tokens.sql`: `id`, `user_id` (FK users), `platform`, `token` UNIQUE, `locale`, `app_version`, `created_at`, `updated_at`.

**Sender** `src/services/notifications/` : `notify(userIds, type, data)`.
- Registry of types: `RIDE_STARTED`, `RIDE_ENDED`. Each: priority, collapse id (`ride-<rideId>`), tap route.
- iOS via APNs HTTP/2 (token auth, ES256 JWT signed with `jose`; no SDK). Android via FCM HTTP v1 (service account OAuth via `jose`; no SDK).
- Env (all optional; missing = log once and skip, never throw): `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8`, `APNS_BUNDLE_ID` (default `danglingmind.convotrack`), `APNS_ENV` (`sandbox`|`production`), `FCM_SERVICE_ACCOUNT` (JSON).
- Remove a token when APNs answers 410 / `BadDeviceToken` or FCM answers `UNREGISTERED`.
- Sending must never block or fail the request that triggered it (fire and forget, catch everything).

**Payloads** (text is localized on the device, the server stores no copy)
- iOS: `aps.alert = { "loc-key": "push.ride_started.body", "loc-args": [rideName] }` (`push.ride_ended.body` likewise), `aps.sound = default`, `thread-id = ride-<rideId>`, custom keys `type`, `rideId`.
- Android: FCM data-only message, `priority: high`, data `{ type, rideId, rideName }`; the app builds the notification from `strings.xml`.
- Recipients: ride participants except the actor (the admin). `RIDE_STARTED` goes to participants in the lobby; `RIDE_ENDED` to participants still in the ride. Fire from `POST /rides/:rideId/start` and the end path (`POST /rides/:rideId/end`, plus any socket path that starts or ends a ride).

**Tap routing** both apps: `RIDE_STARTED` -> open that ride (lobby/navigation); `RIDE_ENDED` -> open the ride summary.
**Foreground**: show the banner, unless the user is already on that ride's screen.
**Permission**: asked once, right after the rider first joins or creates a ride (not at launch). Register the token whenever permission is granted and at every app open while signed in; unregister at sign-out.

## Checkpoints (builders tick their own line and add one line of notes)

- [x] Backend: migration, device routes, sender, hooks, openapi.json, typecheck
- [x] iOS: capability + entitlement, token registration, permission, foreground + tap routing, strings, build passes
  - Note: `Services/PushNotifications.swift` + `aps-environment=development` entitlement; tap RIDE_ENDED opens `HomeRoute.rideSummary`; suppression via `PushNotifications.visibleRideId` (lobby/navigation).
- [x] iOS: simulator test with `xcrun simctl push` (foreground, background, tap)
  - Note: signed-out sim only: prompt, localized foreground/background banners and tap handler verified; PUT /devices, ride routing and suppression not run end-to-end.
- [x] Android: firebase-messaging (plugin applied only if google-services.json exists), service, channel, permission, tap routing, strings, assembleDebug passes
- [x] Reviewer pass over all three
- [x] Review fixes applied
- [x] CLAUDE.md row + docs updated

## Notes

- Backend: migration is `023_create_device_tokens.sql` (018 was taken); `src/db/deviceRepo.ts`, `src/routes/devices.ts`, `src/services/notifications/{index,types,apns,fcm}.ts`, hooks in `routes/rides.ts` start/end (only HTTP paths start/end rides; sockets don't). iOS needs loc keys `push.ride_started.body` / `push.ride_ended.body` (arg = ride title); Android data keys `type`, `rideId`, `rideName`. Both go to non-LEFT participants minus the leader.
- Android: `data/push/Push.kt` + `ConvoFirebaseService` (channel `ride_updates`); permission asked on first lobby entry; needs `app/google-services.json` (gitignored) to go live.
- Review fixes (iOS) applied: 3,4,7
- Review fixes (backend, Android) applied: 1,2,3,5,6

---

# Phase 2: more types + preferences (contract)

## New types
| Type | Category | Recipients | Fired from |
| --- | --- | --- | --- |
| `REGROUP_CALLED` | `regroup` | other non-LEFT participants of the ride (not the caller) | the `ride:regroup` socket handler |
| `EMERGENCY` | `safety` (always on, not switchable) | all other non-LEFT participants (not the rider who raised it) | the `ride:emergency` socket handler |
Existing: `RIDE_STARTED`, `RIDE_ENDED` -> category `ride_updates`.
Not pushed (deliberately): group split, regroup complete, off-route.

**Payloads** (text localized on device)
- iOS `loc-key` + `loc-args`: `push.regroup_fuel.body` / `push.regroup_food.body` / `push.regroup_scenic.body` with args `[callerName, rideName]`; `push.emergency.body` with args `[riderName, rideName]`. Custom keys `type`, `rideId` as before. `thread-id` stays `ride-<rideId>`; collapse id for these two is unique per event (do not replace an earlier push).
- Android data-only: `type`, `rideId`, `rideName`, `riderName`, `reason` (`FUEL|FOOD|SCENIC`, REGROUP_CALLED only). Emergency uses a separate high-importance channel `safety` ("Safety alerts"); the others use `ride_updates`.
- Tap: both new types open the ride navigation screen. Banner suppressed while that ride's screen is on top, as for the existing types (the in-app alert already covers it).

## Preferences
- Table `notification_preferences` (migration `024_create_notification_preferences.sql`): `user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE`, `ride_updates BOOLEAN NOT NULL DEFAULT true`, `regroup BOOLEAN NOT NULL DEFAULT true`, `updated_at`. No row = all on.
- `GET /users/me/notification-preferences` -> `{ rideUpdates: boolean, regroup: boolean }`; `PUT /users/me/notification-preferences` body `{ rideUpdates?: boolean, regroup?: boolean }` (partial upsert) -> same shape. Add both to `openapi.json`.
- `notify()` drops recipients who turned the type's category off. `safety` is never filtered.
- UI (both apps, Profile screen): section "Notifications" with toggles "Ride updates" and "Regroup calls", plus a non-interactive row "Safety alerts, always on". If OS notification permission is denied, show a hint with a button to open system settings. Toggle changes PUT immediately (optimistic, revert on failure). Load with GET on appear.

## Phase 2 checkpoints
- [x] Backend: new types + hooks, preferences table/routes, notify() filtering, openapi, tsc
- [x] iOS: new types handling, strings, Profile section, build passes
- [x] Android: new types handling, safety channel, strings, Profile section, assembleDebug + tests pass
- [ ] Reviewer pass
- [ ] Fixes, migration 024 run, committed and pushed

- Phase 2 backend: types REGROUP_CALLED/EMERGENCY in registry (spec has category + Android channel; `eventId` makes collapse id unique), filtering in notify(), hooks via pushToOthers() in sockets/handlers.ts, prefs routes in routes/notificationPrefs.ts. FCM data stays type-only (no channel key; apps pick channel by type). Migration 024 written, not run.

Notes (iOS Phase 2): REGROUP_CALLED/EMERGENCY taps reuse the RIDE_STARTED open-ride path; foreground suppression is unchanged (keyed on rideId). Profile has a Notifications section (optimistic toggles, denied hint + Open Settings) replacing the old single settings row. Build passes; banners checked via simctl push, signed-out so tap routing and the Profile section were not exercised.

Notes (Android Phase 2): `PushSpec` maps type/reason to text and channel (unit-tested); regroup/emergency use unique notification ids; Profile Notifications section replaces the old settings-link row, denied hint re-checks on resume. assembleDebug and unit tests pass; not run on a device.

Review fixes (iOS): 4, regroup_stop string

Review fixes (backend): 1,3,6; contract: no-reason regroup = push.regroup_stop.body / no reason key
Review fixes (Android): 1,2,5,7
