# ConvoTrack — Business Requirements Document

**Purpose of this document:** a single, factually-verified source of truth about the ConvoTrack
product, reverse-engineered from the shipping iOS app, the Android port, and the production
backend. It is written to be consumed by a **content-generation agent** producing social media
posts. Everything in §1–§7 is a verified fact about the shipped product. §8–§11 are the rules for
turning those facts into posts. **§10 (Claims Guardrails) is binding — do not market anything it
forbids.**

Document date: 2026-09-05 · Source of truth: `convoy` (iOS), `convotrack-android`, `convoy-backend`

---

## 1. Product Snapshot

| Field | Value |
|---|---|
| Brand name | **ConvoTrack** |
| App Store listing name | Moto Group Ride — ConvoTrack |
| Subtitle | Motorcycle ride tracker & map |
| One-liner | Keeps every rider in a motorcycle group on one live map, in real time. |
| Category | Navigation / Travel — motorcycle group riding |
| Platforms | iOS (SwiftUI) and Android (Jetpack Compose), at feature parity |
| Current version | 1.1.2 — iOS build 5, Android versionCode 6 |
| Website | https://convotrack.in |
| Privacy / Terms | https://convotrack.in/privacy · https://convotrack.in/terms |
| Business model | Free tier + **ConvoTrack Pro** auto-renewable subscription (monthly & yearly) |
| Developer | danglingmind |

**Technical shape (for credibility posts, not for consumer copy):** Fastify + Socket.IO + PostgreSQL
backend on `api.convotrack.in`; Google Maps, Directions, Places and Static Maps for mapping;
Clerk for authentication (Sign in with Google, Sign in with Apple); StoreKit 2 on iOS and Play
Billing on Android with server-side purchase verification.

---

## 2. The Problem

Group motorcycle rides fall apart in predictable ways, and every one of them is a content hook:

1. **The junction split.** The leader clears a light or takes an exit; the tail doesn't. The group is
   now two groups and neither knows it.
2. **The guessing game.** Riders behind can't see which way the leader went, and there is no safe
   way to ask at 80 km/h.
3. **The pull-over tax.** The only fix is stopping, taking gloves off, unlocking a phone, and
   calling around — repeatedly.
4. **The "where's Raj?" problem.** Nobody knows whether the last rider is 200 m back or 20 km back,
   or whether they're fine.
5. **No shared record.** After the ride, everyone has a different story about how far it was and how
   long it took.

Existing tools solve one piece each: navigation apps route one rider, location-sharing apps show
dots without a route, and group chats require stopping to use. Nothing coordinates a *pack in
motion*.

## 3. Positioning

> **ConvoTrack is group-riding infrastructure, not a navigation app with sharing bolted on.**
> The unit of the product is the group, not the rider. Every screen answers "where is everyone,
> and are we still together?" before it answers "where do I turn?"

**Positioning statement:** For motorcycle riders who ride in groups, ConvoTrack is a live group
navigation app that keeps the whole pack on one map with turn-by-turn routing, one-tap regroup calls
and emergency alerts — so the group arrives together instead of arriving in pieces.

**Tagline in the app:** *"Ride together in real time."*
**Pro tagline:** *"Your rides. No limits."*

## 4. Audience

| Segment | Who they are | What lands with them |
|---|---|---|
| **Ride leaders / club organisers** (primary) | Run 5–25 rider group rides, breakfast runs, club Sunday rides | Control: they start, pause, edit, end the ride; they call regroups; they see the whole pack |
| **Pack riders** (primary) | The other 4–24 people on the ride | Not getting dropped; knowing how far back they are; not having to guess the route |
| **Touring / long-distance groups** | Multi-hour highway and mountain rides | Split detection, regroup at fuel/food stops, ride summary + history |
| **Weekend crews & new groups** | Informal friend groups, 3–6 bikes | Join in seconds by code/QR/link; nearby ride discovery |
| **Riders who post** | Anyone who shares the ride afterwards | Shareable summary card with route map, distance, and earned ride titles |

