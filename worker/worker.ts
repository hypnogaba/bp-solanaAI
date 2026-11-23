// Cloudflare Worker for the DZ badge app (Solana BP26).
//
//   wss://<host>/checkin   the badge opens a socket (ws.open) and sends its progress: the worker
//                          verifies the badge ticket, locates the badge by its IP (Cloudflare geo),
//                          records progress + metros visited, answers with community totals and
//                          the location bonus (near a DoubleZero metro = boost, first time only).
//   GET  /map              community totals over plain http (through the badge server)
//   POST /admin/season?key=<ADMIN_KEY>   wipe the community counters
//
// The puzzle itself (100 land tiles of data/world.png) is personal and lives on the badge.
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
const METRO_KM = 300;
const JSON_HEADERS = { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': '*' };

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

// ---- community state (one Durable Object: strongly consistent) --------------------------
// The puzzle itself is personal and lives on the badge. The worker only knows, per badge, how
// many pieces it has and which metros it has been near, to give a location bonus and to show
// "community: N pieces by M badges, K complete".
type Badge = { n: number; s: number; m: Record<string, true>; at: number; home: string | null };
type State = { badges: Record<string, Badge>; checkins: number };
type Who = { badge: string; user: string; lat: number | null; lon: number | null; city: string; country: string;
             n?: number; s?: number };

export class MapState {
  state: DurableObjectState;
  constructor(state: DurableObjectState) { this.state = state; }

  async load(): Promise<State> {
    return (await this.state.storage.get<State>('c')) ?? { badges: {}, checkins: 0 };
  }

  view(s: State, you?: any) {
    let pieces = 0, done = 0;
    const metros: Record<string, number> = {};
    for (const b of Object.values(s.badges)) {
      pieces += b.n + Math.max(0, b.s - 1) * 100;
      if (b.n >= 100 || b.s > 1) done++;
      for (const m of Object.keys(b.m)) metros[m] = (metros[m] ?? 0) + 1;
    }
    const lit = Object.entries(metros).sort((a, b) => b[1] - a[1]);
    return { c: { pieces, badges: Object.keys(s.badges).length, done, metros: lit }, at: Math.floor(Date.now() / 1000), you };
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const s = await this.load();
    if (url.pathname === '/state') return Response.json(this.view(s));
    if (url.pathname === '/season' && req.method === 'POST') {
      await this.state.storage.put('c', { badges: {}, checkins: 0 });
      return Response.json({ ok: true });
    }
    if (url.pathname === '/checkin' && req.method === 'POST') {
      const who = await req.json<Who>();
      return Response.json(await this.checkin(s, who));
    }
    return new Response('not found', { status: 404 });
  }

  async checkin(s: State, who: Who) {
    const now = Math.floor(Date.now() / 1000);
    const list = await metros();
    const isNew = !s.badges[who.badge];
    const b: Badge = s.badges[who.badge] ?? { n: 0, s: 1, m: {}, at: now, home: null };
    s.badges[who.badge] = b;
    s.checkins++;
    if (typeof who.n === 'number' && who.n >= 0 && who.n <= 100) b.n = Math.floor(who.n);
    if (typeof who.s === 'number' && who.s >= 1 && who.s <= 99) b.s = Math.floor(who.s);
    b.at = now;

    let near: { code: string; km: number } | null = null;
    if (who.lat != null && who.lon != null) {
      for (const m of list) {
        const d = km(who.lat, who.lon, m.la, m.lo);
        if (!near || d < near.km) near = { code: m.code, km: d };
      }
    }
    const onMetro = near && near.km <= METRO_KM ? near.code : null;
    let boost = false;                       // first time this badge is near this metro
    if (onMetro && !b.m[onMetro]) { b.m[onMetro] = true; boost = true; }
    if (onMetro && !b.home) b.home = onMetro;
    await this.state.storage.put('c', s);

    const you = { near: near ? near.code : null, km: near ? Math.round(near.km) : null, metro: onMetro,
                  home: b.home, boost, isNew, city: (who.city || '').slice(0, 24) };
    return this.view(s, you);
  }
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
        const pair = new WebSocketPair();
        const [client, server] = [pair[0], pair[1]];
        server.accept();
        // The badge sends {"n": pieces, "s": season} right after "open"; wait briefly for it.
        const progress = new Promise<Partial<Who>>((resolve) => {
          const t = setTimeout(() => resolve({}), 700);
          server.addEventListener('message', (ev) => {
            clearTimeout(t);
            try { const d = JSON.parse(String(ev.data)); resolve({ n: d.n, s: d.s }); } catch { resolve({}); }
          });
        });
        ctx.waitUntil((async () => {
          Object.assign(body, await progress);
          const result = await map.fetch('https://map/checkin', { method: 'POST', body: JSON.stringify(body) }).then((r) => r.text());
          server.send(result);
          setTimeout(() => { try { server.close(1000, 'done'); } catch { /* closed already */ } }, 300);
        })());
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
      return new Response('not found', { status: 404 });
    } catch (e) {
      return new Response(JSON.stringify({ error: String(e) }), { status: 502, headers: JSON_HEADERS });
    }
  },
};
