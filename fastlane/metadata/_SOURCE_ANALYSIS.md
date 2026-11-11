# Source analysis — ConvoTrack (do this before translating anything)

## Brand structure
- **BrandWord**: `ConvoTrack` — proper noun, the wordmark. NEVER translated.
  - Latin-script locales: keep `ConvoTrack` verbatim, exact casing.
  - Non-Latin scripts (Cyrillic, Greek, CJK, Arabic, Hebrew, Thai, Indic):
    TRANSLITERATE into the local script (e.g. ja `コンボトラック`, ru `КонвоТрек`,
    hi `कॉन्वोट्रैक`, ar `كونفوتراك`). A Latin brand in a Devanagari listing reads as
    foreign noise.
- **DescriptorWord**: `Moto Group Ride` (name) / `Motorcycle ride tracker & map`
  (subtitle) — common nouns. These are SEARCH VOCABULARY: translate to the term
  local riders actually type, not a literal gloss.
  - Order is fixed in every locale: **descriptor first, brand second.**
  - Name format: `<local descriptor> — <brand>`  (em dash, spaces around it)

## Domain vocabulary — decisions
| Term | Decision |
|---|---|
| rider / riders | translate (motorcyclist sense, NOT horse-riding — this is the #1 mistranslation risk) |
| pack / group / convoy | translate as "group of motorcyclists riding together" |
| regroup | translate by meaning: "gather the group back together" |
| Ride Leader / Pace Keeper / Trail Guardian / Formation Rider | TRANSLATE (descriptive roles, not brands). Keep them as a consistent set of four. |
| ETA | translate or use the locale's conventional abbreviation |
| QR | keep `QR` everywhere |
| GPS | keep `GPS` in Latin scripts; use the conventional local form elsewhere |
| ConvoTrack Pro | brand + `Pro`; `Pro` stays `Pro` (or local convention), brand follows the transliteration rule above |

## Idioms — translate by MEANING, never literally
- "a scattered line of headlights" → the image of a group strung out and split up
- "before they have their gloves on" → "in seconds / before they've even set off"
- "not from who signed up first" → earned by riding, not by registration order

## Verbatim atoms — byte-identical in all 50 locales
- `https://convotrack.in/privacy`
- `https://convotrack.in/terms`
- `ConvoTrack` (Latin locales only — see transliteration rule)
- `Apple Account`, `QR`
- `365`, `24 hours`, `six-character` (translate the word, keep the number meaning)

## Hard rules
- Char limits: name 30, subtitle 30, keywords 100, promotional_text 170, description 4000.
- German, Finnish, Turkish, Hungarian, Tamil, Malayalam expand badly. Source name is
  28/30 and subtitle 29/30 — there is NO headroom. In those locales, SHORTEN the
  descriptor rather than overflow (e.g. drop "& map" from the subtitle).
- keywords: comma-separated, NO spaces after commas, no duplicate phrases,
  ADAPT the same concept list — never invent geo filler ("motorcycle gps germany").
  Concept list to adapt: motorcycle gps / ride with friends / live location sharing /
  route planner / rider / pack / touring / biker.
  If a concept has no local search equivalent, DROP it and spend the chars on the next one.
- Never mention price, discounts, or the word "free" anywhere.

---

# Round 2 (Nov 2026) — Regroup & SOS angle (see docs/aso-review.md)

Sources are now the four English locales: en-US (US wording) and en-GB (UK/India wording).

## What changes per locale
1. **name** — keep the locale's existing name UNLESS its descriptor is awkward or untranslated.
   Pattern stays `<local descriptor> — <brand>`. en-GB/en-AU/en-CA = `Bike Group Ride — ConvoTrack`.
2. **subtitle** — NEW angle: "Regroup & SOS for <bike/motorcycle> groups" (en-GB) /
   "Motorcycle crew regroup & SOS" (en-US). Translate the MEANING: gather-the-group-back-together
   + SOS/emergency alert + for motorcycle groups. Use the word local riders use for motorcycle
   (e.g. "moto", "Motorrad", "बाइक"). "SOS" stays Latin "SOS" where it is the local convention
   (most locales); otherwise the local word for emergency alert. ≤30 chars.
   The subtitle must NOT repeat a word already in the name (fixes name/subtitle overlap).
3. **keywords** — concept list (adapt, in priority order, drop concepts with no local search term):
   convoy / motorcycle gps / biker / location sharing / route planner / riding club /
   touring / road trip / rideout / navigation / motorcycle (if not in name/subtitle).
   No word that already appears in name or subtitle. No spaces after commas. Use the budget:
   aim for 90–100 chars (CJK: fill with more concepts; they are short).
   Never brand words, never "free", never Apple product names, never geo filler.
4. **promotional_text** — translate en-US promo (≤170). India/Pakistan/Bangladesh locales
   (hi, bn-BD, gu-IN, kn-IN, ml-IN, mr-IN, or-IN, pa-IN, ta-IN, te-IN, ur-PK) use the en-GB
   version with "fuel or chai stop".
5. **description** — take the locale's EXISTING description (already translated, vetted
   vocabulary) and:
   a. after the 2nd paragraph insert a translation of:
      "Live location in a group chat shows you dots on a map. ConvoTrack shows you who has
      dropped behind, and lets you call the regroup."
   b. reorder the sections to: LIVE GROUP MAP → ONE TAP TO REGROUP → EMERGENCY ALERT →
      JOIN IN SECONDS → TURN-BY-TURN NAVIGATION → RIDE SUMMARY → RIDE ROLES → RIDE HISTORY →
      CONVOTRACK PRO, then the subscription legal paragraph and the two URL lines unchanged.
   Do not otherwise rewrite the text.

## Cross-localization pairs (one storefront indexes both — keep keyword fields DISJOINT)
- India: en-GB + hi → hi must not repeat any en-GB keyword (en-GB is Latin; hi may use
  Latin only for terms absent from en-GB).
- US: en-US + es-MX → es-MX must not contain biker, gps, convoy, rideout or any en-US term.
- Canada: en-CA + fr-CA → disjoint.
