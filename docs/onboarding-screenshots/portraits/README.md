# Rider portraits (onboarding clips)

Drop one square-ish image per rider here, named by first name:

    arjun.png   meera.png   ananya.png   kabir.png      (.jpg / .heic / .webp also work)

then re-render: `tools/onboarding-video/.venv/bin/python tools/onboarding-video/make.py`

Until a file exists, that rider is drawn with ConvoTrack's own letter avatar (what the app shows
for a rider without a profile photo). Brief: docs/onboarding-video-script.md section 2.

The same portraits feed the paid-ad creatives: `.claude/skills/ad-creative/scripts/build-c1b.sh`
composites arjun / meera / ananya into the map markers, the rider strip and the feature card.

## Provenance (required, one line per portrait)

| Rider | File | Generator / source | Date | Notes |
|---|---|---|---|---|
| Arjun Rao | arjun.png (square face crop of source/arjun-source.webp) | AI-generated, supplied by the user; generator not recorded | 2026-10-29 | olive tee, no jacket |
| Meera Iyer | meera.png (square face crop of source/meera-source.webp) | AI-generated, supplied by the user; generator not recorded | 2026-10-29 | source shows a RYNOX jacket logo; the crop excludes it, keep it out of any larger crop |
| Ananya Das | ananya.png (square face crop of source/ananya-source.webp) | AI-generated, supplied by the user; generator not recorded | 2026-10-29 | source shows a partial jacket logo; the crop excludes it |
| Kabir Shah | - | not supplied yet | | |

Illustrative riders, not customers: never pair them with quotes or ratings.
