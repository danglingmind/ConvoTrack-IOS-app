# Live navigation — backlog

What is still open after the live-navigation improvements (HIG review of `RideNavigationView`,
Android parity in `convotrack-android`) and the image-caching work. All six plan phases are built
and committed on both platforms; every code item that did not need a device or a product decision
has been done. What remains is checking on real hardware, decisions, and a few deliberate skips.

Status key: **verify** built but never run on a device · **decide** needs a product call ·
**skipped** deliberately not done, with the reason.

## Verify on a device (nothing below has been seen running)

**Voice (Phase 2)**
- Music ducking (Spotify, Apple Music, YouTube Music); prompts with the screen locked and the app backgrounded; with the silent switch on (iOS); Bluetooth/helmet headset routing.
- Prompt distances at city and highway speeds; arrival prompt names the destination; the regional English voice (en-IN etc.) is picked on a real device.
- The spoken cue now starts just after the siren ends (siren length + 200 ms); check it doesn't overlap or leave a long gap.
- The rider who is behind hears "You're falling behind"; split voice is not repeated when re-entering navigation (Android).

**Alerts and camera (Phase 3)**
- Emergency + split + regroup together: only the emergency shows, with "+2 more", the chip cycles in priority order, the turn card is never pushed down.
- Show / edge-chip peek: camera flies there, follow camera returns after ~10 s of riding, Resume works at any point. Regroup/emergency edge chips appear only off-screen, are never clustered, and clear when resolved.

**Information and controls (Phase 4)**
- ARRIVAL against the device clock (and across a 12/24-hour change); AM/PM hidden on the narrowest width; "42m left" at the largest text size.
- Convoy cards: gap sign and size are right; "--" until a rider has posted a position; "Level" within 25 m; offline riders dimmed; tapping a card peeks, tapping your own recentres.
- The bottom bar is taller (strip + stats): check how much map is left and that it doesn't crowd the Regroup/Exit buttons. Edge chips don't collide with the turn card; hit areas 44 pt / 48 dp.
- Landscape keeps the strip in the side panel above the banners (the plan only asked for the same order).

**Pins and splits (Phase 1)**
- Split alert on a two-device ride names the right rider, gap within ~100 m of the leaderboard difference, number moves while the alert is up.
- Pin labels at default and largest text size (capped 1.5×): no overlap with the route, wrapped names stay inside the plate. `stopPinTopExtent` / `STOP_PIN_TOP_EXTENT_DP` (104) were set by estimate: measure against a two-line destination name.

**Live Activity / notification (Phase 5)**
- iOS: Lock Screen and Dynamic Island rendering, updates while locked/backgrounded, tap-to-open, Increase Contrast, StandBy. The widget extension's App ID registers on the first signed device/archive build.
- Android: emergency heads-up, whether Android 16 promotes the Live Update (chip, progress bar, large icon), tap-to-navigation including a cold start, the 5 s throttle, lock-screen privacy (generic text only). If the system restarts the service after killing the process it now stops itself instead of showing a notification that tracks nothing.

**Cleanup (Phase 6)**
- iOS: visual pass of the HUD (one component set), Reduce Motion (fades instead of springs, camera jumps), worst-case label contrast over a light map tile (muted 1.47:1 / secondary 2.53:1 on thin glass; backdrop colours were estimated, not measured).
- Android: "Remove animations" (camera, strip scroll, pulse dot, press scale).

**Image caching**
- Avatars, history thumbnails, destination photos and the summary card load the second time with no network; editing a ride refreshes its thumbnail and card; sign-out empties the caches; deleting, leaving, or the leader deleting a ride removes its map and card; history thumbnails still appear offline.
- iOS only: LRU eviction, 304 revalidation and the format-version wipe were never exercised.

**Swipe back**
- iOS: swipe back from the lobby, the history summary and create/edit ride; dead on live navigation and the post-ride summary.
- Android: predictive back animation on Android 14+; Exit navigation / End ride remain the only ways out of guidance.

## Decisions needed

- **Google Maps terms** on caching static-map images. iOS keeps them 30 days (`ImageCategory`); Android honours the server's `max-age` (~1 day, floored at 5 min). The rendered summary card, with the map baked in, never expires on either. Confirm against the terms.
- **Voice default**: on for everyone (current), or ask on the first ride?
- **Units**: spoken and on-screen distances are metric only. Follow the device's units?
- **Mute button** sits bottom-trailing (iOS: in the convoy strip), not under the turn card as the plan said. Keep?
- **Regroup banner** stays up for everyone including the rider who called it. Keep?
- **Android touch targets**: `DsSize.touchTarget` is 44 dp, Android's minimum is 48 dp. Raising it changes the whole app.
- **Cache-clearing UI**: `clearAll()` exists and runs on sign-out/account deletion; no Settings control was added.

## Deliberately skipped

- Place photos stay on their own existing cache (iOS) because of Google's attribution and photo terms.
- History thumbnails are keyed by place, not ride, so deleting a ride does not purge them (they age out by TTL and the size cap); deleting one ride can cost another ride to the same place one photo refetch.
- iOS tests: the project has no test target and adding one means hand-editing the project file. Android has tests for the voice guide and split-alert logic.
- iOS `isDynamicIslandLimitedInWidth` (28 pt layout) is not in the SDK; compact views rely on `minimumScaleFactor`. Adopt when available.
- iOS Live Activity logo is the SF Symbol `location.north.fill` (the shipped `AppLogo` asset is a circle, i.e. a container). Swap in a bare mark if one exists.
- Android `setRequestPromotedOngoing` is not in the compileSdk 36.0 jar, so `"android.requestPromotedOngoing"` is set directly; use the setter when moving to 36.1.
- The Android notification is not shown during route preview, only once guidance starts. The `Reconnecting…` banner is shown in iOS route preview only; Android has no preview-time indication.
- The speech language is English only: the prompts are English strings, so the voice picks the rider's regional English accent rather than their language.
- Live Activity v2: server-pushed updates via ActivityKit push tokens when iOS suspends the app (needs a backend endpoint).
- Associated Domains capability work is still pending (see Architectural Decisions above); Phase 5's deep link needs the same setup for Universal Links.
- A cleanup of the unrelated untracked `design/IOS_HANDOFF.md` in the Android repo.

## Maintenance notes

- Re-sync the iOS string catalog in Xcode after any further user-facing copy change (last synced after Phase 4; "Then continue", "Everyone arrived" and the new split/arrival strings need the next sync).
- Keep the two `NavVoiceGuide` implementations, alert priorities and the values in `CLAUDE.md` ("Live navigation: values that must match on both platforms") in step.
