# ConvoTrack brand for ads

Source of truth is `convotrack/DesignSystem/Tokens.swift`. **CLAUDE.md still lists the old lime
`#caf300`; the app ships `#CDEF1E`.** Use the values here.

| Token | Value | Use in ads |
| --- | --- | --- |
| Background | `#090B0D` (radial to `#040506`) | Canvas |
| Accent (lime) | `#CDEF1E`, glow `rgba(205,239,30,.28)` | Payoff word, eyebrow, chip icon, road ribbon |
| On accent | `#0C0E02` | Text/icons on lime |
| Text primary / secondary | `#F5F7FA` / `#B4B9C1` | Headline / sub |
| Danger | `#FBB0A9` (strong `#E5484D`) | Emergency concept only |

Type: system sans (SF) heavy, extended width (`font-variation-settings: "wdth" 125`), tight
tracking (-0.035em) for headlines; eyebrow/chip labels 700, wide tracking, uppercase. The app has
no custom font files, so don't introduce one.

Motifs: real satellite road (hero style, preferred); phone shell tilted ~4° and floating; glass
feature card with a lime icon tile, lime rim and glow; the featured rider's marker ring
recoloured orange `#FF8A4C` (`DS.Status.food`) in the screenshot, joined to the card by a
dotted lime leader. No shapes drawn over the UI, no magnified crops.
The plain dark background with the lime road ribbon (from `design/app-store-header/`) still
exists as `--look dark` but the user found it boring for ads.

## Claims: what you may say
Only things the app does today:
- Live positions of every rider in the group on one map; distance (gap) to each rider.
- Group-split alert when someone drops back; regroup call (fuel / food / scenic stop) to all riders.
- Emergency alert sent to the whole group.
- Create a ride and share one invite link; riders join from the link (HTTPS universal link, QR also exists).
- Turn-by-turn navigation with voice prompts; ride summary (distance, duration, max group split).

Do NOT claim: accident/crash detection, calls to emergency services, "SOS" to authorities
(a competitor advertises these, ConvoTrack doesn't), rider counts, ratings, awards, offline
maps, anything about price or "free" until confirmed against the current paywall
(trial-first freemium; see CLAUDE.md "Access").

Never put coordinates, real names, emails or invite codes on an ad. Demo riders (Arjun, Meera,
Ananya, Kabir) and a demo ride ("Sunrise at Nandi Hills") are fine.
