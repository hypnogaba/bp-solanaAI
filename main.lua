-- DZ Status 0.5: DoubleZero on the Solana BP26 badge.
--
-- Home menu -> Map / Network / Links / Lookup / Join / Alerts / About.
-- SELECT opens, CANCEL goes back (and exits from the menu). UP/DOWN scroll lists.
--
-- Data: FEED_URL, a ~2 KB JSON made by server/badge.ts from data.doublezero.xyz
-- (the site's own endpoints are far over the badge's 3.5 KB answer cap).
-- Falls back to the public /api/stats when the feed is unreachable.
-- Bundled: data/world.png (160x74 land bitmap), data/metros.json, art/logo.png.

local FEED_HOST  = "dz-badge.example.workers.dev"                 -- also in app.json hosts and service.lua
local FEED_URL   = "https://" .. FEED_HOST .. "/badge.json"
local LOOKUP_URL = "https://" .. FEED_HOST .. "/lookup?q="
local STATS_URL  = "https://data.doublezero.xyz/api/stats"
local REFRESH_MS = 60000

local LINKS = {
  { title = "Discord",  sub = "community and support", url = "https://discord.gg/doublezero" },
  { title = "X",        sub = "@doublezero",           url = "https://x.com/doublezero" },
  { title = "Docs",     sub = "docs.doublezero.xyz",   url = "https://docs.doublezero.xyz" },
  { title = "Website",  sub = "doublezero.xyz",        url = "https://doublezero.xyz" },
  { title = "Data",     sub = "data.doublezero.xyz",   url = "https://data.doublezero.xyz" },
}

local C = {
  bg = 0x000000, panel = 0x0E0E12, line = 0x24242C,
  text = 0xFFFFFF, dim = 0x8A8A96,
  accent = 0x14F195, purple = 0x9945FF, purple2 = 0x5A2E99, warn = 0xFFB020, bad = 0xFF4D4D,
}

-- map projection (must match server/make_world.py) ------------------------
local MW, MH = 160, 74
local LON0, LON1, LAT0, LAT1 = -170, 180, 74, -58
local function proj(la, lo)
  local x = math.floor((lo - LON0) / (LON1 - LON0) * MW)
  local y = math.floor((LAT0 - la) / (LAT0 - LAT1) * MH)
  return math.max(0, math.min(MW - 1, x)), math.max(0, math.min(MH - 1, y))
end

-- header -------------------------------------------------------------------
ui.bg(C.bg)
local HEAD = 42
ui.rect(0, 0, ui.W, HEAD, { color = C.panel })
ui.rect(0, HEAD, ui.W, 1, { color = C.line })
if fs.exists("art/logo.png") then ui.image(8, 3, "art/logo.png", { scale = 2 }) end
ui.label(50, 6, "DoubleZero", { size = 20, color = C.text })
local subtitle = ui.label(50, 27, "", { size = 12, color = C.dim, w = 200 })
local stamp = ui.label(180, 14, "", { size = 12, color = C.dim, w = 132, align = "right" })
local dot = ui.rect(306, 30, 6, 6, { color = C.dim })     -- status dot: green / orange / red

local BODY_Y = HEAD + 6
local FOOT_H = 16
local BODY_H = ui.H - BODY_Y - 16 - FOOT_H
local footer = ui.label(8, ui.H - 16 - FOOT_H + 2, "", { size = 12, color = C.dim, w = 304 })

-- widgets (one per screen, shown/hidden) ----------------------------------
local menu = ui.list(0, BODY_Y, ui.W, BODY_H, {}, {})
local list = ui.list(0, BODY_Y, ui.W, BODY_H, {}, {})
local map = ui.canvas(0, BODY_Y, MW, MH, { scale = 2, color = C.bg })           -- 320 x 148
local mapNote = ui.label(8, BODY_Y + MH * 2 - 14, "", { size = 12, color = C.dim, w = 304 })   -- over the empty south
local qr = ui.qr and ui.qr(8, BODY_Y, 130, "https://doublezero.xyz") or nil
local qrTitle = ui.label(150, BODY_Y + 10, "", { size = 20, color = C.text, w = 160 })
local qrSub = ui.label(150, BODY_Y + 40, "", { size = 12, color = C.dim, w = 160 })
local qrUrl = ui.label(150, BODY_Y + 60, "", { size = 12, color = C.accent, w = 160 })
local qrHint = ui.label(150, BODY_Y + 100, "scan with your phone", { size = 12, color = C.dim, w = 160 })
local text1 = ui.label(8, BODY_Y + 4, "", { size = 14, color = C.text, w = 304 })
local text2 = ui.label(8, BODY_Y + 28, "", { size = 12, color = C.dim, w = 304 })
local text3 = ui.label(8, BODY_Y + 70, "", { size = 12, color = C.dim, w = 304 })

