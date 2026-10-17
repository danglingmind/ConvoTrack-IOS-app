# Onboarding Videos — Plan & Shot Script

Three silent, looping background clips for the onboarding pages in
`convotrack/Onboarding/OnboardingFlowView.swift`, built as motion graphics from the real app
screenshots in `docs/onboarding-screenshots/` (captured from a live 4-rider ride up Nandi Hills).

| Page | Copy (native text, already in the app) | Clip file |
|---|---|---|
| 1 | LIVE TRACKING · **Every rider. One map.** | `onboarding_tracking.mp4` + `onboarding_tracking_poster` |
| 2 | REGROUP · **Nobody gets left behind.** | `onboarding_regroup.mp4` + `onboarding_regroup_poster` |
| 3 | ONE LINK · **One link. Everyone's in.** | `onboarding_invite.mp4` + `onboarding_invite_poster` |

File names are the ones `OnboardingBackdrop` already looks for; drop them into the bundle and
the code-drawn stand-in is replaced automatically, with no code change needed.

---

## 1. Ground rules (apply to all three)

### 1.1 Honesty: animate real UI, never invent it

Every element on screen must be a real ConvoTrack UI element, behaving the way it really does.
We *stage* (re-time, isolate, smooth), we don't *fabricate*.

| Allowed | Not allowed |
|---|---|
| Rider pins gliding along the route (the app does this live) | UI that doesn't exist, e.g. the rider detail drawer, which is unreachable in code (`showRiderDetail` is never set), so it's out |
| Regroup banner sliding in, regroup pin appearing | Branded third-party UI (WhatsApp/iMessage chrome); trademark issue, use a neutral bubble |
| Lobby rows appearing, WAITING → READY, rider count ticking | Stats the app wouldn't produce (keep distances/speeds plausible for the ride) |
| Re-timing (a 3-minute ride compressed to 7 s), cropping, camera moves | Removing the Google Maps logo or photo attribution |

*Why:* `onboarding.md › Keep onboarding content focused on the experience you provide`. A clip
that promises UI the rider then can't find costs more trust than it earns.

**These clips are for in-app onboarding only. Do not reuse them as App Store app previews.**
App Review Guideline 2.3.4 (from memory, verify before any App Store use) requires previews to use
screen captures of the app; composited faces and staged motion don't qualify. For the store, record
a straight capture with the `ride-demo` skill.

### 1.2 Composition: respect what's drawn on top of the video

The page layers native UI over the clip. Measured from `OnboardingFlowView`:

```
 0% ┌───────────────────────────┐
    │ [⏸]               [Skip] │  top bar: keep 0–12% free of key action
12% ├───────────────────────────┤
    │                           │
    │    ACTION ZONE            │  everything that tells the story lives here
    │    (12% – 55%)            │  ≈ y 315–1440 px on a 1206×2622 canvas
    │                           │
55% ├───────────────────────────┤
    │  scrim ramps to 88% black │  nothing meaningful below here: it's
    │  LIVE TRACKING            │  covered by the eyebrow, headline,
    │  Every rider. One map.    │  body, page dots and Continue
    │  ●○○○   [ Continue ]      │
100%└───────────────────────────┘
```

- **No app chrome from the screenshots at full scale.** A screenshot's own buttons ("START
  NAVIGATION", "MARK AS ARRIVED", the stats bar) sitting under our real Continue button reads as
  two competing UIs. Crop to the *content*: the map, the banner, the roster.
- **Lime belongs to the Continue button.** `branding.md › Apply your app's accent color judiciously`.
  In the action zone the lime route line is content and fine; in the bottom 45% there must be no
  lime at all, so the CTA owns the colour.
- **Status bar:** never include the screenshot's status bar; the device draws its own.

### 1.3 Motion grammar

From `motion.md › Add motion purposefully` and `accessibility.md › Be cautious with fast-moving
and blinking animations`:

- **One primary motion per beat.** If riders are moving, the camera is not, or it drifts ≤ 3%.
- **Ease, don't bounce.** `easeInOutCubic` for camera, gentle spring (damping ≥ 0.85) for cards.
  No overshoot > 4 px.
- **Speeds:** pins ≤ 60 px/s on the 1206-px canvas; camera ≤ 2% zoom/s.
- **No flashing.** Pulses ≤ 1 Hz, never more than 3 flashes in any 1 s window, red areas small.
  This is why the emergency banner is *not* animated (see Video 2).
- **Seamless loop:** design each clip so frame 0 and the last frame are identical; bake a 0.5 s
  cross-dissolve into the final half-second so `AVPlayerLooper`'s seam is invisible.

### 1.4 Accessibility: already handled in code, but the clip must cooperate

`OnboardingBackdrop` shows the **poster** instead of the video when Reduce Motion is on, video
autoplay is off, or Low Power Mode is on; the page has a pause button
(`accessibility.md › Let people control audio and video playback`). So:

- **The poster must tell the whole story on its own.** Pick the single frame where the beat
  resolves (named per clip below). It's what a Reduce Motion user sees forever.
- **No text the story depends on is only in the video.** Headline and body are native, scale with
  Dynamic Type and are read by VoiceOver; the clip is `accessibilityHidden`.
