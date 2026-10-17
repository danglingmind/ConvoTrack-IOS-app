# Onboarding + Paywall Flow — Design Plan

Status: v3. iOS flow implemented with code-drawn placeholder artwork (no footage yet); backend
migration written but **not yet applied**; App Store Connect trial **not yet configured**.

## 0. Plan changes (v3)

The free offering is three terms that apply together, in this order:

1. **3-day free trial of Pro** (App Store introductory offer, free, 3 days)
2. then the free plan: **3 rides a month** (was 10; `migrations/014_reduce_free_plan_monthly_rides.sql`, applied)
3. and **up to 5 riders per ride** (unchanged)

Paywall presentation: the trial leads (a "3 DAYS FREE" badge under the title, "3 days free, then
billed every …" on each plan card, and a "START 3 DAYS FREE" CTA). The price stays the dominant
element on each card (Guideline 3.1.2). Terms 2 and 3 sit as a footnote under the CTA: *"After the
trial, the free plan includes 3 rides a month and up to 5 riders per ride."* — numbers read from the
server plan, not hardcoded. Nothing about a trial is shown unless the account is actually
eligible for the offer; ineligible accounts see "Free plan: …" instead.

Rollout notes:
- The migration changes the limit for every existing free user at once. Anyone who has already
  taken part in 3+ rides this calendar month is locked out immediately (`quotaService.ts` counts
  the current month). Decide whether to ship it at the start of a month or grandfather existing users.
- The trial is live in App Store Connect on both subscriptions (3 days, free, all 175 territories)
  and mirrored in `convotrack.storekit` for local testing. It needs **no client code**: `MembershipStore` / `MembershipView` already read the
  introductory offer and the CTA becomes "START 3 DAYS FREE" and the disclosure gains
  "Includes a free 3 days trial, then …" only when the account is eligible. Configure it in App
  Store Connect on both subscriptions (Pricing → Introductory Offers → Free, 3 days).
- The paywall's free-plan line reads `maxRidersPerRide` / `monthlyLimit` from `fetchMe`, so it
  shows 3 and 5 automatically once the migration is applied.

## 1. Where it slots into the app

Today: `ContentView` → `SplashView` (3.5 s) → `AuthView` → `MainTabView`.
`MembershipView` is only reachable from Profile / CreateRide / EditRide.

Proposed:

```
Launch screen → session check (Clerk) happens HERE, not after an animation
  ├─ signed in + onboarding done ........................ straight to MainTabView (no splash)
  ├─ opened via join link (DeepLinkRouter.pendingJoinCode) ... straight to AuthView, then the join sheet
  └─ first launch
       SplashView (1.8 s, first launch only, start of onboarding)
       OnboardingFlowView
         1. VALUE   Every rider. One map.           (video)
         2. VALUE   Nobody gets left behind.        (video)
         3. VALUE   One link. Everyone's in.        (video)
         4. QUESTION How big is your usual pack?    (still frame)
         5. AUTH    existing AuthView as a page, with one line of benefit copy
         6. PAYWALL MembershipView(.onboarding)
       MainTabView
         └─ LOCATION request at first ride start (optionally primed — see §5)
```

Every onboarding page carries **Skip** (top trailing, 44 × 44 pt target). Skip jumps to
Auth, not past it. The old "ride, remembered" screen moved out of the flow — see §3.

### Why this order

- **Value before auth** is the biggest lever; the old flow showed auth second with no argument.
- **Auth before paywall** is a technical constraint, not a preference:
  `MembershipStore.activateOnServer` → `APIClient.activateMembership` needs a Clerk token, so a
  pre-auth purchase leaves a local entitlement with no server row until the next launch.
  HIG `managing-accounts.md` says to delay sign-in as long as possible; we honour that
  everywhere we can (join-link users, §1 tree) and accept it here for the one reason above.
  Auth gets a single line of benefit copy ("Sign in to keep your rides and ride with others").
- **Location last, in context.** `privacy.md`: request when the feature needs it. The need is
  first-ride start. Ask *When In Use* there; escalate to *Always* only when the user
  turns on background tracking.
- **Notifications: not in onboarding.** Ask on entering the first ride lobby.
- **Splash only on first launch.** `launching.md`: put the splash at the start of onboarding;
  returning users should see their app, not an animation.

## 2. The question screen

One question, one tap, optional-feeling:

> **HOW BIG IS YOUR USUAL PACK?**  *So we can set up your first ride.*
> `Just me + 1` · `3–5 riders` · `6–12 riders` · `12+ riders` · `Not sure`

Rules (these are requirements, not suggestions):

1. **The answer must be used.** Persist `OnboardingAnswers.packSize` and prefill `maxRiders`
   in `CreateRideView`. A question that changes nothing is manipulation, not onboarding.
2. **Personalized paywall copy only when the answer actually hits the free cap**
   (`maxRidersPerRide`, currently 5). "3–5", "Just me + 1" and "Not sure" get the neutral
   headline; don't sell a cap the user won't hit.
3. The copy states its purpose in the UI (subtitle above), and "Not sure" is always offered.

## 3. The three value screens (+ one deferred)

Each page: full-bleed looping video, bottom-anchored text block, eyebrow, headline, one line of
body, `Continue`. Page dots (no separate segmented progress bar). **Skip on every page.**

| # | Eyebrow | Headline | Body | Footage |
|---|---------|----------|------|---------|
| 1 | LIVE TRACKING | **Every rider. One map.** | See where your whole pack is, second by second — even the ones you can't see. | Nav map, 3–4 rider markers on the lime polyline, off-screen edge chips |
| 2 | REGROUP | **Nobody gets left behind.** | Call a regroup and every phone knows where to wait. One tap for emergencies. | `RegroupBottomSheet` → broadcast → markers converge |
| 3 | ONE LINK | **One link. Everyone's in.** | Share a link. They're on the map. No group chat chaos. | Share sheet → join sheet prefilled → rider appears in lobby |

**Deferred: "The ride, remembered"** (ride summary) is no longer a pre-sign-in screen. It becomes a
contextual TipKit tip / one-time card after the user's first completed ride
(`onboarding.md`: context-specific tips beat a long prerequisite flow).

Copy rules: headline ≤ 4 words; body ≤ 14 words. **Eyebrow is `onSurfaceVariant`, not lime** —
lime is reserved for the primary CTA and the route line inside the footage so that it keeps
meaning "go". Screens 1 and 2 are the differentiators versus sharing a location in a maps app;
don't reorder them.

### Typography, Dynamic Type, layout (new — required)

The app theme uses fixed `Font.system(size:)` styles that do **not** scale. Onboarding does not
inherit that:

- Use scalable text for all onboarding copy: headline `.largeTitle.bold()`, body `.body`,
  eyebrow `.caption.weight(.bold)`; or `@ScaledMetric` sizes derived from the theme values.
  Never use `.headlineLg` / `.bodyMd` as-is here.
- Each page's text block lives in a `ScrollView` (bottom-anchored via `defaultScrollAnchor`) so it
  stays reachable at the largest accessibility sizes. At accessibility sizes the CTA stays
  pinned below the scroll area.
- CTAs use `minHeight: 56`, not a fixed `frame(height: 56)`.
- Test checklist: Larger Accessibility Text at max, Bold Text, Increase Contrast, Reduce
  Transparency, smallest supported iPhone, landscape (the app is portrait-only outside
  navigation, so onboarding locks portrait).

### Text over moving video (new — required)

- Bottom gradient scrim, `surfaceDim` from 0 → ~0.8 opacity, text block in the lower 40 %.
- Verify contrast against the **brightest frame** of each clip (white roads and satellite tiles),
  not the average. Target ≥ 4.5:1 for body text, with Increase Contrast on.
- Where a clip can't meet that, darken the clip in the encode, not the type.

## 4. Video production & playback

**Footage comes from the `ride-demo` skill** — real multi-rider footage on a real route.
One recording device per pass (three concurrent encoders dropped >50 % of frames).

Per clip: 6–8 s, seamless loop; 1080 × 2340 H.265 `.mp4`; **no audio track**; ≤ 1.5 MB each,
≤ 4.5 MB total (three clips); bundled, never downloaded (`onboarding.md`: no download wait).
Ship a first-frame `.heic` poster per clip.

Playback (`LoopingVideoView: UIViewRepresentable`):
- `AVQueuePlayer` + `AVPlayerLooper`, `AVPlayerLayer` `.resizeAspectFill`.
- Audio session category `.ambient` with `.mixWithOthers`, never activated by us; the files have no
  audio anyway. Background music must keep playing.
- Poster underneath until `isReadyForDisplay`, to avoid a black flash.
- Preload page *n+1* only; pause on page change and when the app backgrounds.

### Motion & accessibility (replaces the old one-line fallback)

Show the **poster, not video**, when any of these is true:
`UIAccessibility.isReduceMotionEnabled`, `!UIAccessibility.isVideoAutoplayEnabled`,
`ProcessInfo.isLowPowerModeEnabled` (Low Power is our choice, not an Apple rule).

Also:
- **A visible pause/play control** (44 × 44 pt) on every video page.
  `accessibility.md`: don't autoplay video without controls to start and stop it.
- **Reduce Motion:** page transitions become cross-fades (no horizontal slide, no parallax, no
  scale), and the Continue button's glow pulse is static.
- **Dim Flashing Lights:** the regroup clip contains a broadcast flash. Audit every clip for
  flashing; reduce in the encode, and honour the system setting by showing the poster.
- **VoiceOver:** the video layer is `accessibilityHidden`; the visible copy is the content.
  Each page announces "Page 2 of 3" via the page control. Describe the footage in one sentence on
  the container's `accessibilityLabel` ("Map showing four riders moving along a route").
- All meaning lives in the text; the video is decoration plus demonstration.

## 5. Location request

Preferred: **no priming screen** — let the system prompt appear when the user taps *Start ride*
(or *Create ride*), where the need is self-evident (`privacy.md`).

If a priming screen is kept (it measurably helps grant rate), these are hard rules from
`privacy.md › Requesting permission`; breaking them is an App Review rejection:

- **One button, titled `Continue`** — never "Allow" or "Enable Location".
- **No Skip, Not now, or close** on that screen.
- It explains the benefit in the body copy and then opens the system alert immediately.
- Purpose strings (`Info.plist`) stay specific and in sentence case with a period. The existing
  *When In Use* string is fine; the *Always* string is escalated at background tracking only.

## 6. The onboarding paywall

Reuse `MembershipView` with `presentation: .sheet | .onboarding` rather than a second StoreKit
surface — it already handles storefront changes, intro-offer eligibility, the 3.1.2
auto-renewal disclosure, restore and retry.

`.onboarding` changes only:

- **Headline.** Neutral by default ("Ride bigger. Keep every ride."). Personalized only when the
  pack-size answer exceeds the free cap: "12+" → *"Up to 25 riders on one map."*, "6–12" →
  *"Your pack is bigger than 5."*.
- **Benefit order** follows the answer (cap first for big packs, history/analytics for small).
- **Background:** the real map footage (poster frame, blurred) instead of the generic crown hero.
- **Dismiss, visible from frame one:** a 44 × 44 pt close control (the current 32 × 32 `xmark`
  is too small) **and** a text button `Continue with Free`.
- **Free-plan line, always shown above the plans, read from the server plan** (`fetchMe` →
  `MembershipPlanInfo.maxRidersPerRide` and `.monthlyLimit`) — e.g. "Free: up to 5 riders per
  ride, N rides a month." Never hardcode the numbers, and never label the free option in a
  way that hides the monthly limit. *(Open item: confirm the actual
  `monthly_ride_participation_limit` for the free plan in the backend before writing final copy.)*
- Yearly preselected with the existing `bestValuePlan` badge and per-month equivalent.

### Legal text & contrast — fix in `MembershipView` (applies to the sheet too)

Computed on `#131313`:

| Element | Today | Contrast | Fix |
|---|---|---|---|
| Auto-renewal disclosure | `onSurfaceVariant` @ 0.42 | 2.86 : 1 | full `onSurfaceVariant` (10.9 : 1) |
| Restore / Terms / Privacy | @ 0.38 | 2.57 : 1 | full `onSurfaceVariant` |
| "Secured by Apple · Cancel anytime" | @ 0.45 | 3.13 : 1 | full `onSurfaceVariant` |

All are 12 pt text, which needs 4.5 : 1. The disclosure and Restore link are exactly what App
Review reads on a paywall; faint legal text invites a 3.1.2 rejection. Disclosure and legal links
must also scale with Dynamic Type and wrap (no truncation).

### Recommendation: add a 7-day introductory offer in App Store Connect

`MembershipStore.introductoryOffer` and its disclosure plumbing are already written and dormant.
A trial-led paywall typically converts materially better than price-first. Console change plus
CTA copy swap; no new client code. Judge on day-30 retained revenue, not checkout rate.

### Second chance, placed once

1. `CreateRideView` / `EditRideView` rider cap — already wired.
2. After the **first completed ride summary**: *"You rode with 4. ConvoTrack Pro carries 25."*
   Shown once, ever. Also where the deferred "ride, remembered" tip appears.

## 7. Files

New:
- `Onboarding/OnboardingFlowView.swift` — host, page control, routing, Skip
- `Onboarding/OnboardingPage.swift` — layout (video, scrim, scalable text in ScrollView)
- `Onboarding/LoopingVideoView.swift` — AVPlayerLooper wrapper + playback policy
- `Onboarding/PackSizeQuestionView.swift`
- `Onboarding/LocationPrimingView.swift` — optional, single `Continue` button
- `Onboarding/OnboardingState.swift` — `hasCompletedOnboarding`, `packSize`,
  `onboardingVersion`, `hasSeenPostRidePaywall`
- `Resources/Onboarding/*.mp4` + `*.heic`

Changed:
- `ContentView` — root decides launch → (splash →) onboarding → main; replaces the nested
  `fullScreenCover` chain (Splash→Auth→MainTab), which can't be entered mid-way
- `SplashView` — 1.8 s, first launch only, no `fullScreenCover`
- `AuthView` — embeddable page + benefit line; confirm Apple button is the system
  `SignInWithAppleButton`, at least as prominent as Google
- `MembershipView` — `presentation` parameter, 44 pt close, Free line, legal-text contrast
- `CreateRideView` — prefill `maxRiders` from `packSize`

## 8. Instrumentation

`onboarding_step_view/advance/skip`, `paywall_view/dismiss`, `purchase_start/success/cancel`,
`location_grant/deny`, `join_link_shortcut_used`.

A-B candidates, in order of expected effect: trial vs price-first · paywall before vs after
auth · 3 screens vs 2 · question before vs after paywall.
**Not** a test variant: hiding, delaying or removing the paywall dismiss control (Guideline 3.1.1
risk).

## 9. Android parity

Same flow and copy. `ExoPlayer` (`repeatMode = ALL`, no audio focus request) for
`AVPlayerLooper`; Play Billing for StoreKit; `HorizontalPager` for the page host. Honour
`Settings.Global.ANIMATOR_DURATION_SCALE == 0` as the Reduce Motion equivalent and the
system font scale for text. The single-`Continue` priming rule is an Apple review rule; on
Android it's a good practice, not a requirement.

## 10. Review checklist before shipping

- [ ] Max Dynamic Type: no clipped copy, CTA reachable on every page
- [ ] Reduce Motion + Low Power + autoplay off → posters, fades, no sliding
- [ ] Pause/play control present and labelled for VoiceOver
- [ ] Brightest-frame contrast ≥ 4.5 : 1 under Increase Contrast
- [ ] Legal text ≥ 4.5 : 1; close/Skip/pause targets ≥ 44 × 44
- [ ] Priming screen (if kept) has exactly one `Continue` button
- [ ] Free-plan limits shown from server values; no hidden monthly cap
- [ ] Join-link users skip the value pages
- [ ] Returning signed-in users never see splash or onboarding