---

## 5. Verified Feature Inventory

Each feature below exists in shipped code. "Post angle" is the hook a content agent should use.

### 5.1 Live group map
- Every rider in the ride renders on one shared map in real time, updated over Socket.IO.
- Each rider pin shows **their name and their live distance from you**.
- Riders who drift outside your viewport become **edge indicators** pinned to the screen border;
  several distant riders collapse into a **cluster chip**. Tapping one jumps the map to that rider.
- Tapping a rider opens a detail drawer.
- Live leaderboard card shows running order, each rider's rank, and position changes.
- **Post angle:** "You never have to wonder who's behind you." The off-screen edge markers are the
  single most demo-able, most screenshot-able feature in the app.

### 5.2 Turn-by-turn navigation
- Full route guidance to the destination via Google Directions, with a turn indicator pill, spoken
  voice announcements, and always-on-screen **ETA** and **remaining distance**.
- Multi-stop routes: waypoints can be added when planning the ride, and render as waypoint pins.
- **"OFF ROUTE"** state is surfaced explicitly when a rider leaves the route.
- Dedicated landscape layout with a side panel — built for a bike mount.
- **Post angle:** you don't need a second navigation app running. The group map *is* the nav.

### 5.3 One-tap regroup
- The leader (or any rider) calls a regroup with one of three reasons — **FUEL**, **FOOD**, or
  **SCENIC** — plus a "how far ahead should we meet" distance selector that projects the meeting
  point forward along the route.
- Every rider gets an instant banner ("REGROUP CALLED — head to the fuel stop"), an audible
  two-tone siren, and a colour-coded regroup pin dropped on their map.
- The regroup auto-resolves once riders arrive: "Regroup complete · Everyone arrived."
- **Post angle:** the pull-over tax, deleted. Three taps, whole group knows where and why.

### 5.4 Emergency alert
- A distinct, separate emergency broadcast: one tap pushes the reporter's exact location to every
  rider, with an urgent continuous siren (deliberately different in character from the regroup
  tone), a red banner naming the rider — "*[name]* needs help — head to their location" — and an
  emergency pin on the map.
- Alerts sound through the **silent switch** — this is treated as a safety event, not a
  notification.
- **Post angle:** the feature you hope you never use. Strong for safety-themed and rider-community
  posts. Handle with a serious tone; never jokey.

### 5.5 Automatic split detection
- The backend continuously measures the leader-to-tail gap. When the group stretches past the split
  threshold (5 km by default), a split is broadcast to everyone, and resolved automatically when the
  group closes back up.
- **Post angle:** "The app notices the group has broken before you do."

### 5.6 Joining a ride — three ways, seconds each
- Every ride gets a **6-character invite code** from a safe charset (no 0/O/I/L, so it can be read
  out over comms without confusion).
- Share a link (`convotrack.in/join/CODE`), read out the code, or **scan a QR code**.
- **Post angle:** "Riders are on the map before they have their gloves on."

### 5.7 Nearby ride discovery
- Home screen surfaces public rides starting near you (default 20 km radius), with title, status,
  rider count, and a "FULL" state.
- A preview sheet shows the route before you commit: *"You'll join as a Formation Rider."*
- **Post angle:** for solo riders and new-to-the-area riders — find a group, don't build one.

### 5.8 Ride lifecycle & leader controls
- States: **LOBBY → ACTIVE → PAUSED → COMPLETED.**
- Leader-only: start, pause, resume, end, edit ride details, remove a participant, delete the ride.
  Everyone in the lobby is told immediately if the leader deletes it.
- Any non-leader participant can leave.
- Exiting navigation is distinct from ending the ride: *"Exit closes navigation on your phone — the
  ride keeps running. End Ride stops location sharing for every rider and generates the summary."*
