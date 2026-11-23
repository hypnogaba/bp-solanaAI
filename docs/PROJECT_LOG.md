# DZ Map (ex DZ Status) badge app - project log

For whoever (human or agent) picks this up next. Read README.md first, then this.

## What this is

A Lua app for the Solana Breakpoint 2026 badge (BP26, ESP32-C5, Solana OS 2.4.0) that shows the
DoubleZero network live: world map of metros and routes, stats, link health, validator lookup,
QR codes to the community, background alerts. Built 2026-11-19 by hypnogaba with Claude.

- Code: https://github.com/hypnogaba/bp-solanaAI (public, MIT)
- Local: ~/Projects/doublezero/bp26-badge-dzstat/
- Feed (Cloudflare Worker): https://dz-badge.hypnogaba.workers.dev/badge.json and /lookup?q=
- Data source: https://data.doublezero.xyz (public API, no auth), see docs/DZ_DATA_API.md
- Badge platform: docs/BADGE_KNOWLEDGE.md (hardware, Solana OS, Lua API, limits, workflow)

## Done

1. Studied the badge: hardware, Solana OS, Lua API, limits (3.5 KB http answers, 200k instructions
   per callback, one radio, no secure storage), developer workflow (submit page, emulator, USB)
2. App 0.1-0.3: stats list from data.doublezero.xyz/api/stats (300 bytes, read directly), DZ icon
   (16x18 pixel art sampled from the brand icon on its 16 px grid), LED feedback, offline cache
3. App 0.4: world map (Natural Earth 110m land rasterised to 160x74, shown at 2x), 31 metros from
   /api/dz/metros bundled as data/metros.json, WAN routes from the feed
4. App 0.5: home menu with 7 screens, Lookup (d-pad keyboard + /lookup on the feed), Join (5 QR
   codes), Alerts (service.lua: polls once a minute, service.notify on status change or new
   incident), About with an easter egg (konami code on About -> rickroll QR + LED rainbow)
5. Feed: server/badge.ts (Bun) and worker/worker.ts (Cloudflare Worker, deployed). It squeezes
   /api/stats (300 B) + /api/status (65 KB) + /api/dz/links (150 KB) into ~2 KB
6. Tested every screen on a clean install in the official browser emulator
   (solana.com/breakpoint/badge/emulator) by driving its console: `lua put` in 128-char base64
   lines, `lua run dzstat`, `key up|down|select|back`. Zero Lua errors
7. Removed the personal surname and domain from everything public; feed host uses the handle only

## Left to do

- [ ] Upload dzstat-submit.zip contents on solana.com/breakpoint/badge/apps/submit, Run on badge,
      Publish (store listing text is in the chat of 2026-11-19 and below)
- [ ] Cloudflare API token in worker/.env as `CLOUDFLARE_API_TOKEN=...` so an agent can run
      `npx wrangler deploy` from the sandbox (the first token was pasted without the key name and
      got exposed; revoke it, make a new one). .env is git-ignored
- [ ] Ask Eden (comms) before the tweet, since the app carries the DZ logo in a public store
- [ ] Tweet (skeleton in the chat; Ivan writes the final)
- [ ] Discord link: app uses https://discord.gg/doublezero; change in main.lua LINKS if needed

## Ideas not built yet

- Latest @doublezero posts tab (needs the feed to fetch them)
- Discord member count from the widget API
- mesh "DZ Meet": signed meets between badges, leaderboard for events
- Edge / ShredStream counters from ClickHouse via the feed
- Games: Bomberman clone on mesh (feasible), a runner (heavier); a trading watchlist with Solana Pay
  QR (no signing on the badge)

## Store listing (0.5.0)

Summary: DoubleZero network map, stats, link health, validator lookup and community links.

Description: see README.md sections; permissions explained: http (data.doublezero.xyz and the
feed), led (feedback), background (Alerts only if turned on). P.S. easter egg on About.

## Gotchas learned

- `lua put` is refused while the app's background service runs: `svc stop app:dzstat` first
- Emulator without a claimed account has no http ("not linked"); the app shows the bundled
  data/sample.json snapshot then
- `ui.list` has show(); the map canvas (148 px) does not fit above the footer, so the footer is
  hidden on the map and the note sits over the empty south of the map
- PNG for the badge: palette, not interlaced; the land map is 897 bytes, the icon 264 bytes


## 2026-11-21: pivot to DZ Map 1.0

Why: Juan (DoubleZero engineer) published "DoubleZero Monitor" in the badge store (stats, metro
pair latency, diagnostics). DZ Status 0.5 duplicated that. Decision with Ivan: no network
dashboards, focus on the ordinary badge user, make something unique: a collective puzzle.

What changed:
- main.lua rewritten: home = puzzle map (100 land pieces of world.png on an 8x8 grid), check-in
  over `ws` to the worker (badge IP -> Cloudflare geo -> nearest metro, one piece per badge per
  UTC day), metro browsing, About + QR, Mako the shark (pixel art, swims in the Pacific),
  LED fiber wave. Easter eggs: UP x3 on the map (feeding frenzy), konami on About (rickroll).
- Removed: Network, Links, Lookup, Alerts, service.lua, data/sample.json, `background` permission.
- worker/worker.ts: `MapState` Durable Object (strongly consistent state), `wss /checkin` with
  badge ticket verification (Ed25519, key from solana.com/breakpoint/badge/api/http/key),
  `GET /map`, `POST /admin/season?key=`. Legacy `/badge.json` and `/lookup` kept for 0.5.
