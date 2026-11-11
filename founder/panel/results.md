# ConvoTrack App Store listing: quick buyer panel (20 simulated buyers)

Date: 2026-11-11 · Method: founder-consumer `--quick` (20 buyers), all 20 simulated by the moderator in one pass (no sub-agents) at the user's request. Personas were hand-built to hit the requested quotas, not dealt by `panel.py`. Inputs: `founder/customer.json`, `founder/pitch.md`.

> **Honest limits.** These are simulated buyers, not real people. The panel is useful for finding objections, wording and segment differences. It is bad at predicting real conversion, and language models lean agreeable, so read tap and install rates as an upper bound. With 5 buyers per Western market, a 1-buyer swing is 20 points: treat every per-market difference as directional only. Do not quote these lines as testimonials.

## What the panel saw

| Element | en-GB (UK, and India if the phone is in English) | en-US | hi (Hindi-UI India) |
|---|---|---|---|
| Name | Group Ride Track - ConvoTrack | Moto Group Ride — ConvoTrack | बाइक ग्रुप राइड — कॉन्वोट्रैक |
| Subtitle | Motorbike ride tracker & map | Motorcycle ride tracker & map | ग्रुप राइड ट्रैकर और लाइव मैप |
| Promo text | "Spoken turn-by-turn directions, a Live Activity on your Lock Screen, and a fresh new look. See every regroup and emergency at once." | same | Hindi equivalent |
| Description, first lines | "Ride as a pack, not as a scattered line of headlights … nobody gets dropped at a junction …" | same | Hindi equivalent |

**Screenshot captions: not found.** `fastlane/screenshots/` is empty and there's no caption source in `design/screenshots/`. The only first-screen art with text is `design/app-store-header/header.html` and its video spec: "Group ride tracking / Never lose the pack. / Real-time group tracking for motorcycle rides.", the callouts "Whole group: Everyone live on one map" and "Live gap: Distance to every rider", and the video beats "Every rider, live on one map / See the gap to every rider / Regroup in one tap / Never lose the pack." The panel saw this as a stand-in for the first screenshot. If the live screenshots carry different headings, the message tally below may not match what buyers actually see.

**Assumption:** I assumed India's storefront shows the en-GB metadata to English-UI phones. That needs checking against Apple's storefront-language table.

Price shown: free download, 3-day free trial, then an auto-renewing Pro subscription. The StoreKit test config has 4.99/month and 39.99/year. Live territory prices were not checked.

## The 20 buyers

L = leader/organiser, M = member. IC = owns an intercom. WA = uses WhatsApp live location today.

