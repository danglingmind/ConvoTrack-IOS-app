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
