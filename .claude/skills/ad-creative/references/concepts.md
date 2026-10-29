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
2. **c2-live-ride-map** · feature proof
   - `--h1 "Everyone.|*Live.* One map."` · chip: Group split / Alerts when someone drops back (`alert` only for emergencies; use `people`)
   - Headline: See every rider, live
   - Primary: Track your whole convoy in real time. Group split alerts tell you the moment someone drops back, and one tap calls a regroup.
   - Screen: `01d_nav_winding_road_all_four`
3. **c3-emergency-alert** · safety
   - `--h1 "One tap.|*Whole group* alerted."` · `--chip-icon alert` · chip: Emergency / Sent to every rider
   - Headline: Emergency alert for your group
   - Primary: If something goes wrong on a ride, one tap sends an alert to every rider in the group. Don't claim crash detection or emergency-services calls.
   - CTA: Learn more / Install now · Screen: `07_emergency_alert` (keep the banner uncovered: `--chip-dy`)
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
