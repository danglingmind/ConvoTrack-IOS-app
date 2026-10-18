# ConvoTrack iOS redesign plan

Inputs: `convotrack-android/design/IOS_HANDOFF.md` (snapshot 2026-10-18, spec v2.4.0), the current
iOS source, and an `apple-design` HIG review. Citations look like `tab-bars.md › Best practices` and
point to the skill's HIG references. Anything marked *judgment* has no HIG citation behind it.

Scope: a visual and structural restyle. Networking, socket, ride-lifecycle and StoreKit logic stay
as they are.

---

## 1. Verdict on the handoff

**Rating: Good, with a few High fixes needed before it goes on iOS.** The handoff is careful. It
already chooses system fonts, SF Symbols, native sheets and alerts, Liquid Glass on floating chrome,
haptics, Reduce Motion and Dynamic Type. The colour tokens pass contrast (table in §3). The problems
are the places where a literal port of the Android layout breaks an iOS convention or an App Review
rule:

| # | Sev | Issue | Fix in this plan |
|---|---|---|---|
| 1 | **High** | The custom floating tab bar hides the active tab's label, and in the Lobby it shows **no** selected tab | Native iOS 26 `TabView`, tinted (§4.1) |
| 2 | **High** | The current `MainTabView` swaps tabs with a `switch`, so each tab's `NavigationStack` is rebuilt and its state is lost on every tab change | Same fix. `TabView` keeps every stack alive |
| 3 | **High** | Auth: Google is the lime primary button and Apple is a grey custom button built from the `apple.logo` SF Symbol | Use the system `SignInWithAppleButton`, white style, placed first and no smaller than Google (§5, Auth) |
| 4 | **High** | The QR scanner opens as a sheet on top of the Join sheet | Present it with `.fullScreenCover` (§5, Join) |
| 5 | **High** | Splash waits a fixed 3.5 s | End the splash when the auth check finishes (§5, Splash) |
| 6 | Medium | The handoff asks for ALL-CAPS button copy, including inside system alerts | Store strings in title case and apply `.textCase(.uppercase)` only to brand components. System alerts stay title case (§4.4) |
| 7 | Medium | Location disclosure is a 3-paragraph dialog that must offer two equal-weight choices, which a system alert can't do | Make it a sheet (§5, Dialogs) |
| 8 | Medium | `badgeSmall` 10 pt and the current `statLabel`/`captionSm` 10 pt are below the 11 pt iOS minimum | Raise them to 11 pt |
| 9 | Medium | Glass gets applied to cards ("GlassCard", `.ultraThinMaterial`) | Cards are content. Use the opaque `surface.card` fill and keep glass on chrome only (§4.2) |
| 10 | Medium | No answer for Increase Contrast | Add a high-contrast token variant (§3) |

The codebase today has 0 uses of `@ScaledMetric` or `dynamicTypeSize`, 0 Reduce Transparency
checks, 2 Reduce Motion checks, 5 `accessibilityLabel`s, about 170 raw `.system(size:)` calls and 161
raw `cornerRadius:` literals. The foundation phase exists because of these numbers.

---

## 2. Thesis and signature (craft lens)

**Thesis:** *your squad, on this road, right now.* Every screen should answer "where are we going
and who's with me".

**Template risk, called out honestly.** "Near-black with one acid-green accent" is one of the three
looks that generated interfaces fall into by default. Two things keep ConvoTrack out of that bucket,
so protect them:

1. **Real photography of the road and the destination.** That means the Places photo of the place
   you're actually riding to, not stock gradients.
2. **The lime route line as the one signature.** Spend the boldness there and repeat it on purpose:
   the splash trace, the `RouteTimeline` rail in Create/Edit, the map polyline, and the share-card
   distance. Elsewhere lime only marks the single next action and live state. This matches
   `branding.md › Best practices`: "Minimize its use on controls and instead use it intentionally
   for primary actions or status indicators."

**Remove these accessories** (*judgment*, backed by `branding.md`):
- Home's top-leading **logo badge.** `branding.md`: "Resist the temptation to display your logo
  throughout your app." The hero photo and serif headline already carry the brand.
- Auth's **SERVER ONLINE / SSL ENCRYPTED pills.** They are trust theatre and say nothing a rider can
  act on.
- **ConnectionStatusButton outside a ride.** On History and Create it reports a socket that isn't
  doing anything. Show it only while a ride session exists, or when the app is offline.

