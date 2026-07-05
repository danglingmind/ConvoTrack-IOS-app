# vynl.in/motorcade — Landing Page Spec

This page is linked from every ride share QR code generated in the Motorcade app.
It is scanned by passengers, friends, or anyone a rider shares their summary card with.

---

## Purpose

When someone scans the QR code on a ride summary card, they land here. The page has two jobs:

1. **Deep-link existing Motorcade users** directly into the app (via a universal link / app clip).
2. **Convert new users** — show them what Motorcade is and get them to download it.

---

## User Scenarios

| Who lands here | What they expect |
|---|---|
| iPhone user with Motorcade installed | Opens the app directly (universal link) |
| iPhone user without Motorcade | Sees a download prompt → App Store |
| Android / desktop user | Sees a "not available yet" message with an email capture |

---

## Page Sections

### 1. Hero
- App icon + "MOTORCADE" wordmark (match app branding: dark background `#131313`, lime accent `#caf300`)
- One-line tagline: **"Ride together in real time."**
- Primary CTA button: **"Download on the App Store"** → links to App Store listing

### 2. Ride Context Card (optional, shown only when `?rideId=` param is present)
If the QR code is generated with a `rideId` query param (future enhancement), show a brief card:
- "You were invited to a motorcade"
- Ride date, rough distance, number of riders (fetched from backend)
- CTA: "Join in the app" → deep link

For now (no param), skip this section and go straight to the hero CTA.

### 3. Feature Highlights (3 bullets, keep it short)
- Real-time location sharing with your group
- Turn-by-turn navigation that keeps the motorcade together
- One QR code to invite everyone

### 4. Footer
- Links: Privacy Policy (`https://danglingmind.com/privacy`) · Terms (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`)
- "© Motorcade by Danglingmind"

---

## Technical Requirements

### Universal Links
- Host `apple-app-site-association` (AASA) file at `https://vynl.in/.well-known/apple-app-site-association`
- Associate with bundle ID `danglingmind.motorcade`
- Path to handle: `/motorcade*`

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["<TEAM_ID>.danglingmind.motorcade"],
        "components": [
          { "/": "/motorcade*" }
        ]
      }
    ]
  }
}
```

- In Xcode: **Signing & Capabilities → Associated Domains** → add `applinks:vynl.in`

### iOS Behavior
- If app is installed: tapping the link from Messages/Safari opens Motorcade directly
- If not installed: Safari shows the landing page with App Store button

---

## Design Tokens (match the app)
| Token | Value |
|---|---|
| Background | `#131313` |
| Primary accent | `#caf300` |
| Text on accent | `#171e00` |
| Body text | `#e6e6e6` |
| Surface card | `#1e1e1e` |
| Font | System (`-apple-system`, `BlinkMacSystemFont`, `SF Pro`) |

---

## Minimum Viable Version (for App Store submission)
The page just needs to **exist and load** before submission — Apple reviewers check that the QR resolves.

MVP checklist:
- [ ] Page loads at `https://vynl.in/motorcade`
- [ ] Shows app name + tagline
- [ ] App Store download button (can be a placeholder link until app is live)
- [ ] Privacy Policy link works
- [ ] Page is mobile-responsive

Universal links and the ride context card can be added post-launch.
