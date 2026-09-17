# Unified `convotrack.in` Domain Plan

**Status:** CODE CHANGES DONE (2026-08-09) — remaining work is dashboard config + deploys (see "Owner action items" at bottom).
**Goal:** One unified domain experience across both servers — Vercel (website/landing/legal) and Render (backend API + Socket.IO + deep links).

**Decisions locked in:**
- Join/invite Universal Links live on **`convotrack.in` (Vercel)** → `https://convotrack.in/join/CODE`. AASA `components` path pattern = `/join/*`.
- Backend REST + Socket.IO on **`api.convotrack.in` (Render)** custom subdomain (attached by owner 2026-08-09).
- Backend `deeplink.ts` (old AASA/assetlinks/`/convotrack/join`) kept on Render for back-compat with already-shared render-host links; no longer the source of truth.

---

## Current state

| Piece | Host today | Serves |
|-------|-----------|--------|
| Website (Vercel) | `https://convotrack.in` | Landing + legal at **root** routes: `/`, `/privacy`, `/terms`, `/support`. `SITE` const already = `https://convotrack.in` in `convotrack-website/app/layout.tsx`. |
| Backend (Render) | `convoy-backend-hx3c.onrender.com` | REST API, Socket.IO, **and** deep-link infra via `convoy-backend/src/routes/deeplink.ts` (public/unauth in `app.ts`): `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json`, fallback landing `/convotrack/join/:code`. |

**iOS (`convoy`)**
- `AppURLs.swift`: `backendBaseURL = https://convoy-backend-hx3c.onrender.com`; `joinLinkHost = convoy-backend-hx3c.onrender.com`; `joinLink(code) = <base>/convotrack/join/CODE`.
- Legal URLs **already updated** to `https://convotrack.in/privacy` + `/terms` (done 2026-08-08). QR landing → `https://convotrack.in`.
- Entitlement `convotrack/convotrack.entitlements`: `applinks:convoy-backend-hx3c.onrender.com` (join Universal Links only — legal pages use `openURL`/`Link` in Safari and need **no** entitlement).
- Deep-link host/path validated in `ConvoTrackApp.swift` (`handleDeepLink`) and `QRScannerView.swift` (checks `joinLinkHost` + path prefix `/convotrack/join/`).

**Android (`convotrack-android` + `convoy-android`)**
- `app/.../data/net/ApiClient.kt`: `BASE_URL = https://convoy-backend-hx3c.onrender.com` + join-link builder.
- `AndroidManifest.xml`: App Link intent-filter host + assetlinks.
- Legal pages **not wired** (only "Privacy" UI labels, no URLs).

---

## Key constraint

The apex `convotrack.in` can point to only **one** origin. Vercel **cannot proxy long-lived Socket.IO WebSockets**, so the backend must live on its own subdomain.

## Recommended target architecture

- `convotrack.in` (apex) → **Vercel**: marketing + legal + Universal Links infra (AASA, assetlinks) + `/join/CODE` fallback landing.
- `api.convotrack.in` (CNAME → Render) → backend REST + Socket.IO.
- Join/invite Universal Links branded on apex: `https://convotrack.in/join/CODE`; entitlement → `applinks:convotrack.in`.

**Decision needed at execution time:** host join links + AASA on **apex Vercel** (recommended — clean branding; requires moving AASA/assetlinks/join-landing off backend into Vercel static files) *or* keep them on **`api.convotrack.in` Render** (entitlement `applinks:api.convotrack.in`, less migration).

---

## Change checklist

**DNS**
- [ ] apex `convotrack.in` → Vercel (A/ALIAS)
- [ ] `api.convotrack.in` CNAME → Render
- [ ] Verify + TLS on both

**Vercel / website (`convotrack-website`)** — if hosting Universal Links:
- [ ] Add `/.well-known/apple-app-site-association` + `assetlinks.json` as static files, served with `Content-Type: application/json` and **no** file extension (via `next.config` headers or `public/` + rewrites)
- [ ] Add `/join/[code]` fallback page

**Render / backend (`convoy-backend`)**
- [ ] Add custom domain `api.convotrack.in` + TLS
- [ ] Update CORS / allowed origins
- [ ] If join moves to Vercel: remove/deprecate `deeplink.ts` AASA/assetlinks/join routes (or keep for back-compat)
- [ ] Set env `APPLE_APP_ID_PREFIX` (Apple Team ID) + `ANDROID_SHA256_FINGERPRINTS` (release cert SHA-256); redeploy

**iOS (`convoy`)**
- [ ] `AppURLs.swift`: `backendBaseURL` → `https://api.convotrack.in`
- [ ] `AppURLs.swift`: `joinLinkHost` + `joinLink()` base + path → `convotrack.in` (`/join/CODE`)
- [ ] `convotrack.entitlements`: `applinks` → `convotrack.in`
- [ ] Update host/path validation in `ConvoTrackApp.swift` (`handleDeepLink`) + `QRScannerView.swift`

**Android (`convotrack-android` + `convoy-android`)**
- [ ] `ApiClient.kt`: `BASE_URL` → `https://api.convotrack.in`; join link host/path
- [ ] `AndroidManifest.xml`: intent-filter host (`autoVerify`) → `convotrack.in`
- [ ] `assetlinks.json` on `convotrack.in`

**External config (do by hand)**
- [ ] Apple Developer: enable **Associated Domains** capability for App ID `danglingmind.convotrack`
- [ ] Clerk (prod instance `clerk.convoy.vynl.in`): update allowed origins / redirect for new domains
- [ ] Update any live QR codes + App Store review notes

---

---

## Owner action items (dashboard / deploy — not code)

These are the only things left; the code is committed.

1. **Vercel env vars** (convotrack-website project) → then **redeploy**:
   - `APPLE_APP_ID_PREFIX` = Apple **Team ID** (e.g. `AB12CD34EF`) — makes AASA `appIDs` valid.
   - `ANDROID_SHA256_FINGERPRINTS` = release cert SHA-256(s), comma-separated — makes assetlinks valid.
   - (optional) `ANDROID_PACKAGE`, `APP_STORE_URL`, `PLAY_STORE_URL` overrides.
2. **Apple Developer** → App ID `danglingmind.convotrack` → enable **Associated Domains** capability; regenerate provisioning profile if needed.
3. **Verify** `https://convotrack.in/.well-known/apple-app-site-association` returns JSON with the real Team ID, and `.../assetlinks.json` returns the real fingerprints (both via the Next rewrites).
4. **Render** `api.convotrack.in` — already attached; confirm TLS is issued. No backend code change needed (CORS defaults to `*`).
5. (optional) Clerk prod instance allowed origins — only if a browser origin ever calls the API; mobile apps are unaffected.
6. Ship new iOS + Android builds (entitlement/manifest changes require a fresh build to take effect).

## Verify after cutover

- [ ] Universal Link taps open the app from **cold + backgrounded** (iOS + Android `autoVerify`)
- [ ] AASA reachable with correct `Content-Type`
- [ ] API + Socket.IO reachable on `api.convotrack.in`, CORS OK
- [ ] Legal/privacy/terms links load (App Store reviewer path)
