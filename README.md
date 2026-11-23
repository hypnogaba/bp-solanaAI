# DZ Map - light the world on DoubleZero fiber (Solana BP26 badge)

An arcade run for the Solana Breakpoint 2026 badge (ESP32-C5, Solana OS 2.x). The world map
(160x74) is cut into **13 regions, one for each DoubleZero contributor**, all dark. Pick a
region and splice the fiber: a packet bounces between two metros, sometimes slow, sometimes
fast; press SELECT while it is in the green in the middle. A region takes 3 to 6 splices in a
row, and every region is faster and narrower than the last. **3 lives**: a miss costs one, and
when they are gone the map goes dark and the run starts over. Light all 13 for a full-screen
dance, then the next season is faster still. Plays without Wi-Fi; with Wi-Fi your best score goes
on the **online leaderboard** and you can **share on X** (a QR; the post links a picture card).

The DoubleZero shark swims in the Pacific and changes colour with your title.

## Screens and keys

- **Home**: the map with a cursor around one region. Dark land = not yet lit, purple = lit,
  green = lit this session. Metros: green square = in a lit region, grey dot = dark, cyan = your
  home metro. Status: regions, lives, score, title, season; the region under the cursor and its metros.
  - d-pad: move between regions; SELECT: splice this region (or start the next season); CANCEL: menu
- **Splice**: SELECT with the packet in the green = one splice; dead centre = PERFECT (+50).
  Points for the splices are paid when the region is lit. Miss, or no SELECT for 6 passes: a life.
- **Party** (13/13): a dancer and two sharks. SELECT next season, UP share on X, CANCEL map.
- **Menu**: next dark region, how to play, secrets (hints for the four secrets; all four make the
  shark a rainbow), leaderboard (UP share on X), about, links and QR codes, settings, exit.

## Perks and bonuses

| Regions | Title | Also |
| --- | --- | --- |
| 2 | cable layer | the shark turns aqua |
| 4 | metro builder | the shark turns violet |
| 7 | backbone | metro names appear on the map |
| 10 | exchange point | the shark turns green |
| 13 | doublezero | the dance; next season: faster packets, same world |

Each of these makes a region need one splice less (never under 2):
- **First of the day**: the first region you light each day.
- **Home**: with Wi-Fi the worker finds the DoubleZero metro nearest to you (any distance, e.g.
  Paris -> London, 365 km); its region is home.
- **Metro boost**: the first check-in within 500 km of a DoubleZero metro banks one (up to 3).

Score: 100 per splice (+50 PERFECT), 500 per region, 1000 per life left at 13/13, all x season.

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

Automatic: `.github/workflows/deploy-worker.yml` deploys on every push to `main` that touches
`worker/`, using the `CLOUDFLARE_API_TOKEN` repository secret (Actions secrets). Manual:

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
