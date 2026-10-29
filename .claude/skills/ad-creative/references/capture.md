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
6. Add the file to `screens.md`. Video walkthroughs: `xcrun simctl io <udid> recordVideo`
   on ONE device only (see ride-demo).
