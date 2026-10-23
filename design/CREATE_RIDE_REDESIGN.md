# Create / Edit Ride — map-first redesign

Status: phases 1–7 built on iOS (Create and Edit Ride on the planner; Edit not yet exercised against a real ride). iOS first, then the Android port (`convotrack-android` `ui/ride/CreateRideScreen.kt`, `EditRideScreen.kt`, `RouteForm.kt`).

## Thesis

The screen's one job is **picking the road the pack will ride**. Today that road appears last, in a
220 pt card halfway down a scrolling form. The redesign makes the map the screen, so the route
is the first and loudest thing on it, and the form becomes a sheet that grows only as far as the
rider needs. The flow copies Google Maps' directions flow, which riders already know.

What it's remembered by: the lime route with its time bubbles. The rest is quiet: a dark map,
neutral glass, one lime button.

## Layout

```
┌──────────────────────────┐   ┌──────────────────────────┐
│ ‹ 🔍 Where are you riding? │   │ ‹ ● Your location     ⋮ │  ← stops card replaces
│ [Fuel] [Cafés] [Views]   │   │   ⚑ Nandi Hills       ⇅ │    the search pill
│                          │   │   + Add stop             │
│        full-bleed        │   │      ╲ +9 min            │
│          map             │   │   ━━━━[1h 42m]━━━ ⚑      │
│           ◉              │   │      ╲ +14 min           │
│                     [➤]  │   │                          │
├──────── grabber ─────────┤   ├──────── grabber ─────────┤
│ Plan a ride              │   │ 1h 42m (61 km)           │
│ 🕘 Nandi Hills     61 km │   │ Fastest · via NH 44      │
│ 🕘 Savandurga      58 km │   │ ✎ Ride to Nandi Hills  👥5│
└──────────────────────────┘   │ [   → Create ride      ] │
   1 · Explore (low detent)    └──────────────────────────┘
                                  3 · Preview (low detent)
```

Regular width (iPad, iPhone Duo inner display): the sheet becomes a leading floating panel
(~380 pt) over the map instead of a bottom sheet, same content.

## Flow

1. **Explore.** Map centred on the rider's location. Top: search pill. Sheet at the low detent:
   "Plan a ride" plus recent destinations.
2. **Search.** Tapping the pill opens full-screen results over the map, with the keyboard up.
   Results come in as you type. Rows: name with the match in bold, locality, distance. Also
   "Choose on map" and, for the start slot, "Your location".
3. **Destination picked.** Search closes, the route from *Your location* is drawn straight away,
   and the camera fits it above the sheet. The pill becomes the **stops card**: start,
   destination, swap, ⋮ (route options), + Add stop.
4. **Preview.** Low detent shows time, distance, the route's label ("Fastest · via NH 44"), the
   ride name (pre-filled "Ride to Nandi Hills", editable) with the rider count, and
   **Create ride**. A rider who accepts the defaults creates a ride in **3 taps**: search, result,
   Create ride.