-- state --------------------------------------------------------------------
local screen = "menu"
local feed, updated = nil, nil
local loading = 0
local spinner, spinPos = nil, 0
local metros = fs.json("data/metros.json") or {}
local land = ui.load("data/world.png")
local joinIndex = 1
local konami, konamiAt = 0, 0           -- About screen: UP UP DOWN DOWN LEFT RIGHT
local rickTimer = nil

-- formatting ---------------------------------------------------------------
local function fmtInt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function fmtM(n)
  n = tonumber(n) or 0
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(math.floor(n))
end
local function fmtBps(n)
  n = tonumber(n) or 0
  if n >= 1e12 then return string.format("%.1f Tbps", n / 1e12) end
  if n >= 1e9 then return string.format("%.1f Gbps", n / 1e9) end
  return string.format("%.0f Mbps", n / 1e6)
end
local function ago(unix)
  local now = sys.time()
  if not unix or not now then return "" end
  local d = math.max(0, now - unix)
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return (d // 60) .. "m ago" end
  return (d // 3600) .. "h ago"
end
local function statusColour(s)
  if s == "healthy" then return C.accent end
  if s == "degraded" then return C.warn end
  if s then return C.bad end
  return C.dim
end

-- LEDs ---------------------------------------------------------------------
local function spinStart()
  if spinner then return end
  spinPos = 0
  spinner = timer.every(70, function()
    led.off()
    led.hex(spinPos % 6 + 1, C.accent)
    spinPos = spinPos + 1
  end)
end
local function spinStop(colour)
  if loading > 0 then return end
  if spinner then timer.cancel(spinner) spinner = nil end
  led.off()
  if colour then
    for i = 1, led.count do led.hex(i, colour) end
    timer.after(160, led.off)
  end
end

-- screens ------------------------------------------------------------------
local function showOnly(which)
  menu:show(which == "menu")
  list:show(which == "list")
  map:show(which == "map") mapNote:show(which == "map")
  footer:show(which ~= "map")
  local q = (which == "qr")
  if qr then qr:show(q) end
  qrTitle:show(q) qrSub:show(q) qrUrl:show(q) qrHint:show(q)
  local t = (which == "text")
  text1:show(t) text2:show(t) text3:show(t)
end

local function drawMap()
  map:clear()
  map:image(land, 0, 0)
  local routes = feed and feed.pairs or {}
  local bad = 0
  for _, p in ipairs(routes) do
    local a, b = metros[p[1]], metros[p[2]]
    if a and b then
      local x1, y1 = proj(a.la, a.lo)
      local x2, y2 = proj(b.la, b.lo)
      local drained = (tonumber(p[4]) or 0) > 0
      local colour = drained and C.bad or ((tonumber(p[3]) or 0) >= 100 and C.purple or C.purple2)
      map:line(x1, y1, x2, y2, colour)
      if drained then bad = bad + 1 end
    end
  end
  local n = 0
  for _, m in pairs(metros) do
    local x, y = proj(m.la, m.lo)
    map:rect(x - 1, y - 1, 3, 3, C.accent)
    n = n + 1
  end
  mapNote:text(string.format("%d metros   %d routes%s", n, #routes, bad > 0 and ("   " .. bad .. " drained") or ""))
end

local function networkRows()
  local s = feed and feed.stats
  if not s then return { "No data yet" } end
  return {
    { title = "Validators on DZ", right = fmtInt(s.validators_on_dz) },
    { title = "Stake share", right = string.format("%.1f%%", tonumber(s.stake_share_pct) or 0),
      sub = fmtM(s.total_stake_sol) .. " SOL connected" },
    { title = "Users", right = fmtInt(s.users) },
    { title = "Devices", right = fmtInt(s.devices) },
    { title = "Links", right = fmtInt(s.links) },
    { title = "Metros", right = fmtInt(s.metros) },
    { title = "Contributors", right = fmtInt(s.contributors) },
    { title = "Capacity", right = fmtBps(s.bandwidth_bps) },
    { title = "User inbound", right = fmtBps(s.user_inbound_bps) },
  }
end

local function linksRows()
  if not feed or not feed.links then return { "Needs the feed (see About)" } end
  local rows = {}
  local l = feed.links
  rows[#rows + 1] = { title = "Status: " .. tostring(feed.status or "?"), right = fmtInt(l.healthy) .. "/" .. fmtInt(l.total),
    sub = "healthy links" .. ((tonumber(l.down) or 0) > 0 and (", " .. l.down .. " down") or "") }
  local issues = feed.issues or {}
  if #issues == 0 then rows[#rows + 1] = { title = "No incidents", sub = "all links clean" } end
  for _, i in ipairs(issues) do
    rows[#rows + 1] = { title = tostring(i.code or ""):sub(1, 30), right = tostring(i.issue or ""):sub(1, 10),
      sub = "incident  " .. tostring(i.route or ""):sub(1, 30) }
  end
  for _, t in ipairs(feed.top or {}) do
    rows[#rows + 1] = { title = tostring(t.code or ""):sub(1, 30), right = tostring(t.util or 0) .. "%",
      sub = "busiest  " .. tostring(t.route or ""):sub(1, 30) }
  end
  return rows
end

local function showJoin(i)
  joinIndex = ((i - 1) % #LINKS) + 1
  local l = LINKS[joinIndex]
  if qr then qr:text(l.url) end
  qrTitle:text(l.title)
  qrSub:text(l.sub)
  qrUrl:text((l.url:gsub("^https://", "")))
  subtitle:text("join  " .. joinIndex .. "/" .. #LINKS)
  ui.hint("< > next   CANCEL back")
end

local function showAlerts()
  local on = service.running and service.running() or false
  text1:text(on and "Alerts: ON" or "Alerts: OFF")
  text2:text(on and "A background check runs every minute and shows a toast when the network status changes or a new incident appears."
               or "SELECT turns on a background check (once a minute) that toasts you when the network status changes or an incident appears.")
  text3:text(on and "SELECT turns it off." or "You will be asked to allow the service the first time.")
  ui.hint("SELECT toggle   CANCEL back")
end

local RICK = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
local function rickroll()
  screen = "rick"
  showOnly("qr")
  if qr then qr:text(RICK) end
  qrTitle:text("Never gonna")
  qrSub:text("give you up")
  qrUrl:text("scan me. trust me.")
  subtitle:text("you found it")
  ui.hint("CANCEL back")
  local hue = 0
  if rickTimer then timer.cancel(rickTimer) end
  rickTimer = timer.every(60, function()
    for i = 1, led.count do
      local h = (hue + i * 40) % 240
      local r = h < 80 and (80 - h) * 3 or (h > 160 and (h - 160) * 3 or 0)
      local g = h < 80 and h * 3 or (h < 160 and (160 - h) * 3 or 0)
      local b = h >= 80 and (h < 160 and (h - 80) * 3 or (240 - h) * 3) or 0
      led.set(i, r, g, b)
    end
    hue = (hue + 8) % 240
  end)
end

local function showAbout()
  text1:text("DZ Status 0.5")
  text2:text("Live DoubleZero network data from data.doublezero.xyz. Map, stats, link health, validator lookup, community links.")
  text3:text("Built by @hypnogaba. Source: github.com/hypnogaba/bp-solanaAI" .. (feed and feed.links and "" or "\nFeed unreachable: map routes, links and lookup need it."))
  ui.hint("CANCEL back")
end

local MENU = {
  { title = "Map",        sub = "metros and routes",            go = "map" },
  { title = "Network",    sub = "validators, stake, capacity",   go = "network" },
  { title = "Links",      sub = "health, incidents, busiest",    go = "links" },
  { title = "Lookup",     sub = "find a validator by IP or key", go = "lookup" },
  { title = "Join",       sub = "Discord, X, docs",              go = "join" },
  { title = "Alerts",     sub = "background status watch",       go = "alerts" },
  { title = "About",      sub = "this app",                      go = "about" },
}

local function render()
  stamp:text(ago(updated))
  dot:color(statusColour(feed and feed.status))
  if screen == "menu" then
    showOnly("menu")
    subtitle:text("network status")
    ui.hint("UP/DOWN   SELECT open   CANCEL exit")
  elseif screen == "map" then
    showOnly("map") drawMap()
    subtitle:text("map")
    ui.hint("SELECT refresh   CANCEL back")
  elseif screen == "network" then
    showOnly("list") list:items(networkRows())
    subtitle:text("network")
    ui.hint("SELECT refresh   CANCEL back")
  elseif screen == "links" then
    showOnly("list") list:items(linksRows())
    subtitle:text("links")
    ui.hint("SELECT refresh   CANCEL back")
  elseif screen == "join" then
    showOnly("qr") showJoin(joinIndex)
  elseif screen == "alerts" then
    showOnly("text") showAlerts()
    subtitle:text("alerts")
  elseif screen == "about" then
    showOnly("text") showAbout()
    subtitle:text("about")
  elseif screen == "lookupResult" then
    showOnly("list")
    ui.hint("SELECT search again   CANCEL back")
  end
end

local function go(s)
  screen = s
  render()
end

-- lookup -------------------------------------------------------------------
local function lookup()
  ui.input("IP or pubkey", 44, function(q)
    if not q or #q == 0 then go("menu") return end
    q = q:gsub("%s", "")
    screen = "lookupResult"
    showOnly("list")
    subtitle:text("lookup")
    list:items({ "Searching " .. q:sub(1, 20) .. "..." })
    loading = loading + 1
    spinStart()
    http.get(LOOKUP_URL .. q, function(ok, res)
      loading = loading - 1
      if not ok or res.status ~= 200 then
        list:items({ { title = "Lookup unavailable", sub = tostring(ok and res.status or res) } })
        spinStop(C.bad)
        return
      end
      local r = json.decode(res.body)
      local rows = {}
      for _, u in ipairs(type(r) == "table" and r.users or {}) do
        local m = metros[u.metro] and metros[u.metro].n or tostring(u.metro or "?")
        rows[#rows + 1] = { title = tostring(u.ip or u.owner or ""):sub(1, 30), right = tostring(u.status or ""):sub(1, 10),
          sub = m .. "  " .. tostring(u.device or ""):sub(1, 20) .. "  " .. tostring(u.kind or "") }
      end
      if #rows == 0 then rows = { { title = "Not found on DoubleZero", sub = q:sub(1, 40) } } end
      list:items(rows)
      ui.hint("SELECT search again   CANCEL back")
      spinStop(#rows > 0 and C.accent or C.warn)
    end)
  end)
end

-- data ---------------------------------------------------------------------
local function got(ok, res, what)
  loading = loading - 1
  if not ok then print(what .. ": " .. tostring(res)) footer:text("offline: " .. tostring(res)) spinStop(C.bad) return nil end
  if res.status ~= 200 then footer:text(what .. " said " .. res.status) spinStop(C.warn) return nil end
  local data = json.decode(res.body)
  if type(data) ~= "table" then footer:text("bad json from " .. what) spinStop(C.warn) return nil end
  return data
end

local function refresh()
  if loading > 0 then return end
  stamp:text("updating")
  loading = 1
  spinStart()
  http.get(FEED_URL, function(ok, res)
    local data = got(ok, res, "feed")
    if data then
      feed, updated = data, sys.time()
      storage.set("feed", feed) storage.set("updated", updated)
      footer:text("live  data.doublezero.xyz")
      render()
      spinStop(C.accent)
      return
    end
    loading = 1
    http.get(STATS_URL, function(ok2, res2)
      local s = got(ok2, res2, "stats")
      if s then
        feed = feed or {}
        feed.stats, updated = s, sys.time()
        storage.set("feed", feed) storage.set("updated", updated)
        footer:text("stats only: feed unreachable")
        render()
        spinStop(C.warn)
      end
    end)
  end)
end

-- start --------------------------------------------------------------------
menu:items(MENU)
feed = storage.get("feed")
updated = storage.get("updated")
if feed then footer:text("cached")
elseif fs.exists("data/sample.json") then
  feed = fs.json("data/sample.json")            -- demo snapshot until the first live fetch
  footer:text("sample data, fetching live...")
end
render()
refresh()
timer.every(REFRESH_MS, refresh)

function on_service(msg)
  if type(msg) == "table" and msg.status then
    feed = feed or {}
    feed.status = msg.status
    dot:color(statusColour(feed.status))
  end
end

function on_key(k)
  if screen == "menu" then
    if k == "select" then
      local m = MENU[menu:selected() or 1]
      if m.go == "lookup" then lookup() else go(m.go) end
      return true
    end
    return false                                  -- CANCEL exits the app
  end
  if k == "back" then
    if rickTimer then timer.cancel(rickTimer) rickTimer = nil led.off() end
    go("menu") return true
  end
  if screen == "about" then
    local seq = { "up", "up", "down", "down", "left", "right" }
    if sys.millis() - konamiAt > 3000 then konami = 0 end
    konamiAt = sys.millis()
    if k == seq[konami + 1] then konami = konami + 1 else konami = (k == "up") and 1 or 0 end
    if konami == #seq then konami = 0 rickroll() end
    return true
  end
  if screen == "join" then
    if k == "right" then showJoin(joinIndex + 1) return true end
    if k == "left" then showJoin(joinIndex - 1) return true end
    return true
  end
  if screen == "alerts" and k == "select" then
    if service.running and service.running() then
      service.stop()
      ui.toast("Alerts off")
      showAlerts()
    else
      service.start(function(ok, err)
        ui.toast(ok and "Alerts on" or ("Not started: " .. tostring(err)))
        showAlerts()
      end)
    end
    return true
  end
  if screen == "lookupResult" and k == "select" then lookup() return true end
  if k == "select" then refresh() return true end
  return true
end

function on_exit()
  if spinner then timer.cancel(spinner) end
  if rickTimer then timer.cancel(rickTimer) end
  led.off()
end
