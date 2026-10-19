# Trial-first freemium + Pro conversion — implementation plan

## The model (decided 2026-10-19)

| | Rule |
| --- | --- |
| **Trial** | App-level, **3 days from account creation**, no card, no store involvement. Server stores `users.trial_ends_at`. |
| **During trial** | Free-plan limits still apply: 3 rides/month (`monthlyLimit`), 5 riders/ride (`maxRidersPerRide`). |
| **After trial, not Pro** | **Cannot create or join any new ride.** Pro is the only way forward. |
| **Existing users** | Get a fresh 3 days counted from the moment enforcement is switched on (not from original sign-up). |
| **Messaging priority** | 1) trial countdown / trial ended → 2) rider cap → 3) monthly rides. Monthly/rider limits are secondary copy only. |

Consequences that shape the plan:
- Enforcement **must be server-side** (an old app or modified client must not bypass it) and **switchable** by env flag, so the app update ships before the wall goes up.
- The **store-level 3-day free trial is retired** (App Store Connect intro offers + Play free-trial offer + `convotrack.storekit`). Otherwise riders get "3 free days" twice and the copy contradicts itself. The paywall's trial line already fails closed (`MembershipView.swift:568-580`), so it disappears automatically once no intro offer exists.
- A rider **already inside a ride** when the trial expires is never kicked out: only `POST /rides` and `POST /rides/:rideId/join` are gated. `start`/`pause`/`resume`/`end`/`leave` stay open.

---

## Phase 0 — Discovery (facts later phases rely on)

### Backend (`/Users/ricky/Workspace/convoy-backend`)
- Gate point: `src/services/quotaService.ts` `canUserParticipate(userId)` → `{ allowed, used, limit, plan }`. Called by `POST /rides` (`src/routes/rides.ts:303`, check at `:373`) and `POST /rides/:rideId/join` (`:915`, check at `:953`); both return 403 `QUOTA_EXCEEDED` with `used`/`limit`.
- User creation: `src/db/userRepo.ts` `upsertUser()` — `INSERT … created_at now() ON CONFLICT DO UPDATE`.
- `GET /users/me`: `src/routes/memberships.ts:76-130`, returns `plan { code, isPremium, maxRidersPerRide, monthlyLimit?, rideHistoryDays, analyticsEnabled }`. **No trial or usage fields today.**
- Migrations: `migrations/001…014_*.sql` → next is `015_`.
- Contract: `openapi.json` (CLAUDE.md: always update it with the route schema).

### iOS (`convotrack/`)
- `Services/MembershipStore.swift`: `isPremium`, `products`, `introductoryOffer(for:)`. Server plan merged in `ConvoTrackApp.swift:128-138` (launch only).
- `MembershipView.swift`: `MembershipPresentation { .sheet, .onboarding }`; fetches `fetchMe()` itself (`:80-84`); trial copy derived from StoreKit offer only.
- Onboarding paywall: `ContentView.swift:82-92`.
- Existing upsells: Profile `DSPromoBanner` (`ProfileView.swift:55-60`), rider-cap banner (`RideFormComponents.swift:393-414`), caps hardcoded `isPremium ? 25 : 5` (`CreateRideView.swift:16`, `EditRideView.swift:21`).
- Errors: `QUOTA_EXCEEDED` text-only at `HomeView.swift:628`; `CreateRideView` alert (`:135`, `:289`); `JoinRideView` inline error (`:229-232`). Error code mapping in `Networking/UserFacingError.swift`.
- Home: hero with `DSActionButtonPair(createAction:joinAction:)` (`HomeView.swift:153-173`); toolbar leading slot free.
- Global sheets: `MainTabView.swift` (`JoinSheetContext` pattern `:7-10`, settle delay `:74-80`).
- Persistence pattern: `Onboarding/OnboardingState.swift` (UserDefaults enum).
- DS: `DSPromoBanner` (`Cards.swift:525`), `DSChip`/`DSStatusBadge`/`DSLeaderBadge` (`Feedback.swift`), `DSPillButton`, `DSBenefitTile`, `DSIconDisc`.

### Android (`/Users/ricky/Workspace/convotrack-android/app/src/main/java/com/danglingmind/convotrack/`)
- `data/billing/BillingManager.kt:189-209` `purchase()` uses `subscriptionOfferDetails?.firstOrNull()?.offerToken` — **picks whatever offer Play lists first** (trial or base plan, non-deterministic), and no screen ever tells the rider a trial exists.
- Paywall `ui/membership/MembershipScreen.kt`; gating `ui/common/PlanGate.kt`; hosts `ui/main/MainScreen.kt`, `ui/profile/ProfileScreen.kt`, `ui/ride/CreateRideScreen.kt`, `RouteForm.kt`; models `data/net/Models.kt`.

