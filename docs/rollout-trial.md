# Rollout checklist — 3-day free trial & Pro conversion

Order matters: the trial switch (`TRIAL_ENFORCEMENT_ENABLED`) starts every free rider's 3 days and
blocks create/join when they end. Anything still running an old build then sees `TRIAL_EXPIRED` as a
generic error with no way to upgrade from it. Decision (2026-10-19): flip as soon as **iOS** is live;
Android follows as fast as Play review allows.

Legend: **[you]** needs you (console, credentials, judgement) · **[me]** I can do it on request.

---

## 0. Already done

- [x] Backend: trial, per-device trial, `/events`, `proPlan` — pushed (`544715b`), migrations 015–017 applied on Supabase.
- [x] iOS app work (Phases 1–8 + follow-ups) — pushed (`97890cc`).
- [x] Android app work incl. onboarding paywall — pushed (`b258dd5`).
- [x] App Store: 3-day introductory offers deleted (350/350); en-US + en-GB subscription names/descriptions added as drafts.
- [x] App Store metadata (description, promo text, What's New) in all 50 locales — in `fastlane/metadata`, not yet uploaded.

## 1. Backend live with the switch OFF

- [x] **[you]** Render shows `544715b` (or later) deployed and healthy.
- [x] **[you]** `TRIAL_ENFORCEMENT_ENABLED` is unset or `false` in Render.
- [x] **[me]** (2026-10-19: `/events` live; iOS paywall events reach production with device id. `/users/me` fields not checked — needs a signed-in token.) Verify on the live API with your test account (needs a signed-in session on any device): `GET /users/me` returns `trial` (`enforced: false`), `usage` and `proPlan`. Read-only.

## 2. Store-side setup (before submitting either app)

- [ ] **[you]** Play Console: deactivate any free-trial / intro offer on `convotrack_pro_monthly` and `convotrack_pro_yearly` (the Android app already ignores them, but the listing and Play's own UI would still advertise one).
- [ ] **[you]** App Store privacy label: add **Identifiers → Device ID** (App Functionality, linked, no tracking) and **Usage Data → Product Interaction** (Analytics, linked, no tracking).
- [ ] **[you]** Play data safety: add **Device or other IDs** (App functionality, Fraud prevention) and **App activity → App interactions** (Analytics). Not shared.
- [ ] **[you]** Privacy policy page: add the device-identifier sentence from `docs/store-copy-trial.md` §6.
- [ ] **[you]** Pick the App Review demo account and contact email; fill them into the review notes (§4 of the store-copy doc).

## 3. Ship iOS

- [x] **[me]** Bump version/build in Xcode — 2.0.0 (8), `dde9a9c`.
- [x] **[you]** Archive and upload the build (Organizer). The `BMSHCXL2PM` API key can't cloud-sign; an Admin-role key is needed for me to upload.
- [ ] **[me]** Upload App Store metadata only (no binary, no submission): description, promotional text, What's New for 50 locales. Note: **promotional text goes live immediately** — upload it no earlier than the day the build ships.
- [ ] **[you]** App Store Connect → version page:
  - attach the build;
  - under *In-App Purchases and Subscriptions*, include **both** subscriptions (otherwise the new en-US/en-GB names stay drafts);
  - paste the App Review notes (store-copy doc §4).
- [ ] **[you]** Submit for review. Prefer **manual release** so you control the moment it goes live (step 5 is timed off it).

## 4. Ship Android (in parallel with iOS review)

- [x] **[me]** 2.0.0 (9) on alpha, tagged `v2.0.0`. Release via the `android-play-release` skill: version bump (you choose patch/minor/major), CHANGELOG, signed bundle, upload to the testing track, Play "What's new" from store-copy doc §3.
- [ ] **[you]** Play Console listing: short description, full-description section and What's new from store-copy doc §5.
- [ ] **[you]** Promote to production once testers are happy.

## 5. Flip the switch (the day iOS goes live)

- [ ] **[you]** Release the approved iOS version (manual release).
- [ ] **[you]** Render → set `TRIAL_ENFORCEMENT_ENABLED=true` → redeploy/restart.
- [ ] **[me]** Verify with your test account: `/users/me` shows `trial.enforced: true` and an `endsAt` ~3 days out; the Home badge reads TRIAL · 3D; the device row exists in `trial_devices`.

What riders see from this moment: everyone free gets 3 days from their next app open (existing riders included); Pro riders see nothing new. Android riders on the old build get a generic error on create/join after 3 days until they update — keep the Android release moving.

## 6. Watch (first week)

Run against Supabase (read-only):

```sql
-- Paywall funnel by entry point, last 7 days
SELECT source,
       count(*) FILTER (WHERE name = 'paywall_shown')            AS shown,
       count(*) FILTER (WHERE name = 'paywall_purchase_started') AS started,
       count(*) FILTER (WHERE name = 'paywall_converted')        AS converted
FROM paywall_events
WHERE occurred_at > now() - interval '7 days'
GROUP BY source ORDER BY shown DESC;

-- Nudge: shown vs dismissed
SELECT name, count(*) FROM paywall_events
WHERE name IN ('nudge_shown', 'nudge_dismissed') AND occurred_at > now() - interval '7 days'
GROUP BY name;

-- Trials: running vs ended (free riders only have trial_ends_at set once enforced)
SELECT count(*) FILTER (WHERE trial_ends_at > now())  AS running,
       count(*) FILTER (WHERE trial_ends_at <= now()) AS ended
FROM users WHERE trial_ends_at IS NOT NULL;

-- Devices that already had a trial (repeat-signup protection at work)
SELECT count(*) AS devices, count(*) FILTER (WHERE first_user_id IS NULL) AS from_deleted_accounts
FROM trial_devices;
```

Signals to act on:
- Many `TRIAL_EXPIRED` errors from Android with no `paywall_shown` → riders still on the old build; nudge the Play rollout.
- `nudge_dismissed` ≫ `paywall_shown` from `appOpen` after the trial → the 4-hour cadence is too much (decision noted; easy to relax in both `UpsellPolicy`s).
- Support mail about shared phones getting no trial → the per-device rule is biting; consider a manual reset per account.

## Rollback

- **Stop blocking** (anything goes wrong with the trial): Render → `TRIAL_ENFORCEMENT_ENABLED=false` → restart. Create/join work again for everyone at once; apps fall back to the plain free-plan UI on their next foreground. Trial dates are kept, so turning it back on resumes where it was (riders whose trial ended stay ended).
- **Give one rider more time:** `UPDATE users SET trial_ends_at = now() + interval '3 days' WHERE id = '<clerk user id>';` (and the same on their `trial_devices` row if they'll make a new account).
- **Undo the App Store intro-offer removal:** re-create a 3-day free introductory offer per subscription in App Store Connect.

## Known follow-ups (not blocking)

- Android's auth interceptor retries every 403 once with a fresh token, so a `TRIAL_EXPIRED` refusal is sent twice. Harmless; limiting the retry to 401 is a one-line change.
- Translations in `fastlane/metadata` were machine-written by Claude; a native-speaker pass on the top markets (esp. Indian languages) is worthwhile.
- The App Review risk under guideline 3.1.1 (server-side time-based trial in a subscription app): if rejected, the fallback is a 3-day App Store introductory offer, i.e. a card-required trial.