- **Text over video:** body copy must hit ≥ 4.5:1 against the *brightest* frame behind it. Check
  every clip's frames in the 55–100% band after encoding; darken the plate there, not the type.

### 1.5 Brand

- **Signature element:** the real ride itself, four people on one winding road up Nandi Hills.
  That's specific to ConvoTrack; don't swap it for stock imagery or abstract shapes.
- **No logos in the clips.** `branding.md › Resist the temptation to display your logo throughout`;
  the splash already did that.
- **Keep the Google Maps logo** and the **"Photo: Kavya Hegde · Google"** credit wherever that
  map/photo is visible. Both are licence requirements, not decoration.

---

## 2. The riders (AI-generated faces)

The four test accounts appear as these riders (names already in every screenshot except where
noted). Replace each initials circle with a generated portrait.

| Rider | Role in the story | Shows up in |
|---|---|---|
| **Arjun Rao** | Ride leader, out front | pins `ARJUN`, chips, lobby row 1 (**fix:** that row reads "Demo Demo" in `08`, `11`, `11b`; retype as "Arjun Rao" in the same font) |
| **Meera Iyer** | Calls the regroup | pin `MEERA`, chips, lobby row 2 |
| **Ananya Das** | Mid-pack, the viewer's "you" | pin `ANANYA`, orange "YOU" chip |
| **Kabir Shah** | Trailing rider who gets pulled back in | pin `KABIR`, lobby row 3 |

**Portrait brief (one prompt per rider, same settings):**
- Indian rider, 25–40, matching the name's presentation; head-and-shoulders, ¾ view
- Riding jacket, helmet held or pushed up; golden-hour hill light, shallow background
- Square 1024², plain-ish background so the 28–36 pt circle crop stays legible
- Distinct jacket colour per rider (deep blue, rust, olive, charcoal). At pin size the face
  details vanish; the colour is what makes each rider recognisable
- No text, logos, brand marks or recognisable real people

**Placement:** circle-crop inside the existing ring (lime for focused/leader, neutral ring
otherwise), keeping the green online dot. Pins are ~28 pt; lobby avatars ~36 pt.

**Disclosure:** these are illustrative riders, not customers. Don't pair them with quotes or
ratings anywhere.

---

## 3. Shot scripts

All timings at 30 fps on a 1206×2622 working canvas; deliver at 1080×2340 (§4).

### Video 1: "Every rider. One map." (`onboarding_tracking`, 7.0 s)

**Story:** four riders strung out on a winding climb, and you can see every one of them, even
the one who drops out of view.

**Sources:** `01d_nav_winding_road_all_four.png` (plate), `01c_nav_all_four_visible.png` (pin
positions), `02_nav_leader_offscreen_cluster.png` (off-screen chip style).

**Build the plate:** from `01d`, remove pins, chips, banner, "Mark as arrived" pill and the stats
bar; keep map + route. Trace the lime route as a vector path so pins can follow it exactly.
Extend the map above/below by mirroring tiles only if the camera move needs it (prefer not).

| Time | Beat | Motion |
|---|---|---|
| 0.0 – 0.6 | Settle | Plate visible, 4 pins in their `01c` spacing along the path in the action zone. Camera at 100%. |
| 0.6 – 6.4 | Ride | All 4 pins glide along the traced path at the same speed (~40 px/s), spacing constant. Distance labels under pins count honestly (e.g. 290 m → 250 m). Name tags ride with pins. |
| 1.0 – 1.6 | Chips | Rider chip strip (Arjun Rao · Meera Iyer · **Ananya Das · YOU** · ●4) fades/slides 12 px down into place at ~13% height. Real nav UI; it anchors "every rider". |
| 3.6 – 4.4 | Out of view | Kabir (trailing) reaches the bottom of the action zone and slips under the 55% line; as he does, his **edge chip** ("K · 220 m", app style from `02`) fades in at the zone's bottom edge and tracks his distance. |
| 5.6 – 6.2 | Back in | Kabir catches up into view; edge chip fades out. |
| 6.5 – 7.0 | Loop | 0.5 s dissolve to frame 0. |

**Poster:** frame at **3.0 s**, all four pins + chip strip visible.

### Video 2: "Nobody gets left behind." (`onboarding_regroup`, 8.0 s)

**Story:** one rider calls a regroup, everyone's phone shows where to wait, the pack comes
back together.

**Sources:** `05_regroup_banner_other_rider.png` (banner + Scenic Stop pin),
`06_regroup_pin_riders_gathering.png` (converged state), `01c` (spread-out positions).

**Build the plate:** map from `05` with route; remove banner, chips, pins, pills, stats bar.
Lift the **regroup banner** ("REGROUP CALLED · Head to the Scenic Stop") and the **blue camera
"SCENIC STOP" pin** as separate layers.

