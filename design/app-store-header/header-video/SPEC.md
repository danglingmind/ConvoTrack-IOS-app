# ConvoTrack — App Store product page header video

GOAL:    A first-time visitor sees a real group ride moving live on a map and gets the one idea:
         with ConvoTrack you never lose the pack.
OUTPUT:  HyperFrames, 3840 x 1646 (21:9), 30 fps, silent (the header plays muted), seamless loop.
TIME:    20 s x 30 fps = 600 frames.

LOOK:    Ground = the real map: Google Static Maps hybrid (satellite + roads + labels) at zoom 18,
         around the real ride-demo route up Nandi Hills (Nandi Hills Main Rd → Nandi Hills,
         2.66 km). The app's dark road style was tried first and read as a blank green field
         here (the hill is all forest), so it was dropped. No void, no gradients.
         Ink #F5F7FA, accent #CDEF1E (route, rider rings, one word per line), scenic #5AB8FF
         only on the regroup pin and banner.
         App UI rebuilt from source at 3.6 px per iOS point: rider marker
         (`renderRiderIcon`: 32 pt circle #1E2A38, 1.25 pt lime ring, name above, mono lime
         distance below on #1A1A1A/75%), user chevron (44x49 pt, lime, white 7.5% keyline),
         route (planned lime 28% 3 pt, casing lime 30% 13 pt, core lime 8 pt), turn card,
         `DSBanner` regroup tone, `RegroupPin` SCENIC.
         Display: SF Pro (system-ui) 900, width 125, 120 px, tracking -2 px. Eyebrow 34 px 700
         caps, tracking 6 px, lime. Mono: JetBrains Mono 600 (bundled; SF Mono is not available to the renderer).
         Shadow on UI cards 0 24 60 #000/55%. Map vignette none.
OBJECTS: four riders (Arjun leads, Meera, you = Ananya as the chevron, Kabir trailing), the
         lime route ahead of you, the destination turn card, a Scenic stop regroup pin.
MOTION:  Riders: constant 37.5 m/s along the route (compressed time), gaps breathe ±20 m on a
         20 s period so the distance labels tick. Camera follows the pack centroid (1 s
         window average), frame ≈ 1200 m wide, pack anchored at 70% x 50%; push to 1.07x during beat 1, back by beat 4.
         Text enters per word (blur 8→0 px, 0.13 s, 0.067 s apart) or whole-line blur;
         exits blur 0→8 px + fade in 0.2 s. UI cards arrive y+40→0, expo.out 0.6 s, leave
         power3.in 0.35 s. No bounce, no loops on titles.
SHOTS:   One continuous follow shot.
         f0–24     riders already rolling, turn card up, no text (matches the loop seam)
         f24–150   "Every rider, live on one map." — name tags light lime, camera pushes in
         f162–294  "See the gap to every rider." — distance tags grow 1→1.22, ticking
         f306–450  "Regroup in one tap." — Scenic stop pin lands on Google's real "Rock photo points at
                   Nandi hills" (route 1.86 km), DSBanner slides in
         f450–465  pin and banner leave (before Arjun reaches the pin)
         f462–576  "Never lose the pack." — camera eases back
         f579–600  crossfade to the frame-0 state for the loop
BANNED:  invented UI or data; glow orbs, particles, lens flares; tilted 3D UI; click rings;
         bounce; titles drifting after they land; a logo docked in a corner; prices, URLs,
         awards, © symbols, other platforms' logos (Apple asset rules).
QA:      f0 vs f599 (seam); f90 (beat 1 read); f230 (distance tags large and legible);
         f380 (pin + banner both in frame, banner not over a rider); f520 (tagline);
         every rider inside the frame in every sampled frame; key text inside 80% title safe.