- Tested: worker typechecks and ran locally (`wrangler dev --local --var DEV:1`, six simulated
  check-ins over WebSocket: daily limit, metro lighting, no-geo path). main.lua compiles on
  Lua 5.5 and ran in a Python/lupa fake badge (all screens, keys, offline and no-ws paths).
  NOT yet run in the real emulator or on a badge (browser pane was unavailable).

Open:
- [ ] Ivan: deploy the worker (`cd worker && npx wrangler deploy`), set ADMIN_KEY secret
- [ ] Ivan: drop app.json, main.lua, art/, data/ on the submit page, try in emulator, run on badge
- [ ] Verify on the real badge that `ws.open` reaches the worker and the piece lands
- [ ] Store listing text for 1.0 (summary is in app.json)
- [ ] Paris is not a DZ metro (nearest: London 361 km): Ivan cannot light a metro from home
- [ ] Ideas for 1.1: a web page showing the same map (worker `/map`), a "Faster than the
      internet" minigame, the Mako quest/beacon once a QuestMaker role exists

## 2026-11-22: cleanup

- Removed server/badge.ts and server/sample (Bun feed for 0.5), legacy /badge.json and /lookup
  from the worker, rewrote worker/README.md. DZ_DATA_API.md kept as reference only.
- Git history rewritten to drop the author's surname, personal domain and e-mail (public repo
  rule: handle only). Commits are authored as hypnogaba <hypnogaba@users.noreply.github.com>.

## 2026-11-23: DZ Map 1.1 - the puzzle is personal

Ivan's test of 1.0: Wi-Fi did not join, nothing happened, and the "piece nearest to you" rule
means places with no badge holders (Australia) never get revealed. Decision: everyone can
complete the whole map alone, offline, with a timing game per piece; location is a bonus.

- main.lua: cursor on the tile grid, "lay the fiber" timing game (speed and green width scale
  with pieces and season), perks at 10/25/50/75/100 (titles, Mako skins, metro names, season 2),
  daily fiber, home turf, metro boost, streak frenzy. Menu on CANCEL (next piece, about, QR,
  exit); konami on the menu = rickroll. Progress in storage key "g" (100-char string).
- worker: community counters per badge (pieces, season, metros visited) instead of a shared
  puzzle; /checkin waits up to 700 ms for the badge's {n, s} message, then answers with
  you.{near, km, metro, home, boost} and c.{pieces, badges, done, metros}.
- Tested in the lupa fake badge: miss / retry / hit / perfect, boost, perks, 100th piece and
  season rollover, menu, about, QR, konami. Not yet in the real emulator.
- 1.1 also: splash (Mako, 1.6 s), How to play (3 pages on first run, then from the menu),
  Settings (LEDs on/off, reset progress, stats). Worker deploys from GitHub Actions on push to
  main (worker/**) using the CLOUDFLARE_API_TOKEN repo secret: no token in chat or in the sandbox.

## 2026-11-23: DZ Map 1.2 - fixes and secrets

Why: the store had 1.0.1 (needs the worker), and the 1.0/1.1 worker was never deployed: the GitHub
Action failed because the repo has no CLOUDFLARE_API_TOKEN secret, so Cloudflare still ran the
0.5 feed (`/map` and `/checkin` answered 404). 1.1 had only been run in a fake badge; a review
found crash and UX bugs before it reached players.

- Crash fixes: unknown metro code from the worker (boost), `json.decode` in pcall, empty
  metros.json, partial or 1.0.x saves (numbers normalised, old keys "map" and "updated" removed).
- The badge allows 8 timers: all one-shot delays (toasts, perk, season, return to the map,
  splash, LED flash) now run from a job list in `on_tick` (`later(ms, fn)`); one LED wave at a
  time. Peak in the fake badge: 2 timers.
- Exit in the menu calls `sys.exit()` (returning false only exits on "back").
- 0.7 s "get ready" before the packet runs; SELECT during it is ignored.
- Community sync when the piece count crosses a multiple of 10 (extra pieces skipped it);
  8 s watchdog on check-in; offline at start retries every 5 min.
- Round id so a late "back to the map" from the last round cannot end the new one.
- Header subtitle resets on the map; season prompt no longer promises the title stays.
- Secrets menu (hints, then how once found): PERFECT, FEEDING FRENZY, HOME METRO, NEVER GONNA
  (konami on the menu). All four: rainbow Mako. No !LAMPs (no `lamps` permission: adding it
  sends every update to manual review).
- Worker: season counter can rise by at most 1 per check-in (cap 20), metros fetch has a 2 s
  timeout and a 5 min retry after a failure, the socket closes with 1011 if the Durable Object
  call throws.
- Tests: `tools/fake_badge.py` (Lua 5.5 via lupa, enforces 8 timers / 128 UI objects, counts
  VM instructions): 33 checks, worst callback ~52k of 200k.

Open:
- [ ] Deploy the worker: `cd worker && npx wrangler deploy` from the Mac (wrangler is logged in),
      or add the CLOUDFLARE_API_TOKEN repo secret so the Action works
- [ ] Publish 1.2.0 on the submit page (app.json, main.lua, art/, data/), try in emulator, run on badge
