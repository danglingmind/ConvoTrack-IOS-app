# Live navigation — backlog

Everything left behind from the live-navigation improvements (HIG review of `RideNavigationView`,
Android parity in `convotrack-android`). Source plan: the "Live Navigation Improvements — iOS Plan
& Android Parity" doc. Updated after Phase 4.

Status key: **todo** not started · **partial** done in part · **verify** built but never run on a
device/simulator · **decide** needs a product call.

## Phases not started

| # | Phase | Status | Notes |
| --- | --- | --- | --- |
| 4a | ARRIVAL stat shows clock time, minutes left beneath | done, **verify** | iOS 12/24h from locale; Android from the system setting. AM/PM dropped on the narrowest portrait layout |
| 4b | Convoy strip in the bottom bar, gap per card, tappable, count pill removed | done, **verify** | Portrait only: landscape keeps its side-panel order. The bar is taller; check the map still has enough room |
| 4c | Exit vs End: neutral "Exit navigation" for non-leaders | done, **verify** | |
| 4d | Edge chips as real buttons, 44 pt (iOS) / 48 dp (Android) | done, **verify** | |
| 5 | Live Activity (iOS) / ongoing notification with next turn (Android) | iOS done, **verify on device**; Android in progress | iOS: `ConvoTrackWidgets` extension, `RideLiveActivityController`, `convotrack://ride/<id>` route. See "Phase 5 iOS leftovers" |
| 6 | Use DesignSystem HUD components; reduce glass; Reduce Motion | in progress | See also "Phase 3 leftovers" below |

## Phase 5 iOS leftovers

- Not verified on a device: Lock Screen / Dynamic Island rendering, background updates while locked, tap-to-open from the Lock Screen, Increase Contrast, StandBy. The simulator build and install were checked only.
- Signing: the new App ID `danglingmind.convotrack.ConvoTrackWidgets` is registered on first signed device/archive build (automatic signing, team NJ5P2B5WZJ).
- `isDynamicIslandLimitedInWidth` (HIG 28 pt limited-width layout) is not in the current SDK, so compact views rely on `minimumScaleFactor` rather than a dedicated layout; adopt it when available.
- Logo mark is the SF Symbol `location.north.fill` (the shipped `AppLogo` asset is a circle, i.e. a container). Swap in a bare mark asset if one exists.
- v2: push-token updates (APNs) so the activity survives the app being killed; `NSSupportsLiveActivitiesFrequentUpdates` is on because turn distance changes every few seconds (app throttles to one update per 5 s).

## Phase 4 leftovers

- **verify** Arrival time against the device clock (and across a 12/24-hour change); AM/PM hidden on the narrowest width; "42m left" line height with the largest text size.
- **verify** Gap on each convoy card: sign and size match who is actually ahead/behind; "Level" within 25 m; offline riders dimmed; tapping a card peeks at that rider, tapping your own recentres.
- **verify** Edge chips no longer collide with the turn card now that the strip left the top; hit areas at 44/48 dp.
- Gap is derived from each rider's distance to the goal, so it is meaningless until a rider has posted a position (every rider is seeded with the full route distance, which reads as "Level").
- Landscape still shows the strip in the side panel above the banners, not at the bottom; the plan asked for "same order" only.
- iOS `DSLiveRiderCountPill` and Android `LiveRiderCountPill` were deleted; `liveRiderCount` on both view models is now unused.
- Android `BarStat`/iOS `barStat` gained a third line; the row is ~8 pt taller. Revisit if it crowds the Regroup/Exit buttons.

## Phase 1 leftovers