### Anti-patterns (all phases)
- Client clock never decides access — always the server's `trialEndsAt` + server 403. Client countdown is display only.
- No hardcoded "3 days" / "5" / "25" / prices in copy — read from `/users/me` and `Product.displayPrice`.
- No upsell to `isPremium == true`; no popup during an active ride or over a pending deep link.
- No purchase button outside the paywall (keeps App Store 3.1.2 price/terms disclosure in one place).
- Don't remove the fail-closed StoreKit trial logic in `MembershipView` — it's what hides store-trial copy once the offer is gone.
- `Localizable.xcstrings` has uncommitted edits — merge, don't overwrite.

---

## Phase 1 — Backend: trial data, enforcement, contract

**Implement**
1. `migrations/015_add_user_trial.sql`: `ALTER TABLE users ADD COLUMN trial_ends_at timestamptz;` — nullable, **no backfill here** (backfill happens at enforcement time, step 4).
2. `userRepo.upsertUser()`: on INSERT set `trial_ends_at = now() + interval '3 days'`; on conflict leave it untouched. Put the duration in one constant (`TRIAL_DURATION_DAYS = 3`) in `quotaService.ts`.
3. `quotaService.canUserParticipate()`: before the monthly count, if plan is free **and** `TRIAL_ENFORCEMENT_ENABLED` **and** `trial_ends_at` is set and `< now()` → return `{ allowed: false, reason: 'TRIAL_EXPIRED', … }`. Extend `QuotaResult` with `reason: 'TRIAL_EXPIRED' | 'QUOTA_EXCEEDED' | null`.
4. Lazy fair-start for existing users: when enforcement is on and `trial_ends_at IS NULL`, set it to `now() + 3 days` (single `UPDATE … WHERE trial_ends_at IS NULL RETURNING`), so every pre-existing rider's 3 days start on their first request after the flip — matching "fresh 3 days from release". Do this in a `getOrStartTrial(userId)` helper used by both the gate and `/users/me`.
5. Routes `POST /rides` and `POST /rides/:rideId/join`: return 403 `{ error: 'TRIAL_EXPIRED', trialEndsAt }` when `reason === 'TRIAL_EXPIRED'`; add `errorSchema('TRIAL_EXPIRED')` next to the existing `QUOTA_EXCEEDED` (`rides.ts:334`, `:926`).
6. `GET /users/me`: add
   ```
   trial: { endsAt: date-time|null, isActive: boolean, enforced: boolean }
   usage: { ridesUsedThisMonth: integer, monthlyLimit: integer|null }
   ```
   `usage` reuses `canUserParticipate()` — don't duplicate the SQL. Pro users: `trial.isActive=false`, irrelevant to the client.
7. Update the route schema in `memberships.ts` **and** `openapi.json` (both routes + `/users/me`).
8. Env flag `TRIAL_ENFORCEMENT_ENABLED` (default `false`). Rollout: deploy backend (flag off) → ship iOS + Android updates → flip flag. Old app builds will see `TRIAL_EXPIRED` as a generic error; acceptable once most users have updated.

**Verify**: free test user — `/users/me` shows `trial.endsAt ≈ now+3d`; set `trial_ends_at = now() - interval '1 minute'` in DB → create and join both 403 `TRIAL_EXPIRED`; `start`/`end` of an existing ride still 200; Pro user unaffected; flag off → no 403s.

---

## Phase 2 — Retire the store-level free trial + fix Android offer selection

