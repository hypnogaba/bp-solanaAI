# DZ Map - light the DoubleZero world map together (Solana BP26 badge)

A Lua app for the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS 2.x). The world map
(160x74) is cut into **100 land pieces**. Every badge with Wi-Fi reveals **one piece per day**,
the dark piece nearest to where the badge is. A badge within 300 km of a DoubleZero metro
lights that metro too. When all 100 pieces are lit, the season is complete.

Mako, the DoubleZero shark, swims in the Pacific and keeps count.

## Screens and keys

- **Home**: the puzzle map. Dark land = not yet revealed, purple = revealed, bright purple =
  your pieces, green = today's piece. Metros: green square = lit, grey dot = dark.
  Two status lines: pieces / metros / badges, and your own line (where you are, your pieces,
  when your next piece unlocks).
  - SELECT: check in (one piece today) / refresh
  - LEFT / RIGHT: browse the 31 metros (highlight on the map, how many badges lit it)
  - DOWN: about
  - CANCEL: exit
- **About**: what DoubleZero is, credits, SELECT for QR codes (X, website, Discord, source).
- Easter eggs: one on the map, one on About. You know the code.

## How the check-in works

Plain `http` from a badge goes through the badge server, so a web server never sees the
badge's own IP. `ws` (WebSocket, Solana OS 0.5.1+) goes straight from the badge to our host,
so the Cloudflare Worker sees the badge's public IP and Cloudflare's geolocation of it
(city, lat/lon). The worker:

1. verifies the signed `badge_ticket` the badge adds to the URL (badge id, user id, Ed25519),
2. finds the nearest DoubleZero metro; within 300 km it lights that metro for this badge,
3. reveals the unrevealed piece nearest to the badge, once per badge per UTC day,
4. answers with the whole map state (~400 bytes) and closes.

Without `ws` (old firmware) or when the socket fails, the app reads the same state over
`GET /map` (no check-in) and keeps showing the last map from storage when offline.
Emulator badges (ids starting with `e`) check in like real ones, so test on the real badge
or expect test pieces on the live map.

## Layout

| Path | What |
| --- | --- |
| `app.json` | Manifest: id `dzstat`, permissions `http` + `led`, host `dz-badge.hypnogaba.workers.dev` |
| `main.lua` | The app |
| `data/world.png` | 160x74 land bitmap (Natural Earth 110m), regenerate with `server/make_world.py` |
| `data/metros.json` | Metro codes, names and coordinates (from `/api/dz/metros`) |
| `art/logo.png` | DoubleZero icon, 16x18 px palette PNG, drawn at 2x in the header |
| `worker/worker.ts` | Cloudflare Worker: `wss /checkin`, `GET /map`, legacy `/badge.json` and `/lookup` |
| `worker/wrangler.toml` | Worker config with the `MapState` Durable Object |
| `docs/BADGE_KNOWLEDGE.md` | Everything learned about the badge: hardware, Solana OS, Lua API, limits, workflow |
| `docs/DZ_DATA_API.md` | Notes on the data.doublezero.xyz public endpoints |
| `docs/PROJECT_LOG.md` | History and open items, for the next agent |

## Deploy the worker

```
cd worker
npm install                      # typescript, wrangler, workers-types (dev only)
npx wrangler login               # once
npx wrangler secret put ADMIN_KEY   # for POST /admin/season (new season = fresh puzzle)
npx wrangler deploy
```

The Durable Object needs a paid Workers plan. `npx tsc -p .` typechecks; `npx wrangler dev
--local --var DEV:1` runs it locally with `?badge=X&lat=..&lon=..` instead of a ticket on
`/checkin` (DEV is never set in production).

## Run the app

1. Flash Solana OS 2.x from https://solana.com/breakpoint/badge/stock (USB-C, Chrome/Edge)
2. Sign in at https://solana.com/breakpoint/badge/profile and link X
3. Open https://solana.com/breakpoint/badge/apps/submit, drop `app.json`, `main.lua`, the
   `art` and `data` folders
4. Try in emulator, then Run on badge (Wi-Fi joined on the badge)

## License

MIT for the code in this repo. The DoubleZero logo is a DoubleZero brand asset.