- **verify** Split alert on a two-simulator ride: names the right rider, gap within ~100 m of the leaderboard difference, number moves while the alert is up.
- **verify** Pin labels at default size and at the largest text size (iOS capped 1.5×, Android font scale capped 1.5×): no overlap with the route, wrapped names stay inside the plate.
- iOS string catalog was synced by Xcode after Phase 4 (commit `Sync string catalog`); re-sync after any further user-facing copy change.
- Android touch target: `DsSize.touchTarget` is 44 dp but Android's minimum is 48 dp. Decide whether to raise the token.
- Android `STOP_PIN_TOP_EXTENT_DP` and iOS `stopPinTopExtent` were raised to 104 by estimate; measure against a two-line destination name at the largest label size.

## Phase 2 leftovers (voice)

- **verify** On device: music ducking (Spotify, Apple Music, YouTube Music), prompts with screen locked and app backgrounded, prompts with the silent switch on (iOS), Bluetooth/helmet headset routing.
- **verify** Prompt thresholds (800 / 500 / 100 / 15 m, speed-scaled 20 s / 6 s) at city and highway speeds; arrival at 30 m.
- **decide** Voice on by default for everyone, or ask on first ride? Currently on by default.
- **decide** Units: metric only today ("metres", "kilometres"). Follow device locale?
- **decide** Mute button sits bottom-trailing above the stats bar, not under the turn card as the plan said (thumb reach; avoids the banner area). Confirm.
- Arrival prompt says "your destination", not the place name. Plumb the destination name into `NavVoiceGuide`.
- Speech language is hardcoded to en-US on both platforms.
- The 1.8 s delay before alert speech (to let the siren finish) is a constant copied from the reroute cue; tune it against the real siren length.
- Group-split voice goes to every rider including the one who is behind. Consider skipping it for that rider, or wording it for them ("You're falling behind").
- Android: split voice is keyed on the session's split state, which replays on re-entry, so re-opening navigation during an active split speaks it again.
- No unit tests. iOS has no test target and Android has no test dependencies; `NavVoiceGuide` is pure and the best first candidate on both. (A scratch harness checked the iOS logic only.)
- The "Then ↰" row on the turn card and its VoiceOver/TalkBack text are not visually checked.
- Keep the two `NavVoiceGuide` implementations, thresholds and alert priorities identical; add a shared constants table to `CLAUDE.md`.

## Phase 3 leftovers (alerts and camera)

- **verify** Fire emergency + split + regroup together on a three-device ride: only the emergency shows, with "+2 more"; the chip cycles in priority order; the turn card is never pushed down.
- **verify** Show / edge-chip peek: camera flies there, follow camera returns after about 10 s of riding, Resume works at any point. (Android future-dates `lastInteractionAt` by 7 s, iOS the equivalent; the 10 s is not tuned.)
- **verify** Edge chips for the regroup point and emergency: appear only when off-screen, are never clustered, and clear when the regroup resolves.
- **decide** The regroup banner now stays up for everyone including the rider who called it (previously the toast skipped the caller). Confirm that is wanted.
- Banner and chip transitions still use springs; honour Reduce Motion (iOS) and the "Remove animations" setting (Android) — part of Phase 6.
- iOS shows the "Reconnecting…" banner only in route preview; during guidance it is the turn-card status line. Android has no preview-time indication.
- iOS `landscapeTransientStack` is now a one-line wrapper around `alertSlot`; inline it. `DSBanner` tones `.connection` and `.split` are unused.
- iOS `CoordinationOverlayView` is still a prototype holding `GroupSplitAlert`; move the alert into `HUD.swift` and delete the file (Phase 6).
- Android `HudBanner`-based banners and the new `RegroupAlertBanner` duplicate the frame styling; fold into one.

## Cross-cutting

- Live Activity v2: server-pushed updates via ActivityKit push tokens when iOS suspends the app (needs a backend endpoint). Out of scope until v1 ships.
- Open Associated Domains capability work is still pending (see `CLAUDE.md`); it gates nothing here, but Phase 5's deep link depends on the same setup.
- Android leftovers for this plan live in the Android repo's working tree: `design/IOS_HANDOFF.md` is untracked and unrelated to this work.