- **Post angle:** the leader actually leads. Real controls, clear consequences.

### 5.9 Earned ride roles
Four titles, assigned from **how the group actually rode** — computed from GPS telemetry at ride
end, not chosen at signup:
- **RIDE LEADER** — led the ride
- **PACE KEEPER** — held the smallest average gap to the leader
- **TRAIL GUARDIAN** — rode sweep at the back
- **FORMATION RIDER** — everyone else who held the pack
- **Post angle:** the highest-engagement social hook in the product. "Which one are you?" polls,
  "tag your group's Trail Guardian", role-reveal carousels.

### 5.10 Ride summary
Computed entirely server-side, so every rider sees the same numbers:
- **Duration** — actual wall-clock time on the road (not the planned ETA)
- **Distance** — actually ridden, from route-snapped progress plus off-route detours
- **Average speed** — based on time actually *moving*, so fuel stops and traffic lights don't drag
  it down; shows "--" rather than a wrong number when the data can't support one
- **Max group split** — the widest gap the group ever opened
- **Compactness score** and per-rider **sync score** (%)
- Total regroups and total emergencies
- **Final order** and **sync ranking** leaderboards
- **Post angle:** honest numbers, not flattering ones. "Your speedo lies to you at every red light —
  ConvoTrack doesn't."

### 5.11 Shareable summary card
- Generates an image card with the route drawn on a map, distance in km, ride title, date, the
  ConvoTrack wordmark, and a **scan-to-download QR code**.
- **Post angle:** this is your built-in UGC engine. Every card a rider shares is an ad with a QR on
  it. Content should actively prompt riders to post theirs.

### 5.12 Ride history & lifetime stats
- Every ride led or joined, filterable, with **lifetime totals: distance, total rides, average
  speed.**
- **Post angle:** year-in-review / season-recap content, milestone posts ("1,000 km with the crew").

### 5.13 Destination hero photos
- Ride lobby and the active-ride card show a real photo of the destination, pulled from Google
  Places with proper attribution.
- **Post angle:** visual polish. Good for "planning the ride is half the ride" content.

### 5.14 Account & profile
- Sign in with **Google** or **Apple** (via Clerk). Editable profile. Self-serve **account deletion**
  that removes all ride history.
- **Post angle:** privacy-respecting by default — for trust-building posts.

---

## 6. Monetization

| | **Free** | **ConvoTrack Pro** |
|---|---|---|
| Rides per month | 10 | **Unlimited** |
| Max riders per ride | 5 | **25** |
| Ride history retention | 30 days | **365 days** |
| Live stats & sync scores | — | **Included** |

- Pro is an **auto-renewable subscription**, offered **monthly and yearly**, with the yearly plan
  badged as best value with a computed savings percentage.
- Purchases are verified **server-side** on both platforms; a purchase stays bound to the account
  that first claimed it.
- In-app upsells are contextual, not nagging: the max-riders stepper on the create-ride screen shows
  *"Pro unlocks bigger packs"* when you hit the free ceiling.
- Pro benefit copy used in-app: **BIGGER PACKS** · **UNLIMITED** · **ANALYTICS** · **365 DAYS**.

**Conversion angle for content:** the free tier is genuinely usable for a small crew (5 riders,
10 rides/month). Pro is for **clubs and organisers** — the person who runs the 15-bike Sunday ride
is the buyer. Target content at them.

---

## 7. Differentiators — the defensible claims

1. **Group-first, not rider-first.** The map is built around who's together, not around one blue dot.
2. **Off-screen rider indicators.** Riders who leave your viewport are still on your screen, at the
   edge, with distance — tappable.
3. **Regroup as a first-class action**, with a reason and a forward-projected meeting point — not a
   dropped pin in a chat.
4. **Emergency as a separate, louder channel** than regroup, audible through silent mode.
5. **Server-computed, identical summaries.** No two riders argue about the distance.
6. **Honest metrics.** Moving-time average speed; "--" instead of a fabricated number; the widest
   split the group *ever* hit, not the gap at the finish line.
