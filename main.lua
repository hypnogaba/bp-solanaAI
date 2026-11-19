-- DZ Status 0.4: DoubleZero on the BP26 badge. Map, Network, Links.
--
-- Data: FEED_URL, a small JSON made by server/badge.ts from data.doublezero.xyz
-- (the site's own endpoints are far over the badge's 3.5 KB answer cap).
-- Falls back to https://data.doublezero.xyz/api/stats (public, 300 bytes) for the
-- Network tab when the feed is unreachable.
--
-- Bundled: data/world.png (160x74 land bitmap, equirectangular), data/metros.json.
-- Keys: LEFT/RIGHT tabs, UP/DOWN scroll lists, SELECT refresh, CANCEL exit.

local FEED_URL   = "https://dz-badge.example.workers.dev/badge.json"      -- change to your proxy host
local STATS_URL  = "https://data.doublezero.xyz/api/stats"
local REFRESH_MS = 60000

local C = {
  bg = 0x000000, panel = 0x0E0E12, line = 0x24242C, land = 0x24242E,
  text = 0xFFFFFF, dim = 0x8A8A96,
  accent = 0x14F195, purple = 0x9945FF, warn = 0xFFB020, bad = 0xFF4D4D,
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
if fs.exists("art/logo.png") then
  ui.image(8, 3, "art/logo.png", { scale = 2 })
end
ui.label(50, 6, "DoubleZero", { size = 20, color = C.text })
local subtitle = ui.label(50, 27, "", { size = 12, color = C.dim, w = 200 })
local stamp = ui.label(180, 14, "", { size = 12, color = C.dim, w = 132, align = "right" })

local TAB_Y = HEAD + 6
local TABS = { "Map", "Network", "Links" }
local tabLabels = {}
local tabLine = ui.rect(0, TAB_Y + 18, 0, 2, { color = C.accent })
local BODY_Y = TAB_Y + 26
local BODY_H = ui.H - BODY_Y - 16

-- views --------------------------------------------------------------------
local map = ui.canvas(0, BODY_Y, MW, MH, { scale = 2, color = C.bg })   -- 320 x 148
local mapNote = ui.label(8, BODY_Y + MH * 2 + 2, "", { size = 12, color = C.dim, w = 304 })
local list = ui.list(0, BODY_Y, ui.W, BODY_H, { "Loading..." }, {})
local footer = ui.label(8, ui.H - 30, "", { size = 12, color = C.dim, w = 304 })
ui.hint("< > tabs   SELECT refresh   CANCEL exit")

-- state --------------------------------------------------------------------
local tab = 1
local feed = nil        -- { stats = {...}, pairs = {{a,b,g,bad}}, top = {{...}}, issues = {{...}} }
local updated = nil
local loading = 0
local spinner, spinPos = nil, 0
local metros = fs.json("data/metros.json") or {}

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

-- map drawing --------------------------------------------------------------
local land = ui.load("data/world.png")      -- 160 x 74, decoded once, stamped on each redraw

local function drawLinks()
  map:clear()
  map:image(land, 0, 0)
  local pairs_ = feed and feed.pairs or {}
  local bad = 0
  for _, p in ipairs(pairs_) do
    local a, b = metros[p[1]], metros[p[2]]
    if a and b and p[1] ~= p[2] then
      local x1, y1 = proj(a.la, a.lo)
      local x2, y2 = proj(b.la, b.lo)
      local colour = (tonumber(p[4]) or 0) > 0 and C.bad or ((tonumber(p[3]) or 0) >= 100 and C.purple or 0x5A2E99)
      map:line(x1, y1, x2, y2, colour)
      if (tonumber(p[4]) or 0) > 0 then bad = bad + 1 end
    end
  end
  for _, m in pairs(metros) do
    local x, y = proj(m.la, m.lo)
    map:rect(x - 1, y - 1, 3, 3, C.accent)
  end
  local n = 0
  for _ in pairs(metros) do n = n + 1 end
  mapNote:text(string.format("%d metros  %d routes%s", n, #pairs_, bad > 0 and ("  " .. bad .. " drained") or ""))
end

-- list rows ----------------------------------------------------------------
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
  if not feed then return { "No data yet" } end
  local rows = {}
  local l = feed.links or {}
  rows[#rows + 1] = { title = "Status", right = tostring(feed.status or "?"):sub(1, 12),
    sub = fmtInt(l.healthy) .. " healthy of " .. fmtInt(l.total) }
  for _, i in ipairs(feed.issues or {}) do
    rows[#rows + 1] = { title = tostring(i.code or ""):sub(1, 30), right = tostring(i.issue or ""):sub(1, 10),
      sub = tostring(i.route or ""):sub(1, 40) }
  end
  for _, t in ipairs(feed.top or {}) do
    rows[#rows + 1] = { title = tostring(t.code or ""):sub(1, 30), right = tostring(t.util or 0) .. "%",
      sub = tostring(t.route or ""):sub(1, 40) }
  end
  return rows
end

-- rendering ----------------------------------------------------------------
local function drawTabs()
  for _, l in ipairs(tabLabels) do l:remove() end
  tabLabels = {}
  local x = 8
  for i, name in ipairs(TABS) do
    tabLabels[#tabLabels + 1] = ui.label(x, TAB_Y, name, { size = 14, color = (i == tab) and C.text or C.dim })
    local w = #name * 8 + 4
    if i == tab then tabLine:pos(x - 2, TAB_Y + 18) tabLine:size(w, 2) end
    x = x + w + 14
  end
end

local function render()
  drawTabs()
  local onMap = (tab == 1)
  map:show(onMap) mapNote:show(onMap) list:show(not onMap)
  if onMap then
    drawLinks()
    subtitle:text("network map")
  elseif tab == 2 then
    list:items(networkRows())
    subtitle:text("network")
  else
    list:items(linksRows())
    subtitle:text("links and incidents")
  end
  stamp:text(ago(updated))
end

-- data ---------------------------------------------------------------------
local function got(ok, res, url)
  loading = loading - 1
  if not ok then print(url .. ": " .. tostring(res)) footer:text("offline: " .. tostring(res)) spinStop(C.bad) return nil end
  if res.status ~= 200 then footer:text("server said " .. res.status) spinStop(C.warn) return nil end
  local data = json.decode(res.body)
  if type(data) ~= "table" then footer:text("bad json") spinStop(C.warn) return nil end
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
      feed = data
      updated = sys.time()
      storage.set("feed", feed)
      storage.set("updated", updated)
      footer:text("data.doublezero.xyz")
      render()
      spinStop(C.accent)
      return
    end
    -- fallback: at least the Network tab, straight from the public stats endpoint
    loading = 1
    http.get(STATS_URL, function(ok2, res2)
      local s = got(ok2, res2, "stats")
      if s then
        feed = feed or {}
        feed.stats = s
        updated = sys.time()
        storage.set("feed", feed)
        storage.set("updated", updated)
        footer:text("stats only: feed unreachable")
        render()
        spinStop(C.warn)
      end
    end)
  end)
end

-- start --------------------------------------------------------------------
feed = storage.get("feed")
updated = storage.get("updated")
if feed then footer:text("cached") end
render()
refresh()
timer.every(REFRESH_MS, refresh)

function on_key(k)
  if k == "select" then refresh() return true end
  if k == "right" then tab = tab % #TABS + 1 render() return true end
  if k == "left" then tab = (tab - 2) % #TABS + 1 render() return true end
  return false
end

function on_exit()
  if spinner then timer.cancel(spinner) end
  led.off()
end