| # | Buyer | Market · role | Exact search query | Taps? | Installs? | Top objection (their words) | What would flip a no |
|---|---|---|---|---|---|---|---|
| I1 | Karthik, 34, RE weekend club (40 riders), Bengaluru, WA | IN · L | `group ride app` | Yes | **Yes** (trial on Sunday ride) | "Half my club is on Android. The page never says they can join." | One line saying riders on any phone can join |
| I2 | Sneha, 27, KTM Duke group, Pune, IC | IN · M | `bike group tracking` | Yes | No (waits for invite) | "I'll install when the admin drops the link in the group." | Leader sends the invite |
| I3 | Rohit, 41, Himalayan touring leader, Delhi (Ladakh/Spiti) | IN · L | `bike ride tracker offline` | Yes | No | "After Upshi there's no network. Does any of this work with zero signal?" | A clear answer on low or no signal: last-known position, catch-up when back online |
| I4 | Aman, 23, Classic 350, college group, Delhi, WA | IN · M | `bike riding app` | Yes | **Yes** | "Free for 3 days, then how many rupees? It doesn't say." | Price in ₹ upfront, student-friendly yearly plan |
| I5 | Vikram, 52, Interceptor, club member, Bengaluru | IN · M | `motorcycle group ride app` | No | No | "'Ride tracker and map' sounds like another Strava. I have Google Maps." | A subtitle that says it's live group location, not ride logging |
| I6 | Pooja, 31, co-organiser, women's riding group, Bengaluru, WA | IN · L | `live location sharing group` | Yes | **Yes** (emergency) | "If a rider goes down she can't tap anything. Is there crash detection?" | Automatic alert, or at least "anyone can raise the alert for another rider" |
| I7 | Faizan, 29, plans one Goa trip a year with friends, Mumbai, WA | IN · L | `group trip location sharing` | No | No | "We ride together once a year. WhatsApp live location is free." | A one-trip pass, or a trial long enough to cover the trip |
| I8 | Harish, 45, Bullet club member, Delhi NCR, Hindi UI, WA | IN · M | `bike group ride` | Yes | No | "Will every member have to buy this? Then nobody will." | "Members join free" (only if that's true) |
| I9 | Nikhil, 36, KTM 390 Adventure, leads 8 riders, Pune, IC | IN · L | `convoy app` | Yes | No | "Cardo plus Maps location sharing already covers us." | Show the thing an intercom can't do: the gap to each rider, regroup pin on the map |
| I10 | Divya, 25, new rider and pillion, Bengaluru, WA | IN · M | `bike ride tracker` | Yes | No (waits for leader) | "Live GPS for six hours will kill my battery." | Battery figure for a typical ride |
| U1 | Graham, 58, BMW GS, runs monthly club rideouts, Yorkshire, IC | UK · L | `motorcycle group ride app` | Yes | **Yes** | "Three-day trial is useless. I ride Sundays. It'll want paying before the next rideout." | A trial that covers the first ride (or 7+ days) |
| U2 | Dave, 47, admin of a Facebook bike-meet group, Essex | UK · L | `bike meet app` | No | No | "'Group Ride Track' reads oddly, and 'tracker & map' sounds like a sat-nav. What's it got that Calimoto hasn't?" | Name and subtitle that say rideout or group, with one clear difference |
| U3 | Sian, 34, sport tourer, Cardiff, WA | UK · M | `share location motorbike group` | Yes | No (waits for group) | "Only works if everyone's on it, so it's not my call." | Group adopts it; a joining link that works straight from WhatsApp |
| U4 | Pete, 63, Gold Wing, advanced riders' group, Norfolk, IC | UK · M | `motorcycle group riding` | Yes | No | "We use the second-man drop-off. I'm not looking at a phone on the bike." | Proof it's spoken and hands-off; framed as a backup to drop-off, not a replacement |
| U5 | Josh, 26, sportsbike, rides with mates, Manchester | UK · M | `motorbike tracker` | Yes | **Yes** (summary card, fun) | "Searched 'tracker' and got anti-theft boxes first. Nearly scrolled past." | (installed) |
| A1 | Rick, 55, road captain at a Harley dealer chapter, Texas, IC | US · L | `group ride app` | Yes | No | "25 riders? Our chapter rolls out 40 bikes on a good Saturday." | Higher cap or a chapter plan |
| A2 | Maria, 39, ADV group sweep rider, Colorado | US · M | `motorcycle group tracking offline` | No | No | "No cell out where we ride. My inReach already does this." | Real offline behaviour stated plainly |
| A3 | Tyler, 29, sport touring with friends, California, IC | US · M | `motorcycle ride with friends app` | Yes | **Yes** | "Fine for me, but if my buddies have to pay $5 a month just to join, they won't." | Joiners free, or a leader-pays plan |
| A4 | Bob, 61, retired touring rider, club member, Ohio | US · M | `motorcycle gps` | No | No | "I want a GPS. This looks like a social thing." | (not the target; a GPS seeker) |
| A5 | Jen, 44, organises charity rides (50+ bikes), North Carolina | US · L | `motorcycle group ride organizer` | Yes | No | "25-rider cap, and I'd need 50 strangers to install an app the morning of." | Cap of 50+, join with no account until ride start |

## Tally

**Overall: 15/20 tap (75%) · 6/20 install (30%) · 3 more say "only when my leader invites me".** Of the 15 who tapped, 6 installed (40%).

| Segment | n | Tap | Install | Install if invited |
|---|---|---|---|---|
| India | 10 | 8 (80%) | 3 (30%) | 2 |
| UK | 5 | 4 (80%) | 2 (40%) | 1 |
| US | 5 | 3 (60%) | 1 (20%) | 0 |
| Leaders / organisers | 9 | 7 (78%) | 3 (33%) | – |
| Members | 11 | 8 (73%) | 3 (27%) | 3 |
| Intercom owners | 6 | 5 (83%) | 2 (33%) | – |
| No intercom | 14 | 10 (71%) | 4 (29%) | – |
| WhatsApp live-location users | 7 | 6 (86%) | 3 (43%) | – |

What this says (directionally):
- **The search result works.** "Group ride" in the name catches the most common queries in all three markets. Taps are lost to subtitle confusion: "tracker & map" read as a ride logger (I5), a sat-nav (U2, A4) or an anti-theft tracker (U5, UK).
- **The page loses buyers on questions it doesn't answer.** Do my mates pay? Do Android riders work? What happens with no signal? Will the trial cover my first ride? None of these is about the product being bad.
- **Members don't buy from the listing.** They install from the leader's link. The listing's real buyer is the leader, and for leaders the deciders are the cap (US), the trial length (UK) and the members-pay question (India).
- **US is weakest.** Big groups hit the 25-rider cap, and ADV riders expect offline.
- **WhatsApp live-location users tap and install most.** The pitch reads as "WhatsApp location, but built for riding", and it lands best with them.

## Top 5 objections (primary plus mentions, in their words)

1. **"Everyone has to install it, and do they have to pay?"** (I2, I8, U3, A3, A5; also mentioned by I1, I10). "Will every member have to buy this? Then nobody will."
2. **"What I use now already does this"**: WhatsApp, intercom, the drop-off system (I7, I9, U4, I5). "Cardo plus Maps location sharing already covers us."
3. **"Not clear what it is: tracker, sat-nav or logger"** (I5, U2, A4, U5). "'Ride tracker and map' sounds like another Strava."
4. **"No signal where we ride"** (I3, A2; also mentioned by I6 for Ladakh). "After Upshi there's no network."
5. **"Trial and price don't fit how I ride"**, plus the cap (U1, I4, I7; cap: A1, A5). "Three-day trial is useless. I ride Sundays." / "25 riders? Our chapter rolls out 40 bikes."

Single mentions: Android not stated (I1), an emergency alert that needs a tap (I6), battery (I10), the clumsy en-GB name "Group Ride Track" (U2).

## Search queries, ranked by frequency per market

**India (10).** "bike" is the word. Only one buyer typed "motorcycle" and none typed "motorbike".
1. "bike … group/ride/tracker" family (5): `bike group tracking`, `bike ride tracker offline`, `bike riding app`, `bike group ride`, `bike ride tracker`
2. "group ride app" family (2): `group ride app`, `motorcycle group ride app`
3. location-sharing family (2): `live location sharing group`, `group trip location sharing`
4. `convoy app` (1)

**UK (5).**
1. "motorcycle group ride/riding" (2): `motorcycle group ride app`, `motorcycle group riding`
2. `bike meet app` (1) · `share location motorbike group` (1) · `motorbike tracker` (1), which returns anti-theft trackers first

**US (5).**
1. `group ride app` / `motorcycle group ride organizer` (2)
2. `motorcycle ride with friends app` (1) · `motorcycle group tracking offline` (1) · `motorcycle gps` (1)

Across all 20, 7 queries contain "group ride/riding". The names already carry it, so keep it.

## Which first-screen messages land

Count of the 20 buyers who named the message as a reason to keep going (negative reactions in brackets).

| Message | Lands with | Notes |
|---|---|---|
| Pack / nobody dropped at a junction ("Never lose the pack") | **11** | Strongest in every market. UK riders read "dropped" through the drop-off system, so it resonates. |
| Regroup in one tap | 6 | Strong in India, where "regroup point" is everyday club vocabulary, and with UK and US leaders. I9: the one thing his intercom can't do. |
| Emergency alert | 6 | Ladakh/Spiti, the women's group, older riders. Objection: you can't tap when you're down. |
| Invite code / join in seconds | 4 | Leaders only (I1, U1, A5, I7). Members don't care. |
| Ride summary card | 4 | Under-30s (I2, I4, U5, A3) who want to share it. |
| Ride roles | 2 (3 negative) | Younger Indian riders like it. Older UK and US riders, and I5, call it a gimmick. |
| Promo text: turn-by-turn, Live Activity, "fresh new look" | 0 (3 negative) | "Maps does turn-by-turn." "Fresh new look" means nothing to a first-time visitor. This is the most visible text on the page and it's spent on update notes. |

## Three alternate subtitle and first-line angles

Each buyer re-judged the search result with the subtitle swapped (name unchanged), plus the matching first line of the promo text.

- **A, the outcome:** subtitle "Never lose a rider again" (24). Promo text: "Every rider on one live map, so nobody gets dropped at a junction."
- **B, plain function:** subtitle "Whole group, live on one map" (28). Promo text: "Live location built for group rides: see the gap to every rider."
- **C, the club rituals:** subtitle "Regroup & SOS for bike groups" (29) in IN; "Regroup & SOS for rideouts" (26) in UK; "Regroup & SOS for group rides" (29) in US. Promo text: "Call a regroup or an emergency and every rider gets the spot instantly."

| Market | Current tap | A | B | C | Winner |
|---|---|---|---|---|---|
| India (10) | 8 | 8 | 9 | 9 (installs 3→5) | **C**: "regroup" and "SOS" are native club words, and C also lifts installs (I3, I8). B is the runner-up. |
| UK (5) | 4 | 4 | 4 | 5 | **C**: "rideout" is the UK word, and U2 taps for it. |
| US (5) | 3 | 4 | 4 | 3 | **A**: road captains and organisers care about not losing riders. A ties B on taps but gets 2 installs to B's 1. |

All of these differences are 1–2 simulated buyers. Test the winners with Product Page Optimization (screenshots and promo text) and the next metadata version (subtitle) before trusting them.

## What to change before spending money

1. **Subtitle:** drop "tracker & map". Use C in GB and India, and A in the US. Check the 30-character limit per locale.
2. **Promotional text:** replace the update notes with answers to objection #1: who pays, and how riders join. Only write what's true. Under the current access rules, a joiner whose trial has expired can't join, so "members join free" can't be claimed today. That's a product and pricing decision first (→ `/founder-offer`, `/founder-pricing`).
3. **Description:** add one line each on low signal, battery, and the 25-rider cap or a bigger tier. Riders on Android phones can join, but Apple's metadata rules restrict naming other platforms, so check the wording against App Review guidelines before adding it.
4. **en-GB name:** "Group Ride Track - ConvoTrack" read as clumsy to one buyer, and it's the only locale with a hyphen instead of an em dash.
5. **Trial:** 3 days misses the weekend rider. U1 and I7 would have tried it if the trial covered one ride.

Confirm with real riders (a handful of club leaders in each market, or a PPO test) before acting on any of the rates above.
