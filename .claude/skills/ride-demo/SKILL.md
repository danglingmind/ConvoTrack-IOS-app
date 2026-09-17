---
name: ride-demo
description: Record a multi-rider live-tracking demo of ConvoTrack on iOS Simulators — create a ride, join it from other simulators by invite code, drive all riders along a real route at an exact fixed spacing, record the screen, end the ride and capture the summary. Use when the user asks to record a demo/video of the app, test live tracking or group tracking with 2+ riders, simulate riders moving along a route, reproduce the multi-rider flow on simulators, or capture footage for marketing/App Store/social. Triggers on "record a demo", "live tracking demo", "test with N riders", "simulate GPS on the simulator", "record the ride screen", "make a demo video of ConvoTrack".
---

# ConvoTrack multi-rider demo recording

Drives N iOS Simulators through a real ride and records it. Everything below was
established by measurement across three real runs — the numbers in
`reference/troubleshooting.md` are why the defaults are what they are.

## Golden rules (each one cost a ruined take)

1. **Record ONE device.** Three simultaneous encoders drop >50% of frames. Measured:
   3 encoders → 130 s of a 241 s take frozen; 1 encoder → **zero** gaps >50 ms.
   Need multiple angles? Do multiple passes — the tracks are deterministic, so the
   motion is identical every run and the takes composite frame-accurately.
2. **Never force `--codec=h264`.** simctl's default HEVC uses the hardware media engine.
3. **GPS uses `--distance=2`, never `--interval=1`.** `--interval=1` moves the rider in
   one 20 m teleport per second and looks violently choppy. `--distance=2` emits a fix
   every 2 m (~5–7 Hz) and is smooth.
4. **Riders must start at route km 0.** The summary's distance is the leader's
   *route progress*, so starting mid-route counts the teleport as ridden — one run
   reported 151 km/h and a 7.8 km group split. Pick a start location that IS the
   filming start.
5. **Verify every place name with `verify_place.sh` before typing it.** The in-app field
   uses Places Autocomplete; "Kanavepura" silently resolves to "Kanakapura", 93 km away.
6. **Settle 15 s after starting GPS, before recording.** The per-device streams can't
   launch on the same instant; spacing converges over the first few seconds.
7. **Never improvise during the take.** Verify with screenshots *before* rolling. If a
   step fails mid-take: stop, discard, fix, re-record.

## Workflow

```bash
S=.claude/skills/ride-demo/scripts

# 1. Devices (once per session). --fresh erases them, needed to switch Google accounts.
$S/setup_sims.sh 3 --fresh
#    -> user signs in on each sim with DIFFERENT accounts AND different display names
#    -> verify names differ: tap Profile (302,833) on each, screenshot

# 2. Route — verify the place names, then fetch the exact route the app will draw
$S/verify_place.sh "Nandi Hills Main Road"
$S/fetch_route.sh "Nandi Hills Main Road,Nandi Hills,Karnataka" "Nandi Hills,Karnataka" route.json

# 3. Tracks: 100 m apart, 3 riders, 5 m resample, 2100 m run, starting at km 0
$S/gen_tracks.py route.json 100 3 5 2100 trk 0

# 4. Drive the UI with dtap/dswipe using reference/coordinates.md, screenshotting each step
# 5. Seed BEFORE Start Ride (prevents the bogus split), then start ride + navigation
$S/seed_positions.sh trk

# 6. Roll
$S/run_gps.sh trk 10       # 10 m/s hairpins, 14 open road
sleep 15                   # settle, then screenshot to CONFIRM spacing before recording
$S/record.sh demo.mov L
#    ... let it run ...
$S/stop_record.sh demo.mov

# 7. Verify + ship
$S/check_pacing.sh demo.mov     # must report 0 gaps >50 ms
$S/encode.sh demo.mov demo.mp4  # ~260 MB -> ~7 MB
```

## Coordinates

All devices are iPhone 17-class (402×874 pt), so **one coordinate table works for all**.
`arrange_windows.sh` sets Point Accurate + bezels off, which makes `shot.sh` output
exactly 402×874 — 1 screenshot pixel == 1 tap coordinate. Read coordinates straight
off a screenshot. Full table + traps: `reference/coordinates.md`.

Re-run `arrange_windows.sh` after any reboot — window origins move, and every tap
would land ~52 pt off. (`dtap.sh` reads the live window position each call, so this
is self-healing as long as the windows exist.)

## Production data warning

The app is hardcoded to **`pk_live_` Clerk + `api.convotrack.in`**. Every demo run creates
a real ride under real accounts and consumes one of each account's 10 free monthly ride
participations. Ending the ride is irreversible — get explicit user approval first, and
never leave an orphaned ACTIVE ride behind.
