# DZ Status - DoubleZero stats on the Solana BP26 badge

A Lua app for the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS). Home menu with seven screens:

- **Map**: world map with the 31 DoubleZero metros and the WAN routes between them
  (purple 100G+, darker 10G, red when a link on the route is drained)
- **Network**: validators on DZ, stake share, users, devices, links, metros, contributors, capacity, inbound
- **Links**: overall status, current incidents, the five most loaded links
- **Lookup**: type an IP or pubkey on the d-pad keyboard, see the matching DZ users (metro, device, status)
- **Join**: QR codes for Discord, X, docs, website and the data dashboard
- **Alerts**: a background service (`service.lua`) that checks the feed once a minute and toasts you
  when the network status changes or a new incident appears; keeps running after the app closes and after reboot
- **About**: version and source. There is an easter egg on this screen. You know the code.

A status dot in the header shows the network state (green / orange / red) on every screen.

![DoubleZero](art/logo.png)

## Layout

| Path | What |
| --- | --- |
| `app.json` | Manifest: id `dzstat`, permissions `http` + `led`, host `data.doublezero.xyz` |
| `main.lua` | The app. Reads `FEED_URL` (the proxy), falls back to `data.doublezero.xyz/api/stats` |
| `service.lua` | Background alerts service (permission `background`) |
| `data/sample.json` | A real feed snapshot shown on first run until the live fetch lands |
| `data/world.png` | 160x74 land bitmap (Natural Earth 110m), regenerate with `server/make_world.py` |
| `data/metros.json` | Metro codes, names and coordinates (from `/api/dz/metros`) |
| `art/logo.png` | DoubleZero icon, 16x18 px palette PNG, drawn at 2x in the header |
| `server/badge.ts` | Bun proxy: squeezes `/api/stats`, `/api/status` and `/api/dz/links` into a ~2 KB `badge.json` |
| `server/sample/badge.json` | A real answer from the proxy, for tests |
| `docs/BADGE_KNOWLEDGE.md` | Everything learned about the badge: hardware, Solana OS, Lua API, limits, workflow |
| `docs/DZ_DATA_API.md` | Notes on the data.doublezero.xyz public endpoints |

## Controls

UP / DOWN move, SELECT opens a screen, CANCEL goes back (and exits from the menu). On Join, LEFT / RIGHT flip through the QR codes. SELECT refreshes on data screens.
LEDs chase while loading, flash green on success, orange on a bad answer, red when offline.
Last good data is cached in the app's storage and shown when the badge is offline.

## Run it

1. Flash Solana OS 2.4.0 from https://solana.com/breakpoint/badge/stock (USB-C, Chrome/Edge)
2. Sign in at https://solana.com/breakpoint/badge/profile and link X
3. Open https://solana.com/breakpoint/badge/apps/submit, drop `app.json`, `main.lua` and the `art` folder
4. Try in emulator, then Run on badge (Wi-Fi joined on the badge)
5. Publish

## The feed

The badge accepts at most ~3.5 KB per http answer; the DZ endpoints with link data are 65-150 KB.
`server/badge.ts` (Bun) fetches them every 30 s and serves `/badge.json` (~2 KB) plus
`/lookup?q=` for the Lookup screen. Deploy it behind https, then set `FEED_HOST` in `main.lua`,
`FEED_URL` in `service.lua` and the host in `app.json` (`hosts`). Without the feed the app still
shows the Network screen from the public `/api/stats`, and the map from the bundled snapshot.

## Testing in the emulator without an account

The emulator console accepts the same commands as the badge's serial console. From the page's
devtools, fetch each file, base64 it and send `lua put dzstat <file> begin`, then lines of
`lua put dzstat <file> <128 chars of base64>`, then `lua put dzstat <file> end`; `lua run dzstat`
starts it, `key up|down|left|right|select|back` drives it. Stop the background service first
(`svc stop app:dzstat`) or writes are refused.

## License

MIT for the code in this repo. The DoubleZero logo is a DoubleZero brand asset.
