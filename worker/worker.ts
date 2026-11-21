// Cloudflare Worker for the DZ badge app (Solana BP26).
//
//   wss://<host>/checkin   the badge opens a socket (ws.open): the worker verifies the
//                          badge ticket, locates the badge by its IP (Cloudflare geo), reveals
//                          one puzzle piece for that badge today and answers with the map state.
//   GET  /map              the same state over plain http (through the badge server), no check-in
//   GET  /badge.json       legacy feed for DZ Status 0.5 (stats, links, routes)
//   GET  /lookup?q=        legacy validator lookup for DZ Status 0.5
//   POST /admin/season?key=<ADMIN_KEY>   start a new season (wipes the puzzle, keeps nothing)
//
// The puzzle: data/world.png (160x74) cut into 8x8 tiles; the 100 tiles that hold land are
// the pieces. Every badge reveals one piece per UTC day, the unrevealed piece nearest to where
// the badge is. A badge within METRO_KM of a DoubleZero metro also lights that metro.
//
// Deploy: cd worker && npx wrangler deploy   (needs the MAP durable object, see wrangler.toml)

export interface Env {
  MAP: DurableObjectNamespace;
  ADMIN_KEY?: string;
  DEV?: string;
}

const APP = 'dzstat';
const SITE = 'https://solana.com/breakpoint/badge';
const DZ = 'https://data.doublezero.xyz';
const MAX_BYTES = 3000;
const METRO_KM = 300;
const JSON_HEADERS = { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': '*' };

// Map projection: must match main.lua and server/make_world.py.
const MW = 160, MH = 74, TILE = 8, COLS = 20;
const LON0 = -170, LON1 = 180, LAT0 = 74, LAT1 = -58;
function proj(lat: number, lon: number): [number, number] {
  const x = Math.floor((lon - LON0) / (LON1 - LON0) * MW);
  const y = Math.floor((LAT0 - lat) / (LAT0 - LAT1) * MH);
  return [Math.max(0, Math.min(MW - 1, x)), Math.max(0, Math.min(MH - 1, y))];
}
// The 100 land tiles (tx, ty) of world.png, in reading order. Index = piece number.
const TILES: [number, number][] = [
  [0,0],[1,0],[2,0],[3,0],[4,0],[5,0],[6,0],[7,0],[8,0],[10,0],[11,0],[12,0],[13,0],[14,0],[15,0],[16,0],[17,0],[18,0],[19,0],
  [0,1],[2,1],[3,1],[4,1],[5,1],[6,1],[9,1],[10,1],[11,1],[12,1],[13,1],[14,1],[15,1],[16,1],[17,1],[18,1],
  [2,2],[3,2],[4,2],[5,2],[9,2],[10,2],[11,2],[12,2],[13,2],[14,2],[15,2],[16,2],[17,2],
  [3,3],[4,3],[5,3],[8,3],[9,3],[10,3],[11,3],[12,3],[13,3],[14,3],[15,3],[16,3],
  [4,4],[5,4],[6,4],[8,4],[9,4],[10,4],[11,4],[12,4],[14,4],[15,4],[16,4],
  [5,5],[6,5],[7,5],[10,5],[11,5],[12,5],[15,5],[16,5],[17,5],[18,5],
  [5,6],[6,6],[7,6],[10,6],[11,6],[12,6],[16,6],[17,6],[18,6],
  [5,7],[6,7],[10,7],[11,7],[16,7],[17,7],[18,7],
  [5,8],[18,8],[19,8],
];

// DoubleZero metros, refreshed from /api/dz/metros when reachable (this is the fallback).
type Metro = { code: string; n: string; la: number; lo: number };
const METROS_FALLBACK: Metro[] = [
  { code: 'ams', n: 'Amsterdam', la: 52.3, lo: 4.9 }, { code: 'bom', n: 'Mumbai', la: 19.1, lo: 72.9 },
  { code: 'chi', n: 'Chicago', la: 41.9, lo: -87.6 }, { code: 'cmh', n: 'Columbus', la: 40.1, lo: -83 },
  { code: 'dfw', n: 'Dallas', la: 32.8, lo: -96.8 }, { code: 'dub', n: 'Dublin', la: 53.3, lo: -6.4 },
  { code: 'fra', n: 'Frankfurt', la: 50.1, lo: 8.7 }, { code: 'hkg', n: 'Hong Kong', la: 22.4, lo: 114.1 },
  { code: 'lax', n: 'Los Angeles', la: 34.1, lo: -118.2 }, { code: 'lon', n: 'London', la: 51.5, lo: -0.6 },
  { code: 'mad', n: 'Madrid', la: 40.5, lo: -3.6 }, { code: 'mia', n: 'Miami', la: 25.8, lo: -80.2 },
  { code: 'mrs', n: 'Marseille', la: 43.3, lo: 5.4 }, { code: 'muc', n: 'Munich', la: 48.1, lo: 11.7 },
  { code: 'nyc', n: 'New York', la: 40.8, lo: -74.1 }, { code: 'osl', n: 'Oslo', la: 59.9, lo: 10.8 },
  { code: 'pit', n: 'Pittsburgh', la: 40.5, lo: -80 }, { code: 'prg', n: 'Prague', la: 50.1, lo: 14.5 },
  { code: 'sao', n: 'Sao Paulo', la: -23.5, lo: -46.6 }, { code: 'sea', n: 'Seattle', la: 47.6, lo: -122.3 },
  { code: 'sin', n: 'Singapore', la: 1.3, lo: 103.8 }, { code: 'sjc', n: 'San Jose', la: 37.2, lo: -121.8 },
  { code: 'slc', n: 'Salt Lake City', la: 40.5, lo: -111.9 }, { code: 'sqq', n: 'Siauliai', la: 55.9, lo: 23.3 },
  { code: 'sto', n: 'Stockholm', la: 59.4, lo: 17.9 }, { code: 'sxb', n: 'Strasbourg', la: 48.6, lo: 7.8 },
  { code: 'tyo', n: 'Tokyo', la: 35.7, lo: 139.7 }, { code: 'was', n: 'Washington', la: 39, lo: -77.5 },
  { code: 'waw', n: 'Warsaw', la: 52.2, lo: 20.9 }, { code: 'ymq', n: 'Montreal', la: 45.5, lo: -73.6 },
  { code: 'yto', n: 'Toronto', la: 43.6, lo: -79.4 },
];
let metrosCache: { at: number; list: Metro[] } = { at: 0, list: METROS_FALLBACK };
async function metros(): Promise<Metro[]> {
  if (Date.now() - metrosCache.at < 3600_000) return metrosCache.list;
  try {
    const r = await fetch(`${DZ}/api/dz/metros?limit=200`, { cf: { cacheTtl: 3600 } }).then((x) => x.json<any>());
    const list = (r.items ?? [])
      .filter((m: any) => m.code && typeof m.lat === 'number' && typeof m.lon === 'number')
      .map((m: any) => ({ code: String(m.code).toLowerCase(), n: String(m.name ?? m.code), la: m.lat, lo: m.lon }));
    if (list.length >= 10) metrosCache = { at: Date.now(), list };
  } catch { /* keep the fallback */ }
  return metrosCache.list;
}
function km(la1: number, lo1: number, la2: number, lo2: number): number {
  const r = Math.PI / 180, dLa = (la2 - la1) * r, dLo = (lo2 - lo1) * r;
  const a = Math.sin(dLa / 2) ** 2 + Math.cos(la1 * r) * Math.cos(la2 * r) * Math.sin(dLo / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(a));
}

// ---- badge ticket (docs: Lua API, "ws", "What the host receives") -----------------------
const keys = new Map<string, CryptoKey>();
const seen = new Map<string, number>();
let fetchedAt = 0;
async function badgeKey(id: string): Promise<CryptoKey | null> {
  if (!keys.has(id) && Date.now() - fetchedAt > 60_000) {
    fetchedAt = Date.now();
    const k = await (await fetch(`${SITE}/api/http/key`)).json<any>();
    const raw = Uint8Array.from(atob(k.key), (c) => c.charCodeAt(0));
    keys.set(k.id, await crypto.subtle.importKey('raw', raw, 'Ed25519', false, ['verify']));
  }
  return keys.get(id) ?? null;
}
async function fromBadgeSocket(req: Request): Promise<{ badge: string; user: string } | null> {
  const url = new URL(req.url);
  const ticket = url.searchParams.get('badge_ticket') ?? '';
  const [a, badge, user, time, request, keyId, sig, extra] = ticket.split('.');
  if (extra !== undefined || a !== APP || !sig || !request || !badge || seen.has(request) ||
      !(Math.abs(Date.now() - Number(time)) < 60_000)) return null;
  const key = await badgeKey(keyId);
  if (!key) return null;
  const signed = ['badge-ws-v1', url.host, APP, badge, user, time, request].join('\n');
  const raw = Uint8Array.from(atob(sig.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
  if (!(await crypto.subtle.verify('Ed25519', key, raw, new TextEncoder().encode(signed)))) return null;
  for (const [k, t] of seen) if (Date.now() - t > 120_000) seen.delete(k);
  seen.set(request, Date.now());
  return { badge, user };
}

// ---- the puzzle state (one Durable Object: strongly consistent, no lost check-ins) --------
type Badge = { day: string; metro: string | null; n: number; m: Record<string, true>; first: string | null };
type State = {
  season: number; started: number;
  tiles: (string | null)[];          // piece index -> badge id that revealed it
  tileAt: number[];                  // unix seconds
  metros: Record<string, { n: number; first: string; at: number }>;
  badges: Record<string, Badge>;
  checkins: number;
  done: number | null;               // unix seconds the 100th piece landed
};
function fresh(season: number): State {
  return { season, started: Math.floor(Date.now() / 1000), tiles: Array(TILES.length).fill(null),
           tileAt: Array(TILES.length).fill(0), metros: {}, badges: {}, checkins: 0, done: null };
}
type Who = { badge: string; user: string; lat: number | null; lon: number | null; city: string; country: string };

export class MapState {
  state: DurableObjectState;
  constructor(state: DurableObjectState) { this.state = state; }

  async load(): Promise<State> {
    return (await this.state.storage.get<State>('s')) ?? fresh(1);
  }

  view(s: State, you?: any) {
    const lit = Object.entries(s.metros).sort((a, b) => b[1].n - a[1].n).map(([c, m]) => [c, m.n]);
    const revealed = s.tiles.filter(Boolean).length;
    return {
      s: s.season, t: s.tiles.map((b) => (b ? '1' : '0')).join(''), n: revealed, N: TILES.length,
      m: lit, b: Object.keys(s.badges).length, c: s.checkins,
      done: s.done, at: Math.floor(Date.now() / 1000), you,
    };
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const s = await this.load();
    if (url.pathname === '/state') return Response.json(this.view(s));
    if (url.pathname === '/season' && req.method === 'POST') {
      await this.state.storage.put('s', fresh(s.season + 1));
      return Response.json({ season: s.season + 1 });
    }
    if (url.pathname === '/checkin' && req.method === 'POST') {
      const who = await req.json<Who>();
      return Response.json(await this.checkin(s, who));
    }
    return new Response('not found', { status: 404 });
  }

  async checkin(s: State, who: Who) {
    const now = Math.floor(Date.now() / 1000);
    const day = new Date().toISOString().slice(0, 10);
    const list = await metros();
    const b: Badge = s.badges[who.badge] ?? { day: '', metro: null, n: 0, m: {}, first: null };
    const isNew = !s.badges[who.badge];
    s.badges[who.badge] = b;
    s.checkins++;

    // Nearest metro, lit when within METRO_KM.
    let near: { code: string; n: string; km: number } | null = null;
    if (who.lat != null && who.lon != null) {
      for (const m of list) {
        const d = km(who.lat, who.lon, m.la, m.lo);
        if (!near || d < near.km) near = { code: m.code, n: m.n, km: d };
      }
    }
    const onMetro = near && near.km <= METRO_KM ? near.code : null;
    let litNow = false;
    if (onMetro && !b.m[onMetro]) {
      b.m[onMetro] = true;
      const m = s.metros[onMetro] ?? { n: 0, first: who.badge, at: now };
      m.n++;
      s.metros[onMetro] = m;
      litNow = m.n === 1;
      if (litNow) b.first = onMetro;
    }
    b.metro = onMetro;

    // One piece per UTC day: the unrevealed tile nearest to the badge.
    let piece: number | null = null;
    if (b.day !== day && s.tiles.some((t) => !t)) {
      let ox: number, oy: number;
      if (who.lat != null && who.lon != null) {
        const [px, py] = proj(who.lat, who.lon);
        ox = px / TILE; oy = py / TILE;
      } else {
        // No location: grow from a revealed piece (or the middle of the map).
        const open = s.tiles.map((t, i) => (t ? i : -1)).filter((i) => i >= 0);
        const i = open.length ? open[s.checkins % open.length] : -1;
        ox = i >= 0 ? TILES[i][0] + 0.5 : COLS / 2; oy = i >= 0 ? TILES[i][1] + 0.5 : 4;
      }
      let best = -1, bestD = Infinity;
      for (let i = 0; i < TILES.length; i++) {
        if (s.tiles[i]) continue;
        const dx = TILES[i][0] + 0.5 - ox, dy = TILES[i][1] + 0.5 - oy;
        const d = dx * dx + dy * dy;
        if (d < bestD) { bestD = d; best = i; }
      }
      if (best >= 0) {
        s.tiles[best] = who.badge; s.tileAt[best] = now;
        b.day = day; b.n++;
        piece = best;
        if (s.tiles.every(Boolean)) s.done = now;
      }
    }
    await this.state.storage.put('s', s);

    const mine = s.tiles.map((t, i) => (t === who.badge ? i : -1)).filter((i) => i >= 0);
    const you = {
      metro: onMetro, near: near ? near.code : null, km: near ? Math.round(near.km) : null,
      city: (who.city || '').slice(0, 24), piece, mine, n: b.n, lit: litNow, first: b.first,
      again: piece == null && b.day === day ? 'tomorrow' : 'now', isNew,
    };
    return this.view(s, you);
  }
}

// ---- legacy feed (DZ Status 0.5) ----------------------------------------------------------
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

// ---- routes --------------------------------------------------------------------------------
export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    const map = env.MAP.get(env.MAP.idFromName('world'));
    try {
      if (url.pathname === '/checkin') {
        if (req.headers.get('upgrade')?.toLowerCase() !== 'websocket') return new Response('websocket only', { status: 426 });
        // Local testing only (wrangler dev --var DEV:1): ?badge=X&lat=..&lon=.. instead of a ticket.
        const dev = env.DEV === '1' && url.searchParams.get('badge');
        const who = dev ? { badge: url.searchParams.get('badge')!, user: 'dev' } : await fromBadgeSocket(req);
        if (!who) return new Response('bad ticket', { status: 403 });
        const cf: any = dev ? { latitude: url.searchParams.get('lat'), longitude: url.searchParams.get('lon'), city: 'Dev' }
                            : (req as any).cf ?? {};
        const lat = Number(cf.latitude), lon = Number(cf.longitude);
        const body: Who = {
          badge: who.badge, user: who.user,
          lat: Number.isFinite(lat) ? lat : null, lon: Number.isFinite(lon) ? lon : null,
          city: String(cf.city ?? ''), country: String(cf.country ?? ''),
        };
        const result = await map.fetch('https://map/checkin', { method: 'POST', body: JSON.stringify(body) }).then((r) => r.text());
        const pair = new WebSocketPair();
        const [client, server] = [pair[0], pair[1]];
        server.accept();
        server.send(result);
        // Let the message go out, then close: the badge needs its server connection back.
        setTimeout(() => { try { server.close(1000, 'done'); } catch { /* closed already */ } }, 300);
        return new Response(null, { status: 101, webSocket: client });
      }
      if (url.pathname === '/map') {
        const body = await map.fetch('https://map/state').then((r) => r.text());
        return new Response(body, { headers: JSON_HEADERS });
      }
      if (url.pathname === '/admin/season' && req.method === 'POST') {
        if (!env.ADMIN_KEY || url.searchParams.get('key') !== env.ADMIN_KEY) return new Response('no', { status: 403 });
        const body = await map.fetch('https://map/season', { method: 'POST' }).then((r) => r.text());
        return new Response(body, { headers: JSON_HEADERS });
      }
      if (url.pathname === '/lookup') {
        return new Response(await lookup(url.searchParams.get('q') ?? ''), { headers: JSON_HEADERS });
      }
      if (url.pathname === '/badge.json') {
        const cache = caches.default;
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
