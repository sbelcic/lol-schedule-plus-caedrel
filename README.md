# lolesports-schedule

Chrome extension popup widget for League of Legends esports match schedules. View upcoming matches from **LCK, LEC, MSI, Worlds, and the Esports World Cup** in one unified schedule, plus an optional toolbar LIVE badge for Twitch streamer **caedrel**.

## Features

- Unified schedule for:
  - LCK (League of Legends Champions Korea)
  - LEC (League of Legends EMEA Championship)
  - Mid-Season Invitational (MSI)
  - World Championship (Worlds)
  - Esports World Cup (EWC)
- Matches grouped into:
  - Live
  - Later Today
  - Tomorrow
  - Upcoming days
- Team logos and team codes
- Best-of (Bo3/Bo5/etc.) display
- Tournament stage/week labels
- Completed match scores
- League badge (LCK, LEC, MSI, Worlds, EWC) on every match
- Toolbar LIVE badge when **caedrel** is streaming on Twitch (optional, configurable in Settings)
- **caedrel** button in popup → opens https://www.twitch.tv/caedrel
- Live match cards are clickable → opens https://www.twitch.tv/caedrel
- Background service worker polls Twitch GQL every 2 minutes while the LIVE badge is enabled
- Match times automatically displayed in the user's local timezone

## Install (Unpacked)

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select this extension folder
5. Pin the extension to the Chrome toolbar
6. Click the extension icon
7. Open **Settings (⚙)**
8. Enable **Notify caedrel live** if you want the LIVE toolbar badge

## Files

```
manifest.json    Manifest V3
popup.html       Popup UI
popup.js         Fetches and renders LoL Esports schedules
background.js    Service worker, alarms, Twitch LIVE polling
icons/           16/32/48/128 PNG icons
```

## Data Sources

### LoL Esports Schedule

Schedules are retrieved from Riot's public LoL Esports API endpoint:

https://esports-api.lolesports.com/persisted/gw/getSchedule

using the same public `x-api-key` bundled with the official lolesports.com website.

Supported leagues:

- LCK
- LEC
- Mid-Season Invitational (MSI)
- World Championship (Worlds)
- Esports World Cup (EWC)

### Twitch Live Status

Live status for **caedrel** is retrieved from Twitch's GraphQL endpoint:

https://gql.twitch.tv/gql

using the same public web `Client-ID` used by twitch.tv.
