---
name: ad-creative
description: Design and render ConvoTrack paid-social ad creatives (Meta/Instagram/Facebook feed 4:5, square 1:1, Stories/Reels 9:16) from REAL app screenshots captured from the iOS simulator, in the app's own dark + lime brand look. Use whenever the user asks for an ad image, ad creative, Meta/Instagram/Facebook ad, Stories/Reels creative, "concept N of the six", a marketing visual, a social post graphic, or an App Store/Play style promo image for ConvoTrack, even if they don't say "skill" or give a detailed brief. Also use when they want a creative re-cut in another size, another headline, or a new screenshot swapped in. Video/walkthrough ads are a later mode (see "Video").
---

# ConvoTrack ad creatives

You are acting as a senior performance-ad designer. The job is a scroll-stopping, honest ad whose
image is the real product. A rider thumbing through Instagram decides in under a second, so each
creative has ONE idea, ONE headline, and ONE piece of real UI proof.

Why the rules below exist: ads that show invented UI get rejected by store/ad reviewers and
disappoint users on install; ads with five messages convert worse than ads with one. Everything
here serves "one clear idea, shown with the real app".

## Inputs you need (ask only for what's missing)

A concept = **slug**, **angle** (the one idea), **headline**, optional **eyebrow / sub / chip**, and
**which real screen proves it**. The six planned concepts are in `references/concepts.md`, so
"do concept 1" is a complete brief. For anything new, write the concept down there first.

## Workflow

1. **Pick the concept and the proof screen.** Read `references/concepts.md` and
   `references/screens.md` (library of real captures in `docs/onboarding-screenshots/`, 1206×2622).
   Look at the candidate screenshots (Read them) and choose the one where the proof is
   unmistakable at thumbnail size and sits in the upper two thirds of the phone, because
   feed bleeds the phone off the bottom and Stories overlays the bottom 20%.
2. **Recapture only if the library can't prove the point.** Needs a state that doesn't exist yet
   (e.g. one rider far behind the group)? Capture it from the simulator: see
   `references/capture.md`. Never mock or redraw UI; framing, tilt and crop are fine, and the one allowed pixel edit is
   recolouring the highlighted rider's marker ring (see Design principles).
   Screens must show the current build, the demo riders' names, no personal data, `9:41`
   status bar, full battery.
3. **Write the copy.** Headline ≤ 6 words, plain, rider-voiced; mark the payoff word with
   `*asterisks*` (renders lime) and use `|` for a line break. Keep claims to what the app does
   today (`references/brand.md` → Claims). Do not invent numbers, ratings, user counts or "free"
   wording: "Free to try" must be confirmed against the current paywall first.
