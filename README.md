# lolesports-schedule

Chrome extension popup for League of Legends esports match schedules, with **live notifications for any Twitch streamers you choose**.

## Features

- Unified schedule for LCK, LEC, MSI, Worlds, Esports World Cup, KeSPA Cup, LCS and Demacia Cup
- Matches grouped into Live, Later today, Tomorrow and upcoming days; times shown in your local timezone
- **Choose your leagues** in Settings: the full league list is loaded from Riot's `getLeagues` endpoint (cached 24 h) with search, select/clear and reset. Defaults to the original eight.
- League filter chips, team logos, Bo format, stage/week labels and final scores
- Instant open: the last schedule is cached and refreshed in the background
- **Multiple streamers**: add any Twitch channel by name or URL (`twitch.tv/caedrel`, `@caedrel`, `caedrel`) in Settings (⚙). Up to 15.
- Live streamers appear at the top of the popup with viewer counts
- Toolbar badge: the first 4 letters of the streamer's name (e.g. `CAED`) when one is live, or the number of streamers live. Hover the icon for the full names.
- Optional desktop notification when a tracked streamer goes live (click to open the channel)
- Live match cards open the first live tracked streamer, or lolesports.com if nobody is live
- Dark and light theme (follows your system)

## Install

1. Download this repository as a ZIP and extract it.
2. Open `chrome://extensions/` and enable **Developer mode**.
3. Click **Load unpacked** and select the folder containing `manifest.json`.
4. Click the extension icon, open **Settings (⚙)**, add streamers and enable the badge and/or notifications.

## Files

```
manifest.json   Manifest V3
shared.js       Twitch helpers (channel parsing, batched live lookup)
popup.html/.css/.js   Popup UI
background.js   Service worker: alarm polling at your chosen interval, badge, notifications
icons/          16/32/48/128 PNG icons
```

## Data sources

- Schedules: Riot's public LoL Esports API (`esports-api.lolesports.com`) using the public key bundled with lolesports.com.
- Twitch status: Twitch GraphQL (`gql.twitch.tv`) using the public web Client-ID, one batched request for all streamers.

Polling only runs while the badge or notifications are enabled. The refresh interval (1–15 min, default 3) is set in Settings and applies to both the background live check and the popup's auto-refresh.