| Time | Beat | Motion |
|---|---|---|
| 0.0 – 1.4 | Spread out | Pins spread along the route (Arjun ahead, Kabir far behind), drifting slowly forward. |
| 1.4 – 2.2 | The call | Regroup banner slides down from the top into ~14% height (gentle spring, no bounce). Scenic Stop pin scales 0.8→1.0 + fades in on the route mid-frame; **one** soft ring pulse (1 Hz). |
| 2.2 – 5.6 | Converge | Riders ahead slow and stop at the pin; Kabir's pin moves faster to close the gap. Distance labels count down to "0 m". |
| 5.6 – 7.0 | Together | All four pins clustered round the Scenic Stop pin (matches `06`). Hold. Banner stays. |
| 7.0 – 7.5 | Release | Banner slides up out; pins fan back out to their 0.0 s positions. |
| 7.5 – 8.0 | Loop | Dissolve to frame 0. |

**Poster:** frame at **6.2 s**, banner + all four gathered at the pin.

**Emergency:** the copy says "One tap for emergencies", which is true (`07_emergency_alert.png`).
Don't animate it into this loop: a red, pulsing alert repeating every 8 s on a welcome screen
reads as alarm, and pulsing red is the riskiest thing for photosensitive viewers. If you want it
shown, use a **static** emergency still as an alternate poster in an A/B test, not motion.

### Video 3: "One link. Everyone's in." (`onboarding_invite`, 8.0 s)

**Story:** the leader shares one link; riders pop into the lobby until the whole crew is ready.

**Sources:** `08_lobby_leader.png` (lobby, early), `11b_lobby_4_riders_full_roster.png` (final
roster), `09_share_sheet.png` (link preview: "convotrack.in"), `10_join_sheet.png` (CODE VERIFIED
card).

**Build:** use the lobby's **destination photo strip** (Nandi Hills, keep "Photo: Kavya Hegde ·
Google") as the top of the action zone, the stat pills row (DISTANCE · RIDERS · STATUS · CODE)
under it, then the **SQUAD ROSTER** list. Crop out the lobby's own bottom button and tab bar.

| Time | Beat | Motion |
|---|---|---|
| 0.0 – 1.0 | Just you | Roster shows only **Arjun Rao · LEADER · READY**. Pills: RIDERS **1**, STATUS **Solo**. |
| 1.0 – 2.2 | Share | The link icon (roster header) gets a tap ring; a neutral message bubble carrying the **convotrack.in** link card (from `09`) lifts off and floats out of frame right. No messaging-app branding. |
| 2.2 – 5.2 | They arrive | Rows slide in from the right, one every ~0.9 s: **Meera Iyer**, **Kabir Shah**, **Ananya Das**, each landing as WAITING then flipping to **READY** 0.4 s later. RIDERS ticks 1→2→3→4. |
| 5.2 – 5.8 | All ready | STATUS pill changes to **● All ready** (matches `11b`). |
| 5.8 – 7.5 | Hold | Full roster, still. |
| 7.5 – 8.0 | Loop | Dissolve to frame 0. |

**Poster:** frame at **6.5 s**, full roster, "All ready".

*Optional alt (A/B):* replace 1.0–2.2 with the **join sheet** card (`10`: "CODE VERIFIED ·
Sunrise at Nandi Hills · Arjun Rao · 2/5") sliding in from a second-phone angle. It shows the
receiving side instead of the sending side.

**Invite code:** the code shown (DTPSDT) belongs to the completed shoot ride and can no longer be
joined. That's fine, but if you'd rather nobody tries it, retype it to any 6-letter code in the
same font.

---

## 4. Delivery spec

| | |
|---|---|
| Canvas / export | Work at 1206×2622; export **1080×2340** (19.5:9), `resizeAspectFill` in app |
| Codec | H.265 (HEVC) `.mp4`, 30 fps, **no audio track at all** |
| Length | 7.0 s / 8.0 s / 8.0 s, seamless loops |
| Size | ≤ 1.5 MB each (≤ 4.5 MB total, bundled) |
| Poster | `.heic` of the named poster frame, same size; add to the asset catalog as `onboarding_<name>_poster` |
| Colour | Rec.709, dark plates; check the 55–100% band against white body text ≥ 4.5:1 |
| Faces | 4 portraits, provenance noted (generator + date) in `docs/onboarding-screenshots/` |

Encode (once you have a master `.mov`):

```bash
ffmpeg -i master.mov -an -vf "scale=1080:2340:flags=lanczos,fps=30" -c:v libx265 -crf 30 -preset slow -tag:v hvc1 -pix_fmt yuv420p onboarding_tracking.mp4
```

## 5. Review checklist (before bundling)

- [ ] Nothing on screen the app can't actually do; no drawer, no branded messaging UI
- [ ] Google Maps logo and photo credit intact wherever map/photo shows
- [ ] All key action inside 12–55% height; no lime below 55%
- [ ] Loop seam invisible (watch 5 loops)
- [ ] No flashes > 1 Hz; no red pulsing
- [ ] Poster alone tells the story (view with Reduce Motion on)
- [ ] Body text ≥ 4.5:1 over the brightest frame, with Increase Contrast on
- [ ] "Demo Demo" retyped to "Arjun Rao" in lobby shots
- [ ] Files named exactly as in the table at the top; < 1.5 MB each
- [ ] Not used as App Store previews
