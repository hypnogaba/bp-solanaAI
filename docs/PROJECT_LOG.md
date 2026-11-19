# DZ Status badge app - project log

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