4. **Render all three sizes** with the script (never hand-build HTML per ad). The default,
   approved style is the **hero**: real satellite map background, oversized elevated phone
   cropped by the bottom edge, the rider the card is about marked by recolouring their marker
   ring orange in a copy of the screenshot, and a glowing feature card joined to that marker by
   a dotted leader (concept 1 v2 is the reference). First make the highlighted screenshot:

   ```bash
   # centre (source px), the marker's own ring band, DS.Status.food orange, then the bold
   # stroke band (29..40) and glow radius (51) so it stands out at phone size
   swift .claude/skills/ad-creative/scripts/recolor_ring.swift \
     docs/onboarding-screenshots/01_nav_hero_all_riders_ahead.png \
     design/ad-creatives/c1-where-did-everyone-go/shots/01_nav_hero_meera-orange.png \
     484 927 29.5 37.5 FF8A4C 29 40 51
   ```

   Bold is the default: the marker's own 4–8 px ring recoloured alone was too subtle at phone
   size. 29/40/51 keeps the initial letter, name and distance label clear; a 56 px glow
   started tinting the distance label.

   Then render with `--shot` pointing at that copy:

   ```bash
   .claude/skills/ad-creative/scripts/render.sh \
     --slug c1-where-did-everyone-go \
     --shot design/ad-creatives/c1-where-did-everyone-go/shots/01_nav_hero_meera-orange.png \
     --h1 "Where did|*everyone go?*" --eyebrow "Group ride tracking" \
     --sub "See every rider live, on one map." \
     --chipk "Live gap" --chip "Gap to every rider" --chip-icon gap \
     --scale xl --sat 13.3712,77.6792,1300 --pin 0.4013,0.3535 --pin-r 0.036
   ```

   - `--sat lat,lon,spanMetres` renders a real Apple Maps satellite background per size
     (`scripts/satellite.swift`, MapKit, no API key; cached in `<slug>/bg/`). Pick a place that
     says "ride" from above: winding roads, hairpins, coast roads. Default: the Nandi Hills
     hairpins (the demo ride's own road), `13.3712,77.6792,1300`. Aim for the road to show on
     the **left** third, because the hero phone sits right of centre. Finding a new spot takes a
     few test frames: render 1080×1350 candidates, Read them, adjust; ~0.64 m/px at span 1300.
   - **Find the marker:** crop the screenshot around the rider (`sips -c 220 220 --cropOffset
     <y> <x>`), enlarge it 3× and Read it. The ring centre and outer radius are in source
     pixels (iPhone 17 capture: rider marker outer radius ≈ 37 px, stroke ≈ 4–8 px, so a band
     of ~29.5–37.5). Check the recoloured crop the same way: only the ring may change. The
     script only swaps lime inside that band, so the route, name and distance stay lime.
   - `--pin fx,fy` = the marker centre as a fraction of the screenshot (x/1206, y/2622); the
     dotted leader runs from the card and stops just outside the marker (`--pin-r`, default
     0.031 of the screenshot width = a plain rider marker; 0.036 for the bold ring).
   - **Variant B, rider card:** `--rider "Meera,M,280 m"` (name, initial, distance as shown on
     the screenshot) replaces the card's icon with that rider's map marker: name tag, lime-ringed
     disc, lime mono distance. It is drawn as a vector copy of the app's marker so it stays
     sharp at card size (a screenshot crop at 2.5× is blurry and carries a strip of route).
     Use the ORIGINAL screenshot (no recolour); the leader joins the card's marker to the real
     one. Tall cards are kept above the credit / Stories overlay automatically. Reference:
     `design/ad-creatives/c1b-rider-card/`. **B is the approved style** (A, the orange ring, is
     kept only as history).
   - **Rule — every visible rider avatar gets a portrait. If one is missing, stop and ask the
     user for it before rendering.** List which riders appear (map markers, strip, edge chips,
     alert text, card) and check `docs/onboarding-screenshots/portraits/` for each. Never ship
     a letter avatar, never reuse another rider's face, never generate one yourself unasked.
     Off-screen edge chips (green ring + distance) are avatars too.
   - **Rider portraits:** riders show AI-generated profile photos, not letters, everywhere they
     appear: map markers, the top rider strip and the card. The app really does this for riders
     with a photo (`GoogleMapView.renderRiderIcon`: aspect-fill, clipped, ring on top), so
     `scripts/avatars.swift` composites portraits into a copy of the screenshot inside each
     circle's inner radius, leaving rings, name tags and distances as captured; `--rider-img`
     puts the same portrait in the card. Portraits come from the user, in
     `docs/onboarding-screenshots/portraits/` (brief in `docs/onboarding-video-script.md` §2,
     provenance table in its README). Measure each circle (centre + inner radius) and check with
     `TEST` discs before using real faces. Concept 1 B is one command: `scripts/build-c1b.sh`.
     Illustrative riders, not customers: never pair faces with quotes or ratings.
     Each rendered concept gets its own `scripts/build-<slug>.sh` (portrait specs + render
     flags), so it can be re-rendered in one command: `build-c1b.sh`, `build-c2.sh`.
   - **Keep the card's claim to what the screen shows.** If the feature (e.g. a group-split
     alert) isn't visible on the screenshot, either capture it or pick a card that is.
   - **Text-only label (`--chip-style text`):** when the screenshot's own UI already shows the
     feature (an alert card, a banner), don't add a feature card, marker or dotted line — that
     doubles the card. Name the feature in plain type on the map instead (`--chipk` kicker +
     `--chip` name, e.g. "Live feature / Group split alerts"). Reference: concept 2.
   - `--scale std --look dark` gives the older plain dark style; `--layout split`, `--tilt`,
     `--shift`, `--chip-dx/--chip-dy`, `--chip-icon people|gap|alert|link|flag`, `--sizes`.

   Output: `design/ad-creatives/<slug>/<slug>-{feed,square,story}.png` (1080×1350 / 1080×1080 /
   1080×1920, flattened, no alpha) plus `hires/` @2×. `qa.sh` runs automatically and fails on
   wrong size, alpha or >30 MB.
