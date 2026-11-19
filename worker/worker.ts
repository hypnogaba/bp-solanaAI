// Cloudflare Worker feed for the DZ Status badge app. Same shape as server/badge.ts.
// Deploy: cd worker && npx wrangler deploy   -> https://dz-badge.<account>.workers.dev
// Then put that host in app.json (hosts), main.lua (FEED_HOST) and service.lua (FEED_URL).

const DZ = 'https://data.doublezero.xyz';
const MAX_BYTES = 3000;
const JSON_HEADERS = { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': '*' };

type Pair = { a: string; b: string; g: number; bad: number };

async function build(): Promise<string> {
  const [stats, status, links] = await Promise.all([
    fetch(`${DZ}/api/stats`, { cf: { cacheTtl: 30 } }).then((r) => r.json<any>()),
    fetch(`${DZ}/api/status`, { cf: { cacheTtl: 30 } }).then((r) => r.json<any>()),
    fetch(`${DZ}/api/dz/links?limit=500`, { cf: { cacheTtl: 120 } }).then((r) => r.json<any>()),
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
  const top = (status.links?.top_util_links ?? []).slice()
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
    top, issues,
    at: Math.floor(Date.now() / 1000),
  };
  let body = JSON.stringify(out);
  while (body.length > MAX_BYTES && (out.issues.length || out.top.length)) {
    if (out.issues.length) out.issues.pop(); else out.top.pop();
    body = JSON.stringify(out);
  }
  return body;
}

async function lookup(q: string): Promise<string> {
  const needle = q.trim().toLowerCase();
  if (needle.length < 3) return JSON.stringify({ users: [] });
  const items: any[] = [];
  for (let offset = 0; offset < 5000; offset += 500) {
    const page = await fetch(`${DZ}/api/dz/users?limit=500&offset=${offset}`, { cf: { cacheTtl: 120 } }).then((r) => r.json<any>());
    items.push(...(page.items ?? []));
    if (!page.items || page.items.length < 500) break;
  }
  const users = items
    .filter((u) => [u.client_ip, u.dz_ip, u.owner_pubkey].some((v) => String(v ?? '').toLowerCase().startsWith(needle)))
    .slice(0, 8)
    .map((u) => ({ ip: u.client_ip, owner: String(u.owner_pubkey ?? '').slice(0, 8) + '..', status: u.status, kind: u.kind,
                   metro: u.metro_code ?? u.device_code?.slice(0, 3), device: u.device_code }));
  return JSON.stringify({ users });
}

export default {
  async fetch(req: Request, env: unknown, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const cache = caches.default;
    try {
      if (url.pathname === '/lookup') {
        return new Response(await lookup(url.searchParams.get('q') ?? ''), { headers: JSON_HEADERS });
      }
      if (url.pathname === '/badge.json') {
        const key = new Request(`${url.origin}/badge.json`);
        const hit = await cache.match(key);
        if (hit) return hit;
        const res = new Response(await build(), { headers: { ...JSON_HEADERS, 'cache-control': 'public, max-age=30' } });
        ctx.waitUntil(cache.put(key, res.clone()));
        return res;
      }
      return new Response('not found', { status: 404 });
    } catch (e) {
      return new Response(JSON.stringify({ error: String(e) }), { status: 502, headers: JSON_HEADERS });
    }
  },
};
