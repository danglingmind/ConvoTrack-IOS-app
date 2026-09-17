# Tap coordinates — device points (402×874)

Valid for iPhone 17 / 17 Pro in **Point Accurate** mode with **bezels off**.
`shot.sh` writes PNGs at exactly 402×874, so you can read new coordinates
straight off a screenshot with no conversion.

## Verified

| Screen | Element | Coord |
|---|---|---|
| Home | CREATE RIDE | 107, 162 |
| Home | JOIN RIDE | 294, 162 |
| Bottom nav | Home / Track / Profile | 98,833 · 201,833 · 302,833 |
| Create Ride | Ride title field | 201, 182 |
| Create Ride | Start location field | 214, 307 |
| Create Ride | 1st autocomplete suggestion | 214, 362 |
| Create Ride | Destination field | 214, 421 |
| Create Ride | 1st autocomplete suggestion | 214, 476 |
| Create Ride | scroll down | swipe 100,470 → 100,150 |
| Create Ride | CREATE RIDE button (after scroll) | 201, 726 |
| Lobby | START RIDE / MARK AS READY / RESUME NAVIGATION | 201, 751 |
| Pre-nav | START NAVIGATION | 201, 768 |
| Navigation | end-ride button (red, bottom-right) | 357, 792 |
| End dialog | Exit Navigation *(non-destructive)* | 201, 567 |
| End dialog | **End Ride** *(irreversible)* | 201, 623 |
| Deep-link "Open in ConvoTrack?" | Open | 275, 476 |
| Join sheet | JOIN RIDE | 201, 510 |
| Summary / pushed views | back arrow | 38, 84 |
| Split alert | Ignore / Regroup | 117, 550 · 285, 550 |

## Traps

- **Swiping on the route-preview map pans the map, it does not scroll the page.**
  Scroll the Create Ride form only from x≈100, y≈470 (the "ROUTE PREVIEW" label strip).
- **CREATE RIDE's y depends on scroll position.** The one step that always needs a
  verification screenshot before tapping.
- **The navigation screen has no back button, by design.** Tapping 38,84 there does
  nothing. Exit via 357,792 → "Exit Navigation" (201,567).
- **Tapping the already-active bottom tab does not pop a pushed view.** To leave the
  summary, use the back arrow (38,84).
- **The end-ride dialog is a centered card, not a bottom action sheet**, and shows no
  visible Cancel — dismiss by tapping the dimmed backdrop (e.g. 45,730).

## Joining by invite code

Faster and more reliable than typing:

```bash
xcrun simctl openurl <udid> "convotrack://join/ABC123"   # -> "Open" (275,476)
```
`DeepLinkRouter` (`ConvoTrackApp.swift`) accepts both `convotrack://join/CODE` and
`https://convotrack.in/join/CODE`, uppercases, strips non-alphanumerics, requires 6 chars.