5. **Look at every size yourself** (Read the PNGs) against the checklist in `references/qa.md`
   before showing anyone. Fix and re-render; typical fixes are `--shift`, a shorter headline,
   or a different screenshot. The first render is a draft.
6. **Show the user** the three PNGs with: the one-line idea, the headline/primary text/CTA to
   paste into Meta (`references/concepts.md` has the primary text), and anything unverified
   (claims, "free" wording, map-imagery licence). Don't upload to Meta or create ads unless asked.

**Imagery licence (open):** Apple Maps satellite imagery in a paid ad is not confirmed as
allowed. Until the user confirms the licence, say so with every satellite creative; the
alternatives are a licensed provider (e.g. Google Static Maps with the user's key, keeping
Google's attribution) or the user's own aerial/drone photo via `--bg <image>`.

## Design principles (the "why")

- **Thumbnail test:** squint at the feed PNG at phone size. If you can't read the headline and spot
  the proof in one glance, simplify. Headline sizes in the template are tuned for this; don't shrink them to fit more words.
- **One accent:** lime `#CDEF1E` for the payoff word, eyebrow and chip only. The danger tint
  appears only for emergency concepts. Everything else stays near-black and white.
- **The phone must look like a real iPhone.** The template builds an iPhone 17-class body to
  real proportions: titanium band with bright chamfers, black glass border, display corner
  radius from the real device, action + volume buttons left, side button right. Don't
  simplify it to a rounded rectangle, and don't put coloured rims on the hardware.
- **The product is the hero:** the phone is huge (~60% of the width), right of centre, cropped
  by the bottom edge so the screenshot's feature reads large. It floats: slight 3D tilt, lime
  rim glow and a cast shadow thrown down-left onto the map (the gap between phone and shadow is
  what reads as height). The user rejected the plain dark background as boring: the real map
  under the phone is what makes it feel like a ride.
- **The feature card is the second hero:** large, lime-rimmed, glowing, on solid glass, sitting
  on the map at the phone's left edge, tied to the exact UI by a dotted leader. It never covers
  the UI being advertised (rider pins, banners): a test render once covered the emergency
  banner with its own chip, another covered a rider pin. Card text ≤ ~22 characters; leave a
  visible stretch of dotted leader between card and marker.
- **Highlight by recolouring the marker ring, nothing else.** Rejected by the user, in order:
  a lime ring drawn around the rider (looked bolted on), then a magnified square crop (scaled
  the route and neighbouring riders with it, distorting the map). Approved: the rider's own
  marker ring recoloured orange (`#FF8A4C`, `DS.Status.food`) and thickened with a soft glow,
  in a copy of the screenshot. This is the one pixel edit allowed; the original screenshot stays untouched in
  `docs/onboarding-screenshots/`, edited copies live in `<slug>/shots/`.
- **Satellite is graded, not edited:** dark at the top for the headline, clear through the
  middle so the road reads. Credit "Imagery: Apple Maps" stays bottom-left, on map, never on
  the screenshot (it would read as app UI).
- **Headline wrapping:** the two-line headline must stay two lines in all sizes (story h1 is 112 px
  for this). A one-word orphan line means shorten the words or force `|` breaks.
- **Story safe zones:** no text in the top ~250 px or bottom ~380 px; the template starts copy at 280 px.
- **Rider-real voice:** short, concrete, a little wry ("Where did everyone go?"), no marketing filler
  ("revolutionary", "seamless").

## Video (later mode)

Not built yet. When added it should reuse this template's look: record the walkthrough with
the ride-demo skill (one device, one encoder), frame it in the same phone shell, caption with the
same headline, export 9:16 and 4:5 MP4 ≤ 30 s. Until then, say video isn't available and offer a still.

## Files

- `scripts/render.sh`, `scripts/qa.sh`: render + verify. `assets/template.html`: the one composition.
- `references/brand.md`: tokens, type, claims you may and may not make.
- `references/concepts.md`: the six planned concepts with headline, primary text, CTA, best screenshot.
- `references/screens.md`: what each library screenshot shows.
- `references/capture.md`: capturing new real screens from the simulator.
- `references/qa.md`: pre-delivery checklist and Meta specs.
