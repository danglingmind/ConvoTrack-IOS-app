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

### 1.2 Composition: full-screen video, copy on its own gradient

The clip plays **edge to edge** (behind the status bar and home indicator) and is never darkened
or desaturated in the video itself. `OnboardingFlowView` pushes it into the background with a
**dark teal tint-and-dim** (`#08212A` at 55%, lime's opposite hue, so the clip's lime turns olive
and Continue is the only true lime on screen) plus a **vignette** (radial, clear around the riders at ~38% height,
55% at the edges), then lays two gradients over it:

```
 0% ┌───────────────────────────┐
    │░ top fade, ~96 pt ░░░░░░░░│  surfaceDim 70% → clear: clock, ⏸ and Skip stay readable
    │ [⏸]               [Skip] │  (keep key action out of the top ~14%)
    │                           │
    │   OPEN MAP / SCENE        │  the story plays here, but the scene itself runs the full
    │   (≈ 14% – 58%)           │  height: route, map, roster continue down the screen
    │                           │
~53%│· · · · · · · · · · · · · ·│  copy gradient starts, clear, 100 pt above the copy
    │▒ LIVE TRACKING           ▒│  ~25% at the eyebrow
    │▒ Every rider. One map.   ▒│  ~40% behind the headline
    │▓ See where your whole…   ▓│  ~48% behind the body
    │▓ ●○○○  [ Continue ]      ▓│  50% cap behind the footer and home indicator (never solid;
    │                           │  below ~45% the eyebrow fails 4.5:1)
100%└───────────────────────────┘
```

The copy gradient is **sized to the copy on screen** (measured text + footer height), not a fixed
screen fraction, so it grows with Dynamic Type. The ~58% figure is an iPhone 17 at the default
text size; content that drifts into the gradient (e.g. a rider dropping back) is simply dimmed.

- **No app chrome from the screenshots at full scale.** A screenshot's own buttons ("START
  NAVIGATION", "MARK AS ARRIVED", the stats bar) sitting under our real Continue button reads as
  two competing UIs. Crop to the *content*: the map, the banner, the roster.
- **Lime belongs to the Continue button.** `branding.md › Apply your app's accent color judiciously`.
  The lime route is content and may run the full height, but keep big lime shapes out of the
  footer area; the copy gradient (solid behind Continue) does the rest.
- **Status bar:** never include the screenshot's status bar; the device draws its own.
- **No UI that looks tappable.** Strips of chips or buttons in the clip read as foreground controls
  next to Skip / Continue. Keep the clip to the scene: map, route, pins, banners that *happen*.
- **Map markers are enlarged** (~1.65× the in-app size, arrow included) so riders read at a glance
  behind the dim; edge chips are enlarged by the same factor.

### 1.3 Motion grammar

From `motion.md › Add motion purposefully` and `accessibility.md › Be cautious with fast-moving
and blinking animations`:

- **One primary motion per beat.** If riders are moving, the camera is not, or it drifts ≤ 3%.
- **Ease, don't bounce.** `easeInOutCubic` for camera, gentle spring (damping ≥ 0.85) for cards.
  No overshoot > 4 px.
- **Speeds:** pins ≤ 75 px/s (25 pt/s) on the 1206-px canvas; camera ≤ 2% zoom/s.
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
- **Text over video:** eyebrow and body ≥ 4.5:1, headline ≥ 3:1 (large bold), against the
  brightest pixel behind each line in any frame, with the copy gradient applied. Contrast comes from
  the app's gradient, never from darkening the clip. `tools/onboarding-video/qa.py` measures it.

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

### Video 1: "Every rider. One map." (`onboarding_tracking`, 9.0 s)

**Story:** four riders strung out on a winding climb, and you can see every one of them, even
the one who drops back behind the text.

**Sources:** `01c_nav_all_four_visible.png` (plate + route trace), `02_nav_leader_offscreen_cluster.png`
(off-screen chip style).

