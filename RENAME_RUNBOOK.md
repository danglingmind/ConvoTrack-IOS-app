# App Rename Runbook

How to rename this app end-to-end (code + external services) in one shot.
Derived from the **Convoy → Motorcade** rename (2026-07). Current name is the
"FROM" baseline below; fill in the new name and paste the prompt in
[§0](#0-one-shot-prompt).

Two repos are involved:
- **iOS app** — `/Users/ricky/Workspace/convoy` (repo dir name unchanged; source folder is `convotrack/`)
- **Web/legal pages** — `/Users/ricky/Workspace/noto` (Next.js on Vercel, serves `vynl.in/<name>/…`)

---

## Naming parameters (fill these in for the next rename)

| Token | Current value | New value |
|---|---|---|
| Display / brand name | `ConvoTrack` (also `CONVOTRACK`, `convotrack`) | `<NewName>` |
| Bundle identifier | `danglingmind.convotrack` | `danglingmind.<newname>` |
| Xcode target / product / scheme / source folder | `convotrack` | `<newname>` |
| Deep-link URL scheme | `convotrack://` (invite links `convotrack://join/CODE`) | `<newname>://` |
| IAP product IDs | `danglingmind.convotrack.membership.{monthly,yearly}` | `danglingmind.<newname>.membership.*` |
| Web route prefix | `vynl.in/convotrack` → `src/app/convotrack/` | `vynl.in/<newname>` |
| Clerk OAuth redirect | `danglingmind.convotrack://callback` | `danglingmind.<newname>://callback` |

### ⚠️ Do NOT rename these (they bit us / will break things)
- **Backend host** `convoy-backend-hx3c.onrender.com` in [convotrack/AppURLs.swift](convotrack/AppURLs.swift) — the `-hx3c` suffix is **Render-assigned**; you can't predict the new host. Rename the Render service first, then paste the *actual* new URL. Blindly editing it breaks every API/socket call.
- **`convoy-backend` repo path** references in `CLAUDE.md` — that's the separate backend repo dir on disk; unrelated to the app name.
- **Clerk publishable key / instance domain** `clerk.convoy.vynl.in` — cosmetic only; renaming a *production* Clerk domain forces DNS re-verification + redeploy. Leave unless you truly want clean branding (see [§4](#4-external-config-do-these-yourself)).
- The **repo directory names** themselves (`Workspace/convoy`, `Workspace/noto`) — local paths, not app identity.

---

## 0. One-shot prompt

> Rename the app from **ConvoTrack** to **`<NewName>`** across both repos, following `RENAME_RUNBOOK.md`.
> - iOS repo `/Users/ricky/Workspace/convoy`: rename the `convotrack/` folder, `convotrack.xcodeproj`, scheme, `ConvoTrackApp.swift`/`ConvoTrackTheme.swift`/`convotrack.storekit`, all `ConvoTrack*` Swift symbols, bundle id → `danglingmind.<newname>`, IAP product IDs, `convotrack://` scheme, `vynl.in/convotrack` legal URLs, display copy, Info.plist, StoreKit config, and docs/specs. Use `git mv` to preserve history.
> - Web repo `/Users/ricky/Workspace/noto`: rename `src/app/convotrack/` route folder → `<newname>`, the `src/middleware.ts` matcher, hardcoded `vynl.in/convotrack` legal text, brand copy, and component names. Clean cutover (no redirect) unless I say otherwise.
> - **Leave** the Render backend host (`convoy-backend-*.onrender.com`) with a rename TODO, the `convoy-backend` repo path, and the Clerk key/domain untouched.
> - Verify: `grep -rin` for the old name (only the intentional exceptions should remain), then `xcodebuild … build` for iOS and `tsc --noEmit` for noto.
> - Then give me the external-config checklist (§4) with the new values filled in.

---

## 1. iOS repo (`convoy`) — code changes

### 1a. File / folder renames (use `git mv`)
```
convotrack/                         → <newname>/
convotrack.xcodeproj                → <newname>.xcodeproj
  …/xcschemes/convotrack.xcscheme   → <newname>.xcscheme
convotrack/ConvoTrackApp.swift       → <newname>/<NewName>App.swift   (the @main struct)
convotrack/ConvoTrackTheme.swift     → <newname>/<NewName>Theme.swift
convotrack/convotrack.storekit       → <newname>/<newname>.storekit
```
After moving, **delete any stale `convotrack.xcodeproj/` left untracked** (Xcode can recreate it). The real project must be the renamed one.

### 1b. `project.pbxproj` (safe blanket replace `convotrack`→`<newname>`)
Touches: `PRODUCT_BUNDLE_IDENTIFIER`, `INFOPLIST_FILE`, target `name`, `productName`, synchronized-group `path`, `<name>.app`, and the auto-comments. No external URLs live here, so a whole-file replace is safe.

### 1c. Other project metadata
- `…/xcschemes/<name>.xcscheme` — `BuildableName`, `BlueprintName`, `ReferencedContainer`, StoreKit `identifier` path
- `…/xcuserdata/**/xcschememanagement.plist` — scheme key
- `…/xcuserdata/**/Breakpoints_v2.xcbkptlist` — stale file paths

### 1d. `Info.plist`
- `CFBundleURLName` → `danglingmind.<newname>`
- `CFBundleURLSchemes` → `<newname>`
- `NSCameraUsageDescription`, `NSLocation*UsageDescription` — brand copy

### 1e. Swift symbols (rename everywhere)
`ConvoTrackApp`, `ConvoTrackAppDelegate`, `ConvoTrackBottomNav`, `ConvoTrackTopBar`, `ConvoTrackUser`, `ConvoTrackLocationPin`, and the notification `.convotrackJoinRide` / `Notification.Name("convotrackJoinRide")`.

### 1f. Strings & copy (scoped replaces — never hit the backend host)
- `convotrack://` → `<newname>://` (deep links, QR, comments)
- `== "convotrack"` (scheme guards in `ConvoTrackApp.swift`, `QRScannerView.swift`)
- `danglingmind.convotrack` → product IDs (`MembershipView.swift`, `Services/MembershipStore.swift`)
- `vynl.in/convotrack` → legal + QR URLs (`AppURLs.swift`, `RideSummaryView.swift`)
- Display copy: `CONVOTRACK` / `ConvoTrack` / "convotrack" as brand noun (`SplashView`, `AuthView`, `RideLobbyView`, `MembershipView`, `ProfileView`, `CoordinationOverlayView`, `RideSummaryShareCard`, `RideHistoryView`, `HomeView`, `QRScannerView`, etc.)

### 1g. StoreKit config `<name>.storekit`
`identifier`, `subscriptionGroupID`/`internalID`, `productID` (must match App Store Connect), and display/reference names.

### 1h. Docs
`CLAUDE.md` (build/`open` commands + `Bundle ID`), `docs/app-store-iap-setup.md` (bundle id, product IDs, SKU, group name), `spec/*` (`BACKEND_BRIEF.md`, `BackendSpecV2.jsx`, `INTEGRATION_PLAN.md`, `<name>-landing-page.md`), `TODO.md`. **Protect** `convoy-backend` and the `onrender.com` host in these.

### 1i. The one line to update *manually after* renaming Render
[convotrack/AppURLs.swift](convotrack/AppURLs.swift) `backendBaseURL` — see warning above.

---

## 2. Web repo (`noto`) — code changes

- `git mv src/app/convotrack  src/app/<newname>` — moves 4 pages: `page.tsx`, `privacy/`, `terms/`, `support/`
- `src/middleware.ts` — matcher `'/convotrack(.*)'` → `'/<newname>(.*)'`
- Inside pages: `/convotrack/*` `<Link>` hrefs, hardcoded `vynl.in/convotrack/{privacy,terms}` legal text, component names (`ConvoTrackLandingPage`, …), and `ConvoTrack`/`CONVOTRACK` brand copy
- **Decision each time:** clean cutover (old `/…` 404s) **or** add a `next.config.ts` permanent redirect `/oldname/* → /newname/*`. Last time = clean cutover, no redirect.

---

## 3. Verification

```bash
# iOS — only the backend host + convoy-backend path should remain
cd /Users/ricky/Workspace/convoy && grep -rin "convotrack" . | grep -v "/.git/"   # sanity: new name present
grep -rin "<oldname>" . | grep -v "/.git/"                                        # expect only intentional
xcodebuild -project <newname>.xcodeproj -scheme <newname> \
  -destination 'platform=iOS Simulator,name=iPhone 17' build                      # ** BUILD SUCCEEDED **

# Web — expect no matches in src/
cd /Users/ricky/Workspace/noto && grep -rin "<oldname>" src src/middleware.ts
npx tsc --noEmit    # stale .next/types errors are OK; they regenerate on build
```
Then **sign-in test on device/sim** after doing §4 (Clerk).

---

## 4. External config (DO THESE YOURSELF — not in code)

The bundle-ID rename has mirrors in external systems. Until each matches, the app
won't sign / auth / purchase. Values below assume new bundle id `danglingmind.<newname>`.

| # | System | What to change | Notes |
|---|---|---|---|
| 1 | **Apple Developer** portal | Register App ID `danglingmind.<newname>`; enable **In-App Purchase** + **Sign in with Apple**; regenerate provisioning profiles | New App ID = new provisioning. |
| 2 | **App Store Connect** | New app record bundle id; **recreate** IAP products `danglingmind.<newname>.membership.monthly` / `.yearly` | ⚠️ IAP product IDs **cannot be renamed**, only recreated. Prices: $4.99 / $39.99. |
| 3 | **Clerk Dashboard** (prod instance `clerk.convoy.vynl.in`) | Configure → **Native Applications** → **Allowlist for mobile SSO redirect** → add `danglingmind.<newname>://callback` | This is the **"redirect url is not authorized"** fix. Redirect = `{bundleId}://callback` (ClerkKit default). Instance domain rename optional/disruptive — skip. |
| 4 | **Backend** (`convoy-backend`) | Allowed bundle-id / JWT audience checks; any server-generated invite links using `convotrack://` scheme → `<newname>://` | Check before shipping deep links. |
| 5 | **Render** | Rename the service (or attach a custom domain), then paste the **actual** new host into `AppURLs.backendBaseURL` | New `-xxxx` suffix is unpredictable — must copy from Render. |
| 6 | **Vercel / `noto` deploy** | Deploy so `vynl.in/<newname>/{privacy,terms,support}` is live | Clean cutover ⇒ old `/oldname/*` returns 404. |
| 7 | **Housekeeping** | Update any live **QR codes**, **App Store review notes**, and links that referenced old `vynl.in/oldname/*` or `oldname://` | Reviewers click privacy/terms links — 404 = rejection. |

---

## Appendix — gotchas learned (Convoy → Motorcade)
- Clerk OAuth redirect is `{bundleIdentifier}://callback`, **not** the Info.plist deep-link scheme (`ASWebAuthenticationSession` handles the callback internally). Ref: ClerkKit `ClerkOptions.swift`.
- Git scored a couple of heavily-edited renames as add+delete instead of `R` — content is intact; not a problem.
- iOS repo rename went on branch `rename/motorcade` then merged to `main`; web repo committed straight to `main`. Pick a convention up front.
