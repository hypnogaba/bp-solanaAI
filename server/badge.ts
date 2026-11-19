// Feed for the DZ Status badge app. Run: bun run badge.ts  (PORT=8787)
// Put it behind https (Caddy / nginx / Cloudflare tunnel) and point FEED_URL in main.lua
// and `hosts` in app.json at that host.
//
// Why a proxy: the badge takes at most ~3.5 KB per answer; data.doublezero.xyz's
// /api/status is ~65 KB and /api/dz/links ~150 KB. This squeezes both into ~2.5 KB:
//
// {
//   status: "healthy" | "degraded" | ...,
//   stats: { validators_on_dz, total_stake_sol, stake_share_pct, users, devices, links,
//            contributors, metros, bandwidth_bps, user_inbound_bps },
//   links: { total, healthy, degraded, down },
//   pairs: [ [metroA, metroB, gbps, drainedCount], ... ],   // WAN routes, metro to metro
//   top:   [ { code, route, util }, ... ],                  // 5 most loaded links
//   issues:[ { code, issue, route }, ... ],                 // up to 6 current issues
//   at: unix seconds
// }

const DZ = 'https://data.doublezero.xyz';
const TTL_MS = 30_000;
const MAX_BYTES = 3000;
let cache: { at: number; body: string } | null = null;

type Pair = { a: string; b: string; g: number; bad: number };

async function build() {
  const [stats, status, links] = await Promise.all([
    fetch(`${DZ}/api/stats`).then((r) => r.json()),
    fetch(`${DZ}/api/status`).then((r) => r.json()),
    fetch(`${DZ}/api/dz/links?limit=500`).then((r) => r.json()),
  ]);

  const pairs = new Map<string, Pair>();
  for (const l of links.items ?? []) {
    if (l.link_type !== 'WAN') continue;
    const a = l.side_a_metro, b = l.side_z_metro;
    if (!a || !b || a === b) continue;
    const k = [a, b].sort().join('-');
    const p = pairs.get(k) ?? { a, b, g: 0, bad: 0 };
    p.g += (l.bandwidth_bps ?? 0) / 1e9;
    if (l.status !== 'activated') p.bad++;
    pairs.set(k, p);
  }

  const route = (x: any) => `${x.side_a_metro} - ${x.side_z_metro} · ${x.link_type}`;
  const top = (status.links?.top_util_links ?? [])
    .slice()
    .sort((x: any, y: any) => Math.max(y.utilization_in, y.utilization_out) - Math.max(x.utilization_in, x.utilization_out))
    .slice(0, 5)
    .map((x: any) => ({ code: x.code, route: route(x), util: Math.round(Math.max(x.utilization_in, x.utilization_out)) }));

  const issues = (status.links?.issues ?? []).slice(0, 6).map((i: any) => ({
    code: i.code,
    issue: String(i.issue ?? '').replace('packet_loss', 'loss').replace('missing_adjacency', 'isis'),
    route: route(i),
  }));

  const s = stats;
  const out = {
    status: status.status,
    stats: {
      validators_on_dz: s.validators_on_dz, total_stake_sol: Math.round(s.total_stake_sol),
      stake_share_pct: +(+s.stake_share_pct).toFixed(2), users: s.users, devices: s.devices,
      links: s.links, contributors: s.contributors, metros: s.metros,
      bandwidth_bps: s.bandwidth_bps, user_inbound_bps: Math.round(s.user_inbound_bps),
    },
    links: { total: status.links?.total, healthy: status.links?.healthy, degraded: status.links?.degraded, down: status.links?.down },
    pairs: [...pairs.values()].map((p) => [p.a, p.b, Math.round(p.g), p.bad]),
    top,
    issues,
    at: Math.floor(Date.now() / 1000),
  };

  let body = JSON.stringify(out);
  while (body.length > MAX_BYTES && (out.issues.length || out.top.length)) {
    if (out.issues.length) out.issues.pop(); else out.top.pop();
    body = JSON.stringify(out);
  }
  return body;
}

Bun.serve({
  port: Number(process.env.PORT ?? 8787),
  async fetch(req) {
    if (new URL(req.url).pathname !== '/badge.json') return new Response('not found', { status: 404 });
    try {
      if (!cache || Date.now() - cache.at > TTL_MS) cache = { at: Date.now(), body: await build() };
    } catch (e) {
      if (!cache) return new Response(JSON.stringify({ error: String(e) }), { status: 502 });
    }
    return new Response(cache.body, { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
  },
});
console.log('badge.json on :' + (process.env.PORT ?? 8787));
