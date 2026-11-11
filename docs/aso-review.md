# ASO review — proposed changes (v2.0.1 → next version)

Source: the live App Store Connect listing (50 locales, pulled 11 Nov 2026), checked against the founder-marketing evidence in `founder/` (competitors.md, panel/results.md).
The buyer panel is **simulated (20 buyers)** and the ranking data is an **iTunes Search API proxy** (no ASO tool). Treat both as direction, not proof.

## Verdict
The vibe-aso pass left the mechanics clean: no field over its limit, the keyword fields are formatted correctly and the URLs are intact. **Positioning is the weak point.** "Ride tracker & map" is the phrase every competitor already uses, and buyers read it as Strava, a sat-nav or an anti-theft tracker. Nobody claims *keeping the group together* (regroup, who's dropped behind, SOS), and that is ConvoTrack's real edge.

**Positioning line:** For riding groups who keep losing riders at junctions, ConvoTrack is the group-ride app that shows who has dropped behind, calls the regroup and sends the SOS. WhatsApp live location doesn't do that.

## Fix now (no release needed)
| # | Change | Why |
|---|---|---|
| 1 | **Screenshot 1 typo: "NEVER LOOSE YOUR GROUP" → "LOSE"** | Live on the store and the first thing searchers see |
| 2 | **Promo text** (en-GB, 152 chars): *"See who has dropped behind, call a fuel or chai stop for the whole group, and send an SOS with your exact location. Riders join with a 6-character code."* en-US: the same without "or chai" (144) | The current promo is a changelog ("fresh new look") and landed with 0 of 20 buyers. The new one answers the two biggest objections: "everyone has to install it" and "WhatsApp already does this" |

## Next version: name, subtitle, keywords
| Locale | Field | Now | Proposed |
|---|---|---|---|
| en-GB (UK + India) | Name | Group Ride Track - ConvoTrack | **Bike Group Ride - ConvoTrack** (28) |
| en-GB | Subtitle | Motorbike ride tracker & map | **Regroup & SOS for bike groups** (29) |
| en-GB | Keywords | motorbike gps,ride out,rideout,bike meet,… | `rideout,convoy,motorbike,motorcycle gps,biker,location sharing,route planner,riding club,touring` (96) |
| en-US | Name | Moto Group Ride — ConvoTrack | keep (#10 US for "group ride") |
| en-US | Subtitle | Motorcycle ride tracker & map | **Motorcycle crew regroup & SOS** (29) |
| en-US | Keywords | motorcycle gps,ride with friends,… | `convoy,rideout,biker,location sharing,route planner,riding club,touring,road trip,gps,navigation` (96) |
| hi | Subtitle | ग्रुप राइड ट्रैकर और लाइव मैप (repeats the name) | **मोटरसाइकिल ट्रैकर, लाइव मैप** (27) |
| hi | Keywords | group ride,bike ride,… (≈30 chars overlap en-GB) | `highway,safar,काफिला,बाइकर,लोकेशन शेयर,रूट प्लानर,टूरिंग,दोस्तों के साथ,यात्रा,नेविगेशन,बाइकिंग` (95, no overlap with en-GB) |
| en-CA | Name | the en-US "Moto…" name | use the en-GB-style "Bike Group Ride - ConvoTrack" |

Why:
- **"Bike…" leads the name.** Indian buyers type "bike group …" and none of them typed "motorbike". India indexes en-GB + hi, so en-GB carries India. "Group Ride Track" is awkward phrasing and repeats "Track" from the brand.
- **"Regroup" and "SOS" go in the subtitle (decided).** They are the panel's winning angle in every market, and no competitor uses "regroup". The trade-off: we drop "tracker & map", which is crowded and was misread anyway. "motorbike" moves into the en-GB keyword field so it stays indexed.
- **Keyword fields.** Remove the words that already appear in the name or subtitle (a problem in 40 locales). Drop the generic terms "pack" and "rider". Add `convoy`, `riding club` and `location sharing`, where we are not in the top 50 and the top results have almost no ratings.

## Next version: other locales (mechanical)
- **40 locales:** remove keyword-field words that repeat the name or subtitle.
- **22 locales** (hi + all Indic, en-AU/CA, fr-CA, id, ms): the name and subtitle repeat each other. Move the second keyword into the subtitle.
- **Unused budget:** zh-Hant (35 chars left), zh-Hans/or-IN (31), ko (28), ja/kn-IN (26). Fill it with local terms.
- **es-MX:** drop "biker" (duplicates en-US for the US store) and "viaje" (wrong intent).
- Then re-cascade the new en-GB angle to all locales with the vibe-aso phase-2 method.

## Next version: description (en-GB / en-US, then cascade)
- **Opening two lines:** keep "Ride as a pack…". Then add one line of contrast with WhatsApp: *"Live location in a chat shows dots. ConvoTrack shows who has dropped behind, and lets you call the regroup."*
- **Section order:** Live group map → Regroup → Emergency → Join in seconds → Navigation → Summary → Roles. Roles goes last because 3 of 20 buyers called it a gimmick.
- Make no "members join free" claim. Under the current trial rules, an expired joiner can't join.

## Screenshots (biggest conversion lever)
Right now there is 1 set: en-GB, 6.5" only. Every other locale falls back to it. There is no 6.9" set and no preview video.
1. Shot 1: **"Group motorcycle rides. Never lose a rider."** Use the same style across all five shots (shot 1 is dark, shots 2–5 are light).
2. Shot 2: **"See who's dropped behind"** over a real live-ride map. It currently shows the lobby under a "Live Tracking" label.
3. Shot 3: **"Call a fuel stop in one tap"** (Regroup moves up from shot 4).
4. Shot 4: **"One-tap SOS to the whole group"**. Shot 5: Summary. Remove the stray "REHABS" test text.
5. Add the 6.9" set, then localize the captions for hi and the main Indic locales.

## Flagged, not proposed here
- £39.99/yr is above REVER's £34.99 in the UK.
- Buyers say the 3-day trial is too short for Sunday riders.
- US groups find the 25-rider cap small.
- Validate "bike group ride" and "regroup" in a real ASO tool (Astro/AppTweak) before committing the name.

## Decisions for you
1. ~~Subtitle angle~~: decided, **Regroup & SOS**.
2. Push the promo text now and fix the screenshot typo now?
3. Locale scope for the cascade: all 50, or en + India first?
