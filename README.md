# DZ Status - DoubleZero stats on the Solana BP26 badge

A Lua app for the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS). Shows live DoubleZero
network numbers from data.doublezero.xyz: validators on DZ, stake share, users, devices, links,
metros, contributors, capacity and user inbound traffic.

![DoubleZero](art/logo.png)

## Layout

| Path | What |
| --- | --- |
| `app.json` | Manifest: id `dzstat`, permissions `http` + `led`, host `data.doublezero.xyz` |
| `main.lua` | The app. Network tab reads `GET /api/stats` directly (~300 bytes) |
| `art/logo.png` | DoubleZero icon, 16x18 px palette PNG, drawn at 2x in the header |
| `server/badge.ts` | Optional Bun proxy that trims `/api/status` (65 KB) to a badge-sized Status tab |
| `docs/BADGE_KNOWLEDGE.md` | Everything learned about the badge: hardware, Solana OS, Lua API, limits, workflow |
| `docs/DZ_DATA_API.md` | Notes on the data.doublezero.xyz public endpoints |

## Controls

LEFT / RIGHT switch tabs, UP / DOWN scroll, SELECT refresh now, CANCEL exit.
LEDs chase while loading, flash green on success, orange on a bad answer, red when offline.
Last good data is cached in the app's storage and shown when the badge is offline.

## Run it

1. Flash Solana OS 2.4.0 from https://solana.com/breakpoint/badge/stock (USB-C, Chrome/Edge)
2. Sign in at https://solana.com/breakpoint/badge/profile and link X
3. Open https://solana.com/breakpoint/badge/apps/submit, drop `app.json`, `main.lua` and the `art` folder
4. Try in emulator, then Run on badge (Wi-Fi joined on the badge)
5. Publish

## Status tab (optional)

`server/badge.ts` serves `/dz/status.json`. Deploy it over https, set `STATUS_URL` in `main.lua`
and add its host to `hosts` in `app.json`.

## License

MIT for the code in this repo. The DoubleZero logo is a DoubleZero brand asset.
