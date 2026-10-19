# Live navigation — backlog

Everything left behind from the live-navigation improvements (HIG review of `RideNavigationView`,
Android parity in `convotrack-android`). Source plan: the "Live Navigation Improvements — iOS Plan
& Android Parity" doc. Updated after Phase 3.

Status key: **todo** not started · **partial** done in part · **verify** built but never run on a
device/simulator · **decide** needs a product call.

## Phases not started

| # | Phase | Status | Notes |
| --- | --- | --- | --- |
| 4a | ARRIVAL stat shows clock time, minutes left beneath | todo | `etaString` still returns a duration labelled "ETA" (iOS + Android) |
| 4b | Convoy strip: move above stats bar, show gap, tappable, drop last name and rider-count pill | todo | Android cards are already tappable; iOS cards are not |
| 4c | Exit vs End: neutral "Exit navigation" button for non-leaders | todo | iOS `endRideButton`/`landscapeButtonsRow`; Android `RideNavigationScreen` `onEndRide` |
| 4d | Edge chips as real buttons, 44 pt (iOS) / 48 dp (Android) | partial | Done only for the new regroup/emergency chips on iOS. Rider chips on both platforms, and the new chips on Android, still use a bare tap/clickable |
| 5 | Live Activity (iOS) / ongoing notification with next turn (Android) | todo | Needs a Widget Extension target and `NSSupportsLiveActivities`; add a `convotrack://ride/<id>` route to `DeepLinkRouter` |
| 6 | Use DesignSystem HUD components; reduce glass; Reduce Motion | todo | See also "Phase 3 leftovers" below |

## Phase 1 leftovers

- **verify** Split alert on a two-simulator ride: names the right rider, gap within ~100 m of the leaderboard difference, number moves while the alert is up.
- **verify** Pin labels at default size and at the largest text size (iOS capped 1.5×, Android font scale capped 1.5×): no overlap with the route, wrapped names stay inside the plate.
- iOS `Localizable.xcstrings` still holds the removed "2.4 km behind" and "Signal strength dropping rapidly." entries; new strings (`A rider`, group-split and regroup voice text) are not catalogued. Run a string-catalog sync.
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