7. **Telemetry-earned roles**, not self-declared badges.
8. **Seconds-to-join.** 6-character human-readable code, link, or QR.
9. **True cross-platform parity.** iOS and Android riders sit in the same pack on the same map.

---

## 8. Brand, Voice & Visual Identity

### Visual system (verified from the app's theme)
- **Dark-only interface.** Surfaces run from `#131313` up through a grey scale to `#353535`.
- **Signature accent: lime green `#caf300`.** This is the brand colour — every primary action, glow
  and highlight. Dark text `#171e00` sits on top of it.
- **Secondary accent:** bright green `#62ff96`, used sparingly for success/status.
- **Alert colours:** error `#ffb4ab` on deep red `#93000a`; regroup pins are amber (fuel), sky blue
  (scenic).
- **Typography:** heavy, condensed, wide-tracked all-caps labels; **monospaced type for all live
  telemetry and data** — the HUD/instrument-cluster look is core to the identity.
- **Motifs:** map polylines in lime, rider pins with lime rings, floating stat pills, glassy dark
  cards, subtle lime glows.

**Directive for visual assets:** every graphic should look like it belongs on a bike's instrument
cluster at dusk. Dark ground, lime accent, monospaced numbers, real map geometry. Never light-mode,
never pastel, never stock-photo-with-a-quote.

### Voice
| Do | Don't |
|---|---|
| Short, declarative, rider-to-rider | Corporate SaaS phrasing |
| Concrete ("the widest gap the group opened") | Vague ("powerful analytics") |
| Problem-first, then the fix | Feature-list dumps |
| Confident and dry | Hype, exclamation stacks, emoji spam |
| Safety talk in a serious register | Jokes about crashes or emergencies |
| Second person — "your group", "your pack" | Third-person "users" |

**Reference sentence, in-voice:** *"Ride as a pack, not as a scattered line of headlights."*

