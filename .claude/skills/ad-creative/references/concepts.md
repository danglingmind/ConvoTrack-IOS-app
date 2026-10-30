# The six test concepts

Each: slug · idea · image text (`--h1`) · Meta headline · primary text · CTA · proof screen.
Copy is a draft to test, not proven. Primary text first line = hook.

1. **c1-where-did-everyone-go** · problem scene
   - `--h1 "Where did|*everyone go?*"` · eyebrow "Group ride tracking" · chip: Live gap / Gap to every rider (`gap`; chip text ≤ ~22 characters or it runs off the edge)
   - Headline: Never lose your group again
   - Primary: Someone always falls behind at the first fork. ConvoTrack shows every rider live on the map, so the whole group stays together.
   - CTA: Install now · Screen: `01_nav_hero_all_riders_ahead` (three riders strung out at 430 / 280 / 140 m, all in the upper two thirds). A fresh capture with one rider clearly far behind would be stronger; not required.
   - **v2 (reference for all hero creatives):** Meera's ring recoloured and bold (`recolor_ring.swift … 484 927 29.5 37.5 FF8A4C 29 40 51` → `shots/01_nav_hero_meera-orange.png`), then `--scale xl --sat 13.3712,77.6792,1300 --pin 0.4013,0.3535 --pin-r 0.036`.
   - **v2 variant B (`c1b-rider-card`), APPROVED:** card icon = Meera's marker; rider portraits in all markers, strip and card. Build: `.claude/skills/ad-creative/scripts/build-c1b.sh` (needs arjun / meera / ananya portraits).
2. **c2-live-ride-map** · group split alert (slug kept from the first draft)
   - **Rendered (v2, current):** `scripts/build-c2.sh`. Screen `14_group_split_alert` — a real production capture (ride XJ5SXJ, leader Arjun's screen, alert "Kabir is 5.1 km behind the leader"). No feature card: the alert on screen is the proof, so the label is text only (`--chip-style text`, "LIVE FEATURE / Group split alerts", bottom-left on the map). Image text `--h1 "Nobody gets|*left behind.*"`, eyebrow "Group ride tracking", sub "Know the moment someone drops back." (dropped in story to make room). Arjun and Kabir portraits in the strip and Kabir's edge chip (visible in story only). **APPROVED** (2026-10-30).
   - Headline: Know when someone drops back
   - Primary: Someone always falls behind on the climbs. ConvoTrack alerts the group the moment a rider drops back, and one tap calls a regroup.
   - CTA: Install now
   - v1 (superseded): `01c_nav_all_four_visible` with the leader in the card; too close to concept 1.
3. **c3-emergency-alert** · safety
   - **Rendered:** `scripts/build-c3.sh`. Screen `15_emergency_alert`: a real production capture on the current build (ride GMSUGM, Arjun's screen, banner "Kabir Shah needs help — head to their location", Kabir's emergency pin 190 m up the route). Text-only label "LIVE FEATURE / Emergency alerts"; eyebrow "Group ride safety"; sub "Every rider sees who needs help, and where." (dropped in story). Arjun + Kabir portraits in the strip (story only).
   - `--h1 "One tap.|*All alerted.*"`. "Whole group alerted." and "Everyone knows." both wrapped to three lines in feed/story: keep the second line ≤ ~12 characters.
   - Headline: Emergency alert for your group
   - Primary: If something goes wrong on a ride, one tap sends an alert to every rider in the group. Don't claim crash detection or emergency-services calls.
   - CTA: Learn more / Install now · `07_emergency_alert` is the old UI, don't use it
4. **c4-share-the-link** · leader ease
   - `--h1 "Share the link.|*Everyone's in.*"` · chip: Invite / One link, no codes (`link`)
   - Headline: Start a group ride in seconds
   - Primary: Create a ride, share one link, and your group joins straight from the chat.
   - Screen: `09_share_sheet` (or lobby `11_lobby_4_riders_ready`)
5. **c5-call-a-regroup** · regroup
   - `--h1 "Fuel stop?|*Call it.*"` · chip: Regroup / Every rider gets the message (`flag`)
   - Headline: Call a regroup with one tap
   - Primary: Need fuel, food or a photo stop? Call a regroup and every rider gets the message.
   - Screen: `04_regroup_sheet`
6. **c6-ride-together** · control, real rider photo
   - `--h1 "Ride|*together.*"` · Needs a real rider photo the user supplies and has rights to (helmets on); template has no photo slot yet. Add one with the user before running.
   - Headline: Ride together, stay together
   - Primary: The live tracking app for group rides. See your riders, stay on route, and get everyone home.