5. **Alternatives.** Up to 3 routes. The selected one is lime with a glow; the others are grey and
   tappable, each with a "+N min" bubble at the point where it's furthest from the others. Tapping
   a line or a bubble selects it. The same choices are listed in the sheet at medium (VoiceOver
   can't reach a polyline).
6. **Stops.** + Add stop opens search for a new slot between start and destination. Rows reorder
   by drag handle and remove with ✕. With one or more stops Google returns no alternatives, so
   the bubbles go away (same as Google Maps on mobile).
7. **Details.** Drag the sheet to medium: ride name, max riders stepper with the plan line /
   Pro banner, the route list. Focusing the name field takes the sheet to large.
8. **Map gestures.** Long-press drops a pin, gets its address, and offers *Set as destination*,
   *Add as stop* or *Set as start*. The map is always interactive.

**Edit mode** is the same screen opened on a saved ride: stops card filled in, saved route
pre-selected (the existing `bestMatchIndex`), CTA "Save changes", and "Delete ride" moves
into a ⋯ menu at top right (destructive role, confirmation kept).

## Google Maps feature map

| Google Maps | ConvoTrack today | Redesign | Priority |
| --- | --- | --- | --- |
| Search pill floating over a full-bleed map | Search fields inside a scrolling form | Top glass pill over the map | P0 |
| Results as you type, recent searches | Text Search after 2 chars, 300 ms debounce, no recents | Same debounce, plus local recents (last 8 destinations) | P0 |
| Picking a place shows its card, then Directions | n/a | Skips the card: picking the destination draws the route at once (as you asked) | P0 |
| Start defaults to "Your location" | Start has to be searched | Defaults to Your location; reverse-geocoded to a real name at create time, so other riders don't see a waypoint called "Your location" | P0 |
| Route drawn immediately, camera fits it | Small 220 pt preview card | Full-bleed; camera insets follow the sheet height | P0 |
| Alternatives on the map with time bubbles, tap to choose | Grey lines (tappable only when alternatives exist) and chips under the map | Bubbles on the map plus a list in the sheet; chips removed | P0 |
| Swap start and destination | none | ⇅ button on the stops card | P1 |
| Add stop, drag to reorder, remove | Add and remove only | Add, reorder, remove | P1 |
| One request with all stops | n/a | Today it makes one Routes call **per leg** and stitches them; switch to a single `computeRoutes` with `intermediates` | P1 |
| Long-press to drop a pin | none | Drop a pin, then Set as destination / Add stop / Set as start | P1 |
| "Choose on map" (pan under a fixed crosshair) | none | In search results | P1 |
| Category chips (Gas, Restaurants…) | none | Fuel · Cafés · Viewpoints, search near the map centre | P2 |
| Route options: avoid tolls / highways / ferries | none | ⋮ on the stops card → Routes API `routeModifiers`; "Avoid highways" makes the scenic route easy | P2 |
| Two-wheeler mode | `DRIVE` | Routes API `TWO_WHEELER` where it's supported (India is); check it still returns alternatives | P2, check first |
| Search along the route ("fuel on the way") | none | Places `searchAlongRouteParameters` when adding a stop | P2 |
| Depart at / arrive by | none | **Out of scope**: no departure-time field in `POST /rides` | — |
| Drag the route to reshape it | (desktop only in Google) | Out of scope | — |
| Traffic layer | already on | Keep | — |

## HIG notes (apple-design review of the proposal)

- **Search at the top is right here.** `search-fields.md › Search in a toolbar`: "Place search at
  the top when itʼs important to defer to content at the bottom of the screen." The sheet owns the
  bottom. (Apple Maps puts search inside its sheet; Google Maps puts it on top. We go with Google,
  as asked, and the guideline backs that.)
- **Nonmodal sheet with detents and a grabber.** `sheets.md › Anatomy`: a nonmodal sheet lets
  people "use its functionality to affect the parent view without dismissing the sheet".
  `sheets.md › Mobile`: "Include a grabber in a resizable sheet… a grabber also works with
  VoiceOver." Detents: low (about 25%, it grows with Dynamic Type), medium, large. The sheet is
  never dismissed; you leave with Back.
- **Built in the view, not with `.sheet`.** The paywall (`PaywallPresenter`) and the delete
  confirmation present over this screen, and `sheets.md › Best practices` says "Display only one
  sheet at a time". A system `.sheet` here would stack sheets. So it's a custom `DSMapSheet`
  overlay that keeps the system sheet's sizing, grabber, corner radius and spring, and has
  `accessibilityAdjustableAction` to step through detents.
- **Interactive map.** `maps.md › Best practices`: "In general, make your map interactive." The
  current preview turns interaction off unless there are alternatives.
- **Selected route stands out.** `maps.md`: "Clearly identify elements that people select." Lime
  core and glow for the selected route, grey for the others, and the bubble label as well, so
  colour isn't the only signal.
- **Map logo stays visible.** `maps.md` (Apple's version of a rule Google's SDK terms also
  require): keep the logo above "the lowest resting position of the card". Set `GMSMapView.padding.bottom` to the
  low-detent height, and use the current detent's height for camera fits.
- **Glass only on floating controls** (`liquid-glass.md › Where the material belongs`): the
  search pill, stops card, recentre button and sheet. Chips and bubbles sit on the map
  as content markers, not glass. Reduce Transparency switches to the `DSStyle.opaque` values we
  already have.
- **Contrast (measured):** lime `#CDEF1E` on sheet `#0B131B` 14.2:1; muted `#868C95` on the sheet
  5.5:1 and on the glass `#101820` 5.3:1; button label `#0C0E02` on lime 14.8:1. All pass.
  **One fails:** `DS.Map.routeAlternative` (`#B4B9C1` at 40%) on the map background is
  **2.5:1**, under the 3:1 WCAG 1.4.11 asks for non-text graphics (my judgment, not a HIG
  rule). Raise it to 55% (3.6:1); now that alternatives are the main choice on the map, they
  have to be visible.
- **Targets:** stops-card row actions (✕, handle, swap, ⋮) are 44 × 44 pt even where the icon is
  18 pt. Route bubbles get a 44 pt hit area.
- **Reduce Motion:** camera fits and sheet detent changes happen without animation.

## Architecture

- **`RidePlannerModel` (`@Observable`)**, shared by create and edit: `stops: [RouteStop]` (start,
  middles, destination as one ordered array), `routes: [RouteOption]`, `selectedRouteIndex`,
  `detent`, `searchSlot: StopSlot?`, `routeOptions` (avoid tolls / highways). It owns the
  route calculation that is copied today in both `CreateRideView.recalculateRoute` and
  `EditRideView.recalculateRoute`, and cancels stale requests (fast edits now race).
- **`RidePlannerView`**: ZStack of `GoogleMapView` (full-bleed, `isInteractive: true`), the top
  `PlannerSearchPill` / `PlannerStopsCard`, the `PlannerSearchOverlay`, the `DSMapSheet`, and
  the long-press pin card. `CreateRideView` and `EditRideView` become thin wrappers that supply
  the mode, the CTA and save/delete.
- **`GoogleMapView` additions:** `mapPadding: UIEdgeInsets` (logo and camera), `onLongPress`,
  route bubbles as markers (position = the point of the polyline furthest from the selected
  route), and an "idle camera centre" callback for "Choose on map".
- **`GoogleDirectionsService`:** `route(stops:)` sends a single request with `intermediates` and
  `routeModifiers`. `alternativeRoutes` is unchanged except for `routeModifiers`.
- **`GooglePlacesService`:** add reverse geocoding (Geocoding API) for long-press and "Your
  location". Optional: switch to Places Autocomplete (New) with session tokens. It's cheaper
  per keystroke than Text Search and is what the ride-demo skill already checks place names
  against.
- **Recents:** `UserDefaults`, last 8 destinations `{name, lat, lng, address}`. Stays on device.
- **Removed:** `RideRouteForm`, `StopSearchField` and their preview card (`RideFormComponents.swift`).
- **API contract unchanged.** `POST /rides` and `PATCH /rides/{id}` take the same body;
  waypoint names must be real place names (hence reverse geocoding).
- **Analytics:** no new events needed. If we want to measure the flow, add `route_alternative_selected` /
  `stop_added` to `docs/analytics.md` and both `Analytics.Event` enums (no coordinates or
  place names in properties).

## Phases

1. **Model and services.** `RidePlannerModel`; single-request directions with intermediates;
   reverse geocode; recents store. No UI change yet.
2. **Map canvas and search.** Full-bleed map, search pill, full-screen results, destination
   picked → route from Your location, camera fit.
3. **Sheet.** `DSMapSheet` (low / medium / large, grabber, VoiceOver adjustable, Dynamic Type),
   map padding tied to the sheet, preview content, name field, rider stepper, Create ride.
4. **Stops card.** Start, destination, swap, add, reorder, remove; the search overlay for each slot.
5. **Alternatives on the map.** Bubbles, tap to select, list in the sheet, alternative line
   contrast raised to 55%.
6. **Map gestures.** Long-press pin card, Choose on map.
7. **Edit mode.** Same view with the ride pre-filled, Save changes, ⋯ → Delete ride; delete
   `EditRideView` body and `RideFormComponents.swift`.
8. **P2 extras.** Category chips, avoid tolls / highways, search along route, two-wheeler check.
9. **Android port.** Compose `BottomSheetScaffold` (partial expansion = low detent) with
   maps-compose `contentPadding` for the logo; same model shape in the ViewModel.
10. **Verification.** Build, run on the iPhone 17 simulator, walk create and edit, VoiceOver
    pass, largest Dynamic Type, Reduce Motion / Transparency.