### Vocabulary
**Use:** pack, crew, group, ride, ride leader, sweep, regroup, drop / getting dropped, junction,
formation, convoy, pillion, breakfast run.
**Avoid:** "users", "onboarding", "engagement", "seamless", "revolutionary", "game-changing",
"solution", "leverage".
**Spelling:** the brand is **ConvoTrack** — one word, capital C, capital T. Never "Convo Track",
"Convotrack", or "Convoy" (that's only an internal repo name).

---

## 9. Content Pillars & Post Formats

Six pillars. Rotate; don't run two of the same type back to back.

1. **Pain-point relatable** *(highest reach)* — the junction split, the pull-over tax, "where's the
   last guy". One scenario, one line of setup, one line of fix.
2. **Feature-in-action** — a single feature, shown, not described. Off-screen edge markers, the
   regroup banner, the emergency alert, the live map. Screen recording > screenshot > text.
3. **Ride-role engagement** — "Ride Leader, Pace Keeper, Trail Guardian, Formation Rider — which one
   are you?" Polls, tag-a-friend, role explainers. Best comment-driver in the set.
4. **Summary / UGC amplification** — real (or realistic) summary cards. Prompt riders to share their
   own. Reshare with credit.
5. **Community & safety** — group riding etiquette, sweep-rider responsibilities, pre-ride briefs,
   how to run a regroup properly. Product mentioned lightly or not at all.
6. **Product & build updates** — new versions, what shipped, the reasoning behind a design decision.
   Good for founder/dev-audience channels; keep it a minority of the calendar.

### Post skeletons
- **Pain → fix:** `[The moment it goes wrong]. [What ConvoTrack does instead]. [CTA]`
- **Feature demo:** `[Screen recording]` + one caption line naming the benefit, not the feature.
- **Role poll:** `Four riders. Four jobs. Which are you? [role list] — ConvoTrack assigns these from how you actually rode.`
- **Numbers post:** a real summary stat block in monospaced type on dark ground, one line of context.
- **Leader-targeted (Pro):** `[Organising problem at 15+ bikes] → [Pro capability] → [CTA]`

### Standard CTAs
- "Get ConvoTrack — free for your next ride."
- "Start a ride, share the code, everyone's on the map."
- "convotrack.in"
- Soft/community CTA: "Tag the rider who always sweeps."

---

## 10. Claims Guardrails — BINDING

### ✅ Approved claims (all verified in shipped code)
- Live real-time map of every rider in the group, with per-rider distance
- Off-screen riders shown as tappable edge markers
- Turn-by-turn navigation with voice guidance, ETA and remaining distance
- Multi-stop route planning
- One-tap regroup with fuel / food / scenic reasons and a distance-ahead meeting point
- Emergency alert broadcasting exact location, audible through silent mode
- Automatic group-split detection
- 6-character invite code, shareable link, and QR join
- Nearby ride discovery
- Four telemetry-earned ride roles
- Server-computed ride summary: real duration, real distance, moving-average speed, max group split,
  sync scores, regroup and emergency counts
- Shareable ride summary card
- Ride history with lifetime distance / ride count / average speed
- Free tier: 10 rides per month, 5 riders per ride, 30-day history
- Pro: unlimited rides, up to 25 riders, 365-day history, live stats and sync scores
- Available on iOS and Android at feature parity
- Sign in with Google or Apple; self-serve account deletion

### ❌ Forbidden claims — these are false or unshipped
- **Push-to-talk, voice chat, or any audio comms.** Permanently out of scope. Never imply it.
- **Ride replay / route playback.** The capability flag is off for *both* plans. Not shipped.
- **In-app group chat or messaging.** Doesn't exist.
- **"Available in 50 languages" or any in-app localisation claim.** App Store *listing* metadata is
  localised into 50 locales; the **app interface itself is English-only.** Marketing the app as
  multilingual would be a false claim.
- **Offline / no-signal operation.** Everything realtime requires connectivity.
- **Any safety guarantee.** Never say ConvoTrack prevents accidents, guarantees help arrives, or
  makes riding safe. It broadcasts a location. That is the entire claim.
- **Specific rider counts, download numbers, ratings, or testimonials.** No verified figures exist.
  Do not invent social proof.
- **Named partnerships, clubs, brands, or endorsements.** None exist.
- **Specific subscription prices.** Prices are set per-storefront by App Store / Play Store; never
  state a number. Say "monthly or yearly" and let the store show the price.
- **"Invite links open instantly in the app" as a universal promise.** Universal-link auto-open
  depends on per-store configuration that is not confirmed live everywhere; links always work, but
  don't promise the jump-into-app behaviour.
- **Competitor comparisons by name.** Describe the gap in the category, never a named rival.

### Tone guardrails
- Never joke about crashes, injuries, or the emergency feature.
- Never encourage speeding, racing, or riding without gear; if riding conduct comes up, the default
  posture is pro-safety.
- Never imply riders should interact with the phone while moving — the product's own design premise
  is that you *don't* have to.

---

## 11. Quick Reference for the Content Agent

**Elevator line:** ConvoTrack keeps every rider in your group on one live map — so nobody gets
dropped at a junction and nobody has to pull over to ask where everyone went.

**Three strongest hooks, ranked:** (1) off-screen rider edge markers, (2) the four earned ride
roles, (3) one-tap regroup with a reason.

**Hero colour:** `#caf300` on `#131313`. **Hero motif:** dark map, lime route line, monospaced
numbers.

**Never say:** push-to-talk · replay · chat · "50 languages" · a price · a rider count · a safety
guarantee.

**Always spell:** ConvoTrack.

**Links:** https://convotrack.in · privacy `/privacy` · terms `/terms` · invite links
`convotrack.in/join/CODE`
