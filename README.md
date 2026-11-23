# DZ Map - lay the fiber, light the world (Solana BP26 badge)

A Lua app for the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS 2.x). The world map
(160x74) is cut into **100 land pieces**, all dark. Pick a piece with the d-pad and lay the
fiber: a packet runs along the line, press SELECT while it is in the green and the piece lights
up. Miss, and the packet took the public internet. The more pieces you have, the faster the
packet and the narrower the green. Everything is yours and stays on the badge: **no Wi-Fi needed**.

Mako, the DoubleZero shark, swims in the Pacific, changes colour with your title, and goes
into a feeding frenzy on a streak of five.

## Screens and keys

- **Home**: the puzzle map with a cursor. Dark land = not yet lit, purple = lit, green = lit
  this session. Metros: green square = on a lit piece, grey dot = dark, cyan = your home metro.
  Status: pieces, title, season; the region under the cursor and its metros.
  - d-pad: move the cursor between pieces
  - SELECT: lay fiber on this piece (or start the next season when the map is complete)
  - CANCEL: menu
- **Lay the fiber**: the packet runs from one metro to another. SELECT in the green = the piece
  is lit; dead centre = PERFECT, one extra piece. Miss: SELECT to try again, CANCEL to go back.
- **Menu**: next dark piece, about, links and QR codes (X, website, Discord, source), exit.
  The community line shows how many pieces all badges have laid, when Wi-Fi was on once.

## Perks and bonuses

| Pieces | Title | Also |
| --- | --- | --- |
| 10 | cable layer | Mako turns aqua |
| 25 | metro builder | Mako turns violet |
| 50 | backbone | metro names appear on the map |
| 75 | exchange point | Mako turns green |
| 100 | doublezero | the map glows, season 2 unlocks: faster packets, same world |

- **Daily fiber**: the first piece of the day brings one extra.
- **Home turf**: with Wi-Fi, the worker finds the DoubleZero metro nearest to you; pieces
  around it bring one extra.
- **Metro boost**: the first time you check in within 300 km of a DoubleZero metro, three
  pieces around it light up at once. Travel to another metro, get another boost.
- **Streak of five**: feeding frenzy.

## What the worker does

Plain `http` from a badge goes through the badge server, so a web server never sees the
badge's own IP. `ws` (WebSocket, Solana OS 0.5.1+) goes straight from the badge to our host,
so the Cloudflare Worker sees the badge's public IP and Cloudflare's geolocation of it. On
check-in the app sends its progress; the worker verifies the signed `badge_ticket`, records
progress and metros visited per badge, and answers with the nearest metro, the boost flag and
the community totals. Without `ws` or Wi-Fi the game is unchanged; only the bonuses and the
community line need it.

## Layout

| Path | What |
| --- | --- |
| `app.json` | Manifest: id `dzstat`, permissions `http` + `led`, host `dz-badge.hypnogaba.workers.dev` |
| `main.lua` | The app |
| `data/world.png` | 160x74 land bitmap (Natural Earth 110m), regenerate with `server/make_world.py` |
| `docs/DZ_DATA_API.md` | Notes on data.doublezero.xyz (reference; the app only uses `/api/dz/metros`) |
| `data/metros.json` | Metro codes, names and coordinates (from `/api/dz/metros`) |
| `art/logo.png` | DoubleZero icon, 16x18 px palette PNG, drawn at 2x in the header |
| `worker/worker.ts` | Cloudflare Worker: `wss /checkin` (progress up, bonus + community down), `GET /map`, `POST /admin/season` |
| `worker/wrangler.toml` | Worker config with the `MapState` Durable Object |
| `docs/BADGE_KNOWLEDGE.md` | Everything learned about the badge: hardware, Solana OS, Lua API, limits, workflow |
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