**Build the plate:** from `01c`, remove pins, chips, banner and the stats bar; trace the route as
a vector path and redraw it (lime ahead of "you", grey + green behind). The trace is extended in
gentle curves past both ends of the screenshot so the full-height, scrolling frame never runs out
of road. Map + route fill the whole screen; nothing is darkened.

**Camera:** follows "you" (Ananya), as live navigation does, holding her at ~47% height. The map
scrolls (~75 px/s); Arjun and Meera hold their spacing on screen.

| Time | Beat | Motion |
|---|---|---|
| 0.0 – 0.6 | Settle | All four riders on the open map; route runs off the top and bottom of the screen. |
| 0.6 – 8.45 | Ride | Map scrolls under the pack; distance labels stay honest (220 m / 110 m / ~100 m). |
| 1.0 – 4.6 | Drops back | Kabir eases off (never backwards) and slides down behind the copy gradient; once he's under it his **edge chip** (avatar + distance) fades in at the bottom of the open map and tracks his distance. |
| 4.9 – 8.45 | Back in | Kabir rides harder and catches up into view; edge chip fades out. |
| 8.5 – 9.0 | Loop | 0.5 s dissolve to frame 0. |

**Poster:** frame at **0.9 s**: all four riders on the open map, before Kabir drops back.

(The rider chip strip was cut: on a background clip it read as tappable UI under Skip.)

### Video 2: "Nobody gets left behind." (`onboarding_regroup`, 8.0 s)

**Story:** one rider calls a regroup, everyone's phone shows where to wait, the pack comes
back together.

**Sources:** `05_regroup_banner_other_rider.png` (banner + Scenic Stop pin),
`06_regroup_pin_riders_gathering.png` (converged state), `01c` (spread-out positions).

**Build the plate (full-screen):** map from `05`/`06` with route, banner, chips, pins, pills and
stats bar removed. Gaps are inpainted (the buttons' lime glow is neutralised first), the area above
`05`'s nav banner is the clean map reflected back and forth, and the area below fades into plain
map. Lift the **regroup banner** ("REGROUP CALLED · Head to the Scenic Stop") and the **blue
camera "SCENIC STOP" pin** as separate layers. Markers and the "you" arrow use the same enlarged
size as Video 1 (~1.65×). The Google Maps logo sits bottom-right above the copy gradient.

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

**Build (full-screen, zoomed to ~2.2 px/pt so four rows end above the copy):** use the lobby's **destination photo strip** (Nandi Hills, keep "Photo: Kavya Hegde ·
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
| Length | 9.0 s / 8.0 s / 8.0 s, seamless loops |
| Size | ≤ 1.5 MB each (≤ 4.5 MB total, bundled) |
| Poster | `.heic` of the named poster frame, same size; add to the asset catalog as `onboarding_<name>_poster` |
| Colour | Rec.709, no baked darkening; copy contrast checked with the app's copy gradient (§1.4) |
| Faces | 4 portraits, provenance noted (generator + date) in `docs/onboarding-screenshots/` |

Encode (once you have a master `.mov`):

```bash
ffmpeg -i master.mov -an -vf "scale=1080:2340:flags=lanczos,fps=30" -c:v libx265 -crf 30 -preset slow -tag:v hvc1 -pix_fmt yuv420p onboarding_tracking.mp4
```

## 5. Review checklist (before bundling)

- [ ] Nothing on screen the app can't actually do; no drawer, no branded messaging UI
- [ ] Google Maps logo and photo credit intact wherever map/photo shows
- [ ] Video fills the screen; key action in the open map (≈14–58%), nothing darkened in the clip; no big lime behind the footer
- [ ] Loop seam invisible (watch 5 loops)
- [ ] No flashes > 1 Hz; no red pulsing
- [ ] Poster alone tells the story (view with Reduce Motion on)
- [ ] Eyebrow/body ≥ 4.5:1, headline ≥ 3:1 over the brightest frame with the copy gradient (`qa.py`)
- [ ] "Demo Demo" retyped to "Arjun Rao" in lobby shots
- [ ] Files named exactly as in the table at the top; < 1.5 MB each
- [ ] Not used as App Store previews
