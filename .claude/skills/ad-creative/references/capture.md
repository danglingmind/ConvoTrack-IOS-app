# Capturing a new real screen

Prefer the library. Capture only when no screenshot proves the concept.

1. Boot/inspect: `xcrun simctl list devices booted` (iPhone 17 is the reference device: 1206×2622).
2. Build and install the current app (see CLAUDE.md "Build & Run"); sign in with a demo account.
3. Clean status bar (the `9:41`, full signal/battery look):
   ```bash
   xcrun simctl status_bar booted override --time 9:41 --batteryState charged \
     --batteryLevel 100 --cellularBars 4 --wifiBars 3
   ```
   Reset later with `xcrun simctl status_bar booted clear`.
4. Set up the state. Multi-rider states (a rider far behind, group-split alert, regroup
   called) need several simulators moving along a real route: **use the `ride-demo` skill**
   (`.claude/skills/ride-demo/`) and stop at the moment you need. Respect its golden rules
   (riders start at route km 0; GPS `--distance=2`; settle 15 s).
5. Full-resolution capture, **not** `ride-demo/scripts/shot.sh` (that downsamples to 402 px):
   ```bash
   xcrun simctl io booted screenshot docs/onboarding-screenshots/<NN_name>.png
   sips -g pixelWidth -g pixelHeight <file>   # expect 1206 x 2622
   ```
   Make it read-only right away (`chmod a-w`): a `sips -c` without `--out` crops in place and
   once destroyed a production capture.
6. Add the file to `screens.md`.

**Names on a live ride are frozen at ride start.** The server caches each rider's name in memory
when the ride starts (`sockets/handlers.ts`), and the app syncs its *cached* Clerk name on launch.
So: set demo names in Clerk (dashboard, app "Motorcade"), relaunch every app **twice**, confirm
the names in the lobby, and only then create and start the ride. Renaming mid-ride means a new
ride. Record originals and restore them afterwards.

**Group split alert:** fires when the gap passes `SPLIT_THRESHOLD_METERS` (default 5000). Two
riders are enough: drive only the leader (`simctl location <udid> start --speed=25 --distance=5`)
and leave the other at km 0; ~3.5 min at 25 m/s. Each account in the ride spends one of its 10
monthly ride participations, and an account at its limit can't join. Video walkthroughs: `xcrun simctl io <udid> recordVideo`
   on ONE device only (see ride-demo).