**Implement**
1. iOS: remove both `introductoryOffer` blocks from `convotrack/convotrack.storekit` (`:28-33`, `:54-59`). **Manual (you):** remove the 3-day free intro offer from both plans in App Store Connect.
2. Android `BillingManager.purchase()`: replace `firstOrNull()` with an explicit base-plan pick — the offer whose `offerId == null` (Play's base-plan offer), falling back to `firstOrNull()` only if none. Comment why: the store trial is retired; the app-level trial is the only trial. **Manual (you):** deactivate any free-trial offer on both base plans in Play Console.
3. Android `MembershipScreen.kt`: make sure no trial wording is shown for store offers (parity with iOS fail-closed). If future store offers come back, add a `trialOffer()` helper that only returns an offer with a `$0` first pricing phase — mirror `MembershipView.trialLine`.

**Verify**: iOS paywall on simulator shows no "free trial, then…" line; Android paywall purchase sheet (internal testing track) shows the plain price, no trial.

---

## Phase 3 — Client trial state + global paywall presenter

**Implement (iOS)**
1. `Networking/Models.swift`: add `TrialInfo { endsAt: Date?, isActive: Bool, enforced: Bool }` and `UsageInfo`; decode with `decodeIfPresent` in `UserMeResponse` (old backend still decodes).
2. `MembershipStore`: `@Published private(set) var plan`, `trial`, `usage`; `func refreshServerState()` (moves the merge from `ConvoTrackApp.swift:128-138` here; call it on launch **and** on every `scenePhase == .active`). Derived:
   - `access: Access { .pro, .trial(endsAt), .trialExpired, .free /* enforcement off */ }`
   - `trialDaysLeft: Int?` = ceil of hours left / 24 (show "Last day" when < 24 h, "X hours left" under 12 h).
   - `riderCap` from `plan.maxRidersPerRide` — replace hardcoded caps in Create/Edit.
   `MembershipView` reads `store.plan` instead of its own `fetchMe()`.
3. `UserFacingError`: map `TRIAL_EXPIRED` → "Your free trial has ended. Go Pro to create and join rides."
4. `Services/PaywallPresenter.swift`: `@Published var request: PaywallRequest?`, `present(_ source: PaywallSource)`; sources `appOpen, homeCard, homeBadge, createBlocked, joinBlocked, riderCap, quotaExceeded, rideSummary, profile`. Owned by `MainTabView`, `.sheet(item:)` → `MembershipView(source:)`. Copy the `JoinSheetContext` pattern. Drop presents while `appState.isRideActive`.
5. Migrate Profile/Create/Edit local `showMembership` sheets to the presenter.

**Verify**: build; `grep -rn "showMembership" convotrack` empty; `grep -rn "? 25 : 5" convotrack` only the store fallback.

---

## Phase 4 — Trial-first paywall copy

**Implement** (`MembershipView`, by `store.access` + `source`)
- `.trial` → hero "**2 days left** in your free trial" (live from `trialEndsAt`), subtitle "Keep riding with your crew after it ends."
- `.trialExpired` → hero "Your free trial has ended", subtitle "Go Pro to create and join rides." Close button stays (App Review: paywalls must be dismissible), but nothing behind it lets them ride.
- Free-plan footnote (`:181-197`) rewritten: "Trial includes up to N rides and N riders per ride." — secondary, small.
- Source-specific line under hero for `riderCap` ("Ride with up to 25") and `quotaExceeded`.
- Onboarding paywall (`ContentView` `.paywall`): reframe as "Your 3-day free trial has started" with "Continue free" as the secondary action — the trial is already running, the paywall is the early-upgrade offer.

**Verify**: render each state with a debug override (`-paywallState trial|expired|pro` under the existing `#if DEBUG` launch-arg switch in `ContentView.swift:53-62`).

---

## Phase 5 — Indicators everywhere

**Implement**
1. New `DSPlanBadge` in `DesignSystem/Feedback.swift` (model on `DSLeaderBadge`; add to `FeedbackGallery`):
   - `.pro` — lime rosette "PRO"
   - `.trial(daysLeft)` — tonal "TRIAL · 2d"; turns warning-tinted on the last day
   - `.expired` — "Go Pro" lime pill
2. **Home toolbar leading**: the badge; tap → presenter (`.homeBadge`), Pro → Membership & Billing.
3. **Home create/join while expired**: keep `DSActionButtonPair` visible but intercept both actions → `paywall.present(.createBlocked / .joinBlocked)`; add a small lock glyph on the buttons. Same intercept for the global `JoinRideView` sheet opened from a deep link/QR: show the paywall instead, keep the code so a successful purchase continues straight into the join.
4. **Profile**: badge next to the name; `DSPromoBanner` message follows the trial state ("2 days left in your trial" / "Trial ended — go Pro").
5. **Create/Edit ride**: helper under the riders stepper always visible for non-Pro ("Trial · up to 5 riders · Unlock 25 with Pro"); keep the at-cap banner.
6. **Ride lobby**: free leader sees "3 / 5 riders" chip with lock when ≥ cap − 1.
7. **Ride summary**: non-Pro gets a compact banner with the countdown ("Loved it? 1 day left — keep riding with Pro").
8. Errors: `TRIAL_EXPIRED` and `QUOTA_EXCEEDED` from Create/Join/RidePreview open the paywall (alert action "See Pro") instead of text-only.

**Verify**: screenshots of Home, Profile, Create, Lobby, Summary, Join-by-link in all four `access` states; Pro shows zero upsell.

---

## Phase 6 — Home card + app-open popup (trial-driven)

**Home card** (between hero and Active ride; reuse `DSPromoBanner`, add optional `onDismiss`)
| State | Copy | Dismissible |
| --- | --- | --- |
| trial, > 1 day left | "**2 days** left in your free trial" · "Go Pro" | yes, snooze 24 h |
| trial, last day | "Your trial ends **today**" · "Go Pro" | no |
| expired | "Trial ended — go Pro to keep riding" · "See plans" | no |
| enforcement off / free | "Ride with up to 25 riders" · "Upgrade" | yes, 7 days |

Hidden during an active ride; never for Pro.

**App-open popup** — `ProNudgeSheet`, `.presentationDetents([.medium])`, big countdown number (`.metricValue`), 3 `DSBenefitTile`s, primary "See plans" → closes and `paywall.present(.appOpen)`, secondary "Not now". No price/buy button in the nudge.

Cadence (`Services/UpsellState.swift`, UserDefaults, copy `OnboardingState` pattern; decision in pure `UpsellPolicy.shouldShowAppOpenNudge(access:now:state:)`):
| State | When |
| --- | --- |
| trial day 1 | none (onboarding paywall already shown) |
| trial day 2 | once, first open of the day |
| trial last 24 h | once, first open; again if < 6 h left |
| expired | every app open, max once per 4 h (they can't ride anyway — this is the main conversion surface) |
| enforcement off | old rules: ≥ 3 opens, ≥ 72 h apart, back-off after 3 dismissals |

Always skipped: Pro, active ride, pending `DeepLinkRouter.pendingJoinCode`/`pendingOpenRideId` (the join intercept in Phase 5 handles that path), another sheet up. Present ~1.5 s after Home appears (same reason as `MainTabView.swift:74-80`). "App open" = `scenePhase → .active` after ≥ 30 min in background.

**Optional local notification** (no server push needed): schedule one `UNUserNotificationCenter` notification for `trialEndsAt − 6 h` ("Your ConvoTrack trial ends tonight"), only if notification permission is already granted; cancel on purchase.

**Verify**: debug arg `-resetUpsell` + DB-adjusted `trial_ends_at` walk through day 2 / last day / expired; confirm cadence and that a rider mid-ride never sees it.

---

## Phase 7 — Android parity

Mirror Phases 3–6 with identical thresholds and copy:
- `data/net/Models.kt` `trial`/`usage` (nullable); `TRIAL_EXPIRED` in the Android `UserFacingError`.
- `PlanGate.kt` → access state (`PRO / TRIAL / TRIAL_EXPIRED / FREE`) + presenter with source.
- `MainScreen.kt` hosts paywall + nudge; Home card + create/join intercept; join App Link with expired trial → paywall, keep code.
- `ProfileScreen`, `RouteForm.kt` helper, lobby chip, summary banner.
- `UpsellState` in SharedPreferences/DataStore; `UpsellPolicy` as a pure function with unit tests next to the voice-guide tests (`./gradlew testDebugUnitTest`).
- Trial-end local notification via `AlarmManager`/`WorkManager` only if `POST_NOTIFICATIONS` already granted.
- Add the cadence table above to CLAUDE.md "values that must match on both platforms".

---

## Phase 8 — Rollout & verification

1. Backend deployed with `TRIAL_ENFORCEMENT_ENABLED=false`; contract tests via `curl` (Phase 1 checks).
2. Builds:
   `xcodebuild -project convotrack.xcodeproj -scheme convotrack -destination 'platform=iOS Simulator,name=iPhone 17' build`
   Android `./gradlew assembleDebug testDebugUnitTest` (with the `-D` JDK flag from CLAUDE.md).
3. Grep guards: no `"3 days"` / `"5 riders"` / `"25"` literals in new copy; `Product.purchase` only in `MembershipStore`; no `firstOrNull()?.offerToken` in `BillingManager`; every upsell view checks access.
4. Manual matrix: (Pro / trial day 1 / last day / expired / enforcement off) × (Home, badge, card, popup, Create, Join, Join-by-link, Lobby, Summary, Profile) on both platforms.
5. `apple-design` skill review of badge, Home card, nudge sheet, expired paywall (dismissible, non-deceptive, Dynamic Type, VoiceOver).
6. App Store review notes: explain the app-level trial (no payment taken) and that the paywall is dismissible. Update App Store / Play description: "3-day free trial, then Pro required to create or join rides."
7. Ship apps → wait for adoption → flip `TRIAL_ENFORCEMENT_ENABLED=true` (this starts existing users' 3 days).
8. Update CLAUDE.md: freemium model, presenter location, trial flag, cadence table.
