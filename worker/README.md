# DZ Map worker

Cloudflare Worker behind the DZ Map badge app. One Durable Object (`MapState`) holds the puzzle:
100 land pieces of the world map, which badge revealed each one and when, how many badges lit
each DoubleZero metro, and each badge's last check-in day.

| Route | What |
| --- | --- |
| `wss /checkin` | Opened by the badge with `ws.open`. Verifies the signed `badge_ticket`, locates the badge by its IP (Cloudflare geo), lights the nearest metro within 300 km, reveals one piece for this badge today, answers with the map state, closes. |
| `GET /map` | The same state over plain http, no check-in. Used by the app as a fallback and usable by a web page. |
| `POST /admin/season?key=<ADMIN_KEY>` | Starts a new season: a fresh, dark puzzle. |

Stored per badge: badge id, user id (both from the ticket), last check-in day, metros lit, piece
count. No names, no IPs, no coordinates.

## Deploy

```
npm install
npx wrangler login                 # once
npx wrangler secret put ADMIN_KEY  # once
npx wrangler deploy
```

Needs a paid Workers plan (Durable Objects). The host name is in `app.json` (`hosts`) and at the
top of `main.lua`.

## Local test

```
npx tsc -p .                                   # typecheck
npx wrangler dev --local --port 8787 --var DEV:1
```

With `DEV=1` (never set in production) `/checkin` accepts `?badge=X&lat=..&lon=..` instead of a
ticket, so a WebSocket client can simulate badges in different cities. `GET /map` shows the result.
