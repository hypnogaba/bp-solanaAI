// OPTIONAL proxy for the DZ Status badge app's "Status" tab.
// The Network tab reads https://data.doublezero.xyz/api/stats directly (300 bytes).
// /api/status is ~65 KB, over the badge's 3.5 KB cap, so this trims it.
//
// Run: bun run badge.ts  (PORT=8787), serve over https, then in main.lua set
// STATUS_URL to its address and add that host to `hosts` in app.json.

const SRC = 'https://data.doublezero.xyz/api/status';
let cache: { at: number; body: string } | null = null;
const TTL_MS = 30_000;

async function trimmed() {
  const s: any = await (await fetch(SRC)).json();
  const issues = (s.links?.issues ?? []).slice(0, 8).map((i: any) => ({
    code: i.code,
    issue: String(i.issue ?? '').replace('packet_loss', 'loss').replace('missing_adjacency', 'isis'),
    route: `${i.side_a_metro} - ${i.side_z_metro} · ${i.link_type}`,
  }));
  return {
    status: s.status,
    timestamp: s.timestamp,
    links: { total: s.links?.total, healthy: s.links?.healthy, degraded: s.links?.degraded, down: s.links?.down },
    issues,
  };
}

Bun.serve({
  port: Number(process.env.PORT ?? 8787),
  async fetch(req) {
    if (new URL(req.url).pathname !== '/dz/status.json') return new Response('not found', { status: 404 });
    if (!cache || Date.now() - cache.at > TTL_MS) {
      cache = { at: Date.now(), body: JSON.stringify(await trimmed()) };
    }
    return new Response(cache.body, { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
  },
});
console.log('dz/status.json on :' + (process.env.PORT ?? 8787));
