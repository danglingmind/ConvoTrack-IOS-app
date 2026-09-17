# Measured findings — why the defaults are what they are

## "The video looks snappy / stuttery"

Diagnose with `check_pacing.sh`. It is almost always **recorder count**, not GPS.

| | 1 sim, 1 encoder | 3 sims, 3 encoders | 3 sims, 1 encoder (HEVC) |
|---|---|---|---|
| captured fps | 101 | 53 | **124** |
| max frame gap | 37 ms | **460 ms** | 37 ms |
| gaps >50 ms | 0 | **673** | **0** |
| time frozen | 0 s | **130 s of 241 s** | 0 s |

Three concurrent encoders at 1206×2622 plus three live Google Maps renders plus
WindowServer compositing three windows saturates even an M4 Pro. Idle, three booted
sims already burn ~150% CPU with WindowServer at ~46%.

**Fix: record one device.** For multiple angles, run multiple passes — the tracks are
deterministic so motion is identical and takes composite frame-accurately.

Note this is *not* the same as a sped-up video: check `creation_time` vs file mtime
against the video duration. In every run they matched within a second.

## "The rider movement is choppy"

`--interval=1` at 14 m/s = one 20 m teleport per second. Use `--distance=2` (a fix every
2 m). Also resample waypoints at 5 m, not 20 m — 20 m cuts corners across bends instead
of following the road.

## Summary metrics look absurd (151 km/h, 7.8 km split)

Both come from **starting riders mid-route**. Per `convoy-backend/src/services/summaryService.ts`,
distance = `maxLeaderProgress + detourMeters`, i.e. the leader's furthest *route progress* —
so a rider teleported to km 7.9 is credited with having ridden it. `leaderboardEngine.ts`
keeps a running max of the leader-to-tail gap, and a spike recorded before riders report
their first fix is latched permanently.

**Fix:** choose a start location that IS the filming start (riders begin at km 0), and
`seed_positions.sh` *before* tapping Start Ride.

Even done correctly, max group split still over-reports somewhat (0.6 km observed for a
0.2 km true spacing) — suspected to be the engine sampling before every rider has a
snapped progress value. Open question, not yet fixed.

## Can't sign in with a different Google account

Clerk's OAuth runs in `ASWebAuthenticationSession`, which shares Safari's cookie jar on
that simulator. Google sees a live session and signs straight back in. Signing out inside
the app only clears the *Clerk* session. **Only fix: `simctl erase` the device**
(`setup_sims.sh N --fresh`). Sign in with Apple is unreliable on simulators — use Google.

## Joins appear to fail / leader shows "RIDERS 1 · Solo"

Check whether the joiner is stranded on a **stale navigation screen** from a previous
ride. That screen has no back button, so the join sheet never presents over it. Exit via
357,792 → "Exit Navigation". The joins usually did succeed — the lobby was just covered.

*(This is a genuine UX issue worth fixing in the app: a participant whose ride is ended by
the leader can be left on a dead nav screen whose only exit is a button that reads as
"end the ride".)*

## Spurious GROUP SPLIT at ride start

Fires when the leader has a position but joiners haven't sent their first fix, so their
progress reads 0. Seed everyone and wait ~6 s before Start Ride. Dismiss with Ignore (117,550).

## Route in the app doesn't match the fetched route

The app occasionally reports a slightly different total (3.0 km vs a fetched 2.65 km).
Harmless as long as both follow the same road — confirm visually that the rider marker
sits on the drawn polyline after Start Navigation. If they diverge onto different roads,
re-pick the start location.

## Environment

- `xcrun simctl location` per-device: `set`, `start --speed=X --distance=2 -`, `clear`
- `simctl privacy <udid> grant location-always <bundle>` removes all permission dialogs
- ffmpeg lives at `/opt/homebrew/bin/ffmpeg` (not always on PATH)
- Recording MUST be stopped with SIGINT; SIGKILL leaves an unreadable file