**Serif:** use New York via `.system(design: .serif)` and don't bundle Source Serif. It's free and
gets Dynamic Type and Bold Text automatically (`typography.md › Using system fonts`: "use
Font.Design.serif to get the New York font"). The difference from Android is negligible at hero
sizes. **Drop `Norwester`**, since the logo is an image.

---

## 3. Tokens: verified contrast

WCAG ratios computed from the handoff hex values. `card` and `cardQuiet` are composited over base.

| Text token | base `#060C12` | card `#111A24` | sheet `#0B131B` | Use |
|---|---|---|---|---|
| primary `#F5F7FA` | 18.3 | 16.3 | 17.4 | ✅ body |
| label `#D5D9DF` | 13.9 | 12.4 | 13.2 | ✅ |
| secondary `#B4B9C1` | 10.0 | 8.9 | 9.5 | ✅ |
| muted `#868C95` | 5.8 | 5.2 | 5.5 | ✅ body (AA) |
| subtle `#5C636D` | 3.2 | **2.9** | 3.1 | ❌ never text under 18 pt |
| disabled `#5D6670` | 3.4 | 3.0 | 3.2 | disabled controls only |
| accent `#CDEF1E` | 14.9 | 13.3 | 14.2 | ✅ |
| dangerStrong `#E5484D` | 5.0 | **4.5** | 4.8 | fills and bold labels only; borderline as text on card |
| onAccent on accent | 14.8 | | | ✅ |

Notes:
- **Accent `#CAF300` → `#CDEF1E` is a 1.02:1 difference, which nobody will see.** Change it anyway
  so the token names match Android, but don't expect a visual change.
- **Increase Contrast** (`accessibility.md › Vision`, `color.md › Best practices`): when
  `colorSchemeContrast == .increased`, borders go from hairline 10% to strong 28%, muted text becomes
  secondary, subtle becomes muted, and glass falls back to opaque.
- **Reduce Transparency:** every glass and translucent token uses the opaque `fallback` the JSON
  lists for it.
- Dark-only stays. `dark-mode.md` allows it "in rare cases", and a map-and-photo HUD app is one of
  them.

---

## 4. Platform decisions (where iOS departs from the Android port)

### 4.1 Tab bar: native `TabView` (recommended)

`tab-bars.md › Best practices`:
- "Include tab labels to help with navigation." The Android design hides the label on the active
  tab.
- "Make sure the tab bar is visible… If you hide the tab bar, people can forget which area of the
  app they're in." In the Lobby the Android design shows the bar with no tab selected.
- iOS: "A tab bar floats above content… on a Liquid Glass background." The system bar already *is*
  the floating glass pill the handoff describes.

Plan:
```swift
TabView(selection: $tab) {
    Tab("History", systemImage: "flag.fill", value: .history) { NavigationStack { RideHistoryView() } }
    Tab("Home",    systemImage: "location.north.fill", value: .home) { NavigationStack { HomeView() } }
    Tab("Profile", systemImage: "person.fill", value: .profile) { NavigationStack { ProfileView() } }
}
.tint(.accent)                         // selected icon + label lime, the rest monochrome
.tabViewStyle(.sidebarAdaptable)       // iPad gets a sidebar for free
```
- The Lobby is pushed inside the **Home** stack, so Home stays selected and that issue goes away.
- Navigation, Create/Edit, Summary: `.toolbar(.hidden, for: .tabBar)` on the pushed view. This
  replaces `AppState.isRideActive`, and the bar animates out the way the system does it.
- **Trade-off:** you lose the raised lime circle, the one place the iOS bar will look different from
  Android. You gain labels, VoiceOver tab traits, preserved stack state, the iPad sidebar, and the
  minimize-on-scroll behaviour. If you want the circle anyway, the fallback is a custom bar that
  **keeps the label under the active icon**, adds `.accessibilityAddTraits(.isSelected)` and the tab
  container trait, and is backed by a `TabView` with the system bar hidden so the stacks survive.

### 4.2 Glass discipline

`liquid-glass.md › Where the material belongs`: "Don't use Liquid Glass in the content layer."

| Element | Material |
|---|---|
| Tab bar, floating header buttons, nav HUD (turn card, bottom bar, leaderboard), destination pill, sheets | Liquid Glass. System components get it automatically. Custom ones use `.glassEffect(.regular.interactive(), in: .circle)` |
| Buttons floating over **photos** (Home, Lobby, Summary heroes) | `.glassEffect(.clear)`. The `photoFade` gradient doubles as the ~35% dimming layer, because sunset photos are bright |
| Cards, roster rows, ride rows, details list, stat tiles | **No glass.** Opaque `surface.card` / `cardQuiet` with a 0.5 pt hairline. Rename the component `SurfaceCard` so no one reaches for glass by name |
| Clustered header buttons (Lobby back / edit / more) | Wrap in a `GlassEffectContainer` |

### 4.3 Header: keep the system nav bar, make it transparent

The handoff hides the navigation bar and hand-draws the round buttons, then needs
`NavigationBackSwipe.swift` to bring swipe-back back. On iOS 26, toolbar items in a navigation bar
**already render as floating glass circles over content**. Use them:

```swift
.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
.toolbar {
    ToolbarItem(placement: .topBarTrailing) { ConnectionStatusButton() }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)   // keep edit / more as separate capsules
    ToolbarItem(placement: .topBarTrailing) { moreMenu }
}
```
You get the system back button, swipe-back, VoiceOver order, the scroll-edge effect, and an inline
title that appears on scroll. **Delete `NavigationBackSwipe.swift`.** It's a retroactive
`UINavigationController` delegate override that applies to every stack in the app. The serif hero
title stays in content, as the handoff wants.

### 4.4 Capitalisation and copy

- **Brand components** (buttons, eyebrows, section labels, badges, the HUD) render uppercase with
  tracking through `.textCase(.uppercase)`. **Strings live in `Localizable.xcstrings` in title or
  sentence case**, so translations work and VoiceOver doesn't read words like "SOLO" or "ETA" letter
  by letter.
- **System `.alert` and `.confirmationDialog` stay in title case** (`buttons.md`: "Using title-style
  capitalization"). Use the handoff's words with iOS casing: "Leave Ride", "Delete Ride", "Cancel".
  The wording matches the spec, so the two apps stay consistent.
- Tracking (4.4–4.6 pt) shrinks to about half at accessibility text sizes. Wide tracking at AX5
  makes labels wrap badly (*judgment*).

### 4.5 Dynamic Type

`typography.md › Supporting Dynamic Type`: "Make sure your app's layout adapts to all font sizes."

- Every `typography.styles.*` becomes a `ViewModifier` with `@ScaledMetric(relativeTo:)` driving
  `.font(.system(size:weight:design:))`. Map it like this: heroTitle → `.largeTitle`, titleLarge →
  `.title`, rowTitle → `.headline`, body → `.body`, eyebrow and badge → `.caption`, button →
  `.headline`.
- Data numbers use `.monospacedDigit()`. Fixed-height cards use `.minimumScaleFactor` (metricDisplay
  never goes below 26 pt) instead of clipping.
- **The ride HUD is capped at `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`** so the map stays
  visible. `typography.md › Conveying hierarchy`: "Prioritize important content when responding to
  text-size changes."
- At accessibility sizes, horizontal pairs stack vertically: the CREATE / JOIN pair, metric grids
  going from 2×2 to 1 column, and roster rows (`layout.md › Adaptability`).

### 4.6 Sheets and dialogs

`sheets.md`: one sheet at a time, a grabber when the sheet resizes, swipe to dismiss, and a way out
besides Done.

| Sheet | Detents | Notes |
|---|---|---|
| Join Ride | `.large` | Code input plus keyboard. Cancel at top-leading |
| Regroup | `.medium` | Segmented control and 2×2 tiles fit. Tiles fire immediately, so no Done |
| Remove rider | `.height(~340)` | Destructive button plus Cancel |
| Ride QR | `.medium` | |
| Location disclosure | `.medium`, not dismissable by drag | **Replaces the alert.** Two equal buttons as the spec rule requires. Three paragraphs is too long for an alert (`alerts.md`) |

All sheets get `.presentationDragIndicator(.visible)` and `.presentationBackground(.sheet)`. The
radius comes from the system.

Dialogs: end-ride ("Leave navigation or end the ride?") becomes a **`.confirmationDialog`**, because
it is a choice between two actions. It gets "Exit Navigation", "End Ride" (`.destructive`) and the
system Cancel. Delete/leave/delete-account use `.alert` with `role: .destructive` + `.cancel`. The
acknowledge variants use a single "OK".

---

## 5. Screen-by-screen plan

Handoff layout plus the iOS adjustments. Everything not listed follows `screenSpecs.<id>` exactly.

| Screen | iOS adjustments on top of the handoff |
|---|---|
| **Splash** | **Stop waiting a fixed 3.5 s.** `launching.md`: "Launch instantly." Dismiss when the Clerk session check resolves (minimum ~0.6 s so it doesn't flash). Show the stage-text cycle only if loading takes longer than ~1.2 s. Under Reduce Motion, show a static logo and route line. Set the Info.plist launch screen to the plain `#060C12` base with no text (`launching.md`: "Avoid including text on your launch screen"). |
| **Auth** | Road-sunset photo bundled locally (the current hero is a remote `googleusercontent` URL). **`SignInWithAppleButton(.continue)` with `.signInWithAppleButtonStyle(.white)`** first, 56 pt, radius 18 (`sign-in-with-apple.md`: white on dark backgrounds, "no smaller than other sign-in buttons"). Google below it at the same size as a dark button with outline, **not lime**. No lime on this screen, because neither provider is "the next action". Remove the status pills. |
| **Verify email** | `.textContentType(.oneTimeCode)` on `CodeInput` so the code autofills from Mail/Messages (`entering-data.md`). |
| **Home** | 300 pt hero, transparent nav bar, connection button only during a ride. **Remove the logo badge.** CREATE (lime, the one prominent action) / JOIN (secondary) pair stacks at AX sizes. `ActiveRideCard` is the content layer: opaque scrim, no glass. "See All" switches tabs through the `TabView` selection binding. |
| **History** | Header photo 150 pt. Serif "Ride history" in content. The inline nav title "History" appears on scroll. Stat strip goes from 3 columns to 1 at AX sizes. Rows get swipe actions only if the Android rows have them; don't invent. |
| **Profile** | Settings and Account groups are a styled `List`/`Form` section look built from `SettingsGroup`, with real `NavigationLink` chevrons. Notifications opens the system Settings URL. Delete Account uses `.alert` destructive with an inline error. |
| **Membership** | Keep the **3-day trial lead** (newer than the spec). "Secured by the App Store · Cancel anytime". Show the auto-renewal disclosure from `Product.displayPrice` and the subscription period, never a placeholder. Close button top-trailing (sheet convention). Restore · Terms · Privacy as text buttons, at least 44 pt tall. |
| **Join sheet** | `.large` detent. **The scanner opens with `.fullScreenCover`, not a nested `.sheet`.** `sheets.md` says to use full-screen for "camera views" and "display only one sheet at a time". `CodeInput` uses the `.asciiCapable` keyboard with auto-capitalisation characters. |
| **QR scanner** | Full-screen cover with a top-leading glass close button. Hint pill on clear glass. Camera denied state has "Open Settings". |
| **Create / Edit Ride** | Pushed with the tab bar hidden. Header: system back + inline title "New Ride" / "Edit Ride". The `RouteTimeline` rail is where the signature lime shows up. Max riders uses the **system `Stepper`**, tinted. Plan gating at the cap opens the paywall sheet. Sticky `SAVE RIDE` uses `.safeAreaInset(edge: .bottom)` with the fade. Delete Ride is a destructive button at the bottom with an `.alert`. |
| **Lobby** | Pushed in the Home stack, so **Home stays selected**. Tab bar visible under the sticky action, per your decision. Header buttons back / edit / more in a `GlassEffectContainer`. "More" is a `Menu` (Share invite, QR, Leave Ride destructive) instead of more circles. Roster status = badge word + colour. VoiceOver reads each row as one element ("Asha, Ride Leader, Ready"). |
| **Remove rider** | Sheet as specified. The destructive button is not the primary role (`buttons.md`: "Don't assign the primary role to a button that performs a destructive action"). |
| **Navigation HUD** | Map is content. Turn card, leaderboard and bottom bar are glass on the functional layer, and that's the only glass on screen. Tab bar hidden via `.toolbar(.hidden, for: .tabBar)`. Landscape stays driven by `verticalSizeClass` (already correct, `layout.md › Size classes`). HUD targets 48 pt. Banners announce through `AccessibilityNotification.Announcement`, with emergency at high priority. Dynamic Type capped at AX2. `isIdleTimerDisabled` stays. Apply the Google dark map style JSON in `GoogleMapView`. |
| **Regroup** | `.medium` sheet. `Picker(.segmented)` for meet point, tinted. Emergency tile uses danger fill + `exclamationmark.triangle.fill` + the word, so it never relies on colour alone. Emergency still emits `ride:emergency` (CLAUDE.md). |
| **Summary** | Terminal screen: no back, sticky Done. Award icons are SF Symbols. Share goes through the existing `ShareSheetPresenter` (system activity view). |
| **Share card** | Fixed-pixel poster, independent of Dynamic Type, which is correct for an exported image. Restyle the tokens only. |
| **Onboarding** | Restyle to the new tokens so it reads as a continuation of Splash: same base, serif headline, lime CTA. Keep the videos and paywall. Under Reduce Motion, show posters instead of autoplaying video (the poster assets already exist). |

---

## 6. Build sequence

Order: accessibility and foundation first, then conventions, then craft. Each phase builds and runs
before the next one starts.

**Phase 0 — Decisions (see §8).** About 10 minutes with you.

**Phase 1 — Foundation**
1. `convotrack/DesignSystem/Tokens.swift`: colours (with Increase Contrast and Reduce Transparency
   variants), gradients, spacing, radius, border widths, shadows, motion.
2. `Typography.swift`: the scaled text-style modifiers from §4.5.
3. **Compatibility shim:** point the old `Color.primaryFixed`, `surfaceContainer*`, `onSurface`… at
   the new tokens. The whole app changes palette in one commit and keeps building while screens move
   over one at a time. Delete the shim at the end.
4. Bundle `hero_riders_sunset_mirrored` and `hero_road_sunset` into `Assets.xcassets`. Drop
   Norwester.

**Phase 2 — App shell**
5. `MainTabView` → native `TabView` (§4.1). Replace `AppState.isRideActive` with
   `.toolbar(.hidden, for: .tabBar)`. Keep the join-sheet / deep-link logic unchanged.
6. Transparent nav bar + toolbar glass buttons (§4.3). Delete `NavigationBackSwipe.swift`.

**Phase 3 — Components** (Android names, one file per family, each with `#Preview` at default size
and at AX3)
7. Buttons → atoms (Avatar, StatusBadge, LiveIndicator…) → cards/rows → inputs → chrome → HUD.

**Phase 4 — Screens** in the handoff order: Home → History → Profile → Create/Edit → Lobby → Join +
Scanner → Summary → Membership → Auth/Splash/Onboarding → Navigation HUD + map style → Share card.

**Phase 5 — QA matrix** (every screen)

| Check | How |
|---|---|
| Largest text | Simulator Accessibility Inspector, AX5. No clipping. Primary action reachable |
| Reduce Motion / Transparency / Increase Contrast | Toggle each one, then all together |
| VoiceOver | Every icon button labelled. Roster and ride rows read as single elements. HUD banners announced |
| Sizes | iPhone SE (3rd gen), iPhone 17, 17 Pro Max, iPad (sidebar), Nav HUD in landscape |
| Parity | Side-by-side screenshot against the Android screen |
| Build | `xcodebuild -project convotrack.xcodeproj -scheme convotrack -destination 'platform=iOS Simulator,name=iPhone 17' build` |

No commits or pushes without asking.

---

## 7. Deliberate divergences from Android (to note in the spec)

1. Native tab bar: labels always shown, lime tint instead of the raised circle.
2. Sign in with Apple is first and uses the system white style. Google is not lime.
3. New York serif instead of Source Serif 4.
4. Title-case system alerts. End-ride is an action sheet.
5. Location disclosure is a sheet.
6. No logo badge on Home and no status pills on Auth. *Suggest the same for Android.*
7. 11 pt minimum for badges.
8. The splash finishes when work finishes. *Suggest the same for Android.*

---

## 8. Decisions needed from you

| # | Question | Recommendation |
|---|---|---|
| 1 | Tab bar: native `TabView` or custom lime-circle bar | **Native** (§4.1) |
| 2 | Serif: New York (system) or bundled Source Serif 4 | **New York** |
| 3 | Restyle onboarding in this pass? | **Yes**, in Phase 4 next to Splash/Auth, so first run looks like one product |
| 4 | Remove the Home logo badge, Auth status pills, and the out-of-ride connection button | **Yes** |
| 5 | Lobby keeps the tab bar under the sticky action (your earlier decision) | Keep. It's fine once Home shows as selected |

Out of scope, noted as an opportunity: a **Live Activity** for an active ride (leader distance,
ETA, regroup alerts on the Lock Screen and in the Dynamic Island) is the most iOS-native feature
ConvoTrack could add. It would be a separate effort after the restyle.
