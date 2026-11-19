# data.doublezero.xyz - public API notes

Observed 2026-11-19 in the browser (mainnet-beta env). No auth needed for the endpoints below.
Values and shapes can change; re-check before relying on them.

## Small, badge-sized

`GET /api/stats` (~300 bytes). This is what the badge app reads.

```json
{"validators_on_dz":411,"total_stake_sol":257386509.29,"stake_share_pct":60.06,
 "users":2208,"devices":87,"links":149,"contributors":15,"metros":31,
 "bandwidth_bps":8425000000000,"user_inbound_bps":21483663675.46,
 "fetched_at":"2026-11-19T15:05:31Z"}
```

`GET /api/version` -> {version, commit, date}
`GET /api/config` -> env, availableEnvs (mainnet-beta, testnet), feature flags
`GET /api/auth/me` -> {account: null} when not signed in

## Big (need a proxy for the badge: 3.5 KB cap)

`GET /api/status` (~65 KB). Top-level keys:
- status: "healthy" | "degraded" | ...
- timestamp
- network: links, users, metros, devices, max_users, facilities, contributors, bandwidth_bps, stake_share_pct, total_stake_sol, user_inbound_bps, validators_on_dz, links_by_status, devices_by_status, stake_share_delta
- links: total, healthy, degraded, unhealthy, down, issues[] (code, issue, since, value, is_down, link_type, contributor, side_a_metro, side_z_metro, bandwidth_bps), top_util_links[100]
- top_device_util[]: code, metro, contributor, device_type, utilization, current_users, max_users
- performance: avg_latency_us, p95_latency_us, max_latency_us, avg_jitter_us, avg_loss_percent
- alerts: links[], devices, isis_devices
- interfaces: issues[]
- system: database, last_ingested

`GET /api/status/link-history?range=24h&buckets=72`
`GET /api/topology/critical-links` (~31 KB)
`GET /api/link-metrics?range=24h&include=status,traffic&has_issues=true`

## Paged lists (`?limit=&offset=`, answer {items, total, limit, offset})

- /api/dz/metros: code, name, country, lat/lon, device_count, user_count, facility_count, unicast_users_count, multicast_subscribers_count, multicast_publishers_count, max_users
- /api/dz/devices: code, status, device_type, contributor_code, metro_code, ...
- /api/dz/links: code, status, link_type, bandwidth_bps, side_a/side_z codes and metros, ...
- /api/dz/contributors: code, name, metro_count, facility_count, device_count, link_count, user_count, max_users
- /api/dz/users: pk, owner_pubkey, status, kind (ibrl, ...), dz_ip, client_ip, device_code, ...

Unknown paths return the SPA's index.html with 200, not a 404: check the content type.
