# Feed on Cloudflare Workers (free tier is enough)

```
cd worker
npx wrangler login
npx wrangler deploy
```

Wrangler prints the URL, like `https://dz-badge.<account>.workers.dev`. Check it:
`curl https://dz-badge.<account>.workers.dev/badge.json | wc -c` (about 2 KB).

Then replace `dz-badge.YOUR-ACCOUNT.workers.dev` in `app.json`, `main.lua` and `service.lua`
with that host and re-upload the app.
