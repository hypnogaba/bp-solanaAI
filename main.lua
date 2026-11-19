-- DZ Status 0.3: DoubleZero network status on the BP26 badge.
--
-- Network tab: GET https://data.doublezero.xyz/api/stats (public, ~300 bytes).
-- Status tab:  GET https://data.doublezero.xyz/api/status is ~65 KB, too big for
--   a badge (3.5 KB cap), so it comes from STATUS_URL, a small proxy
--   (server/badge.ts). Leave STATUS_URL nil to ship with the Network tab only.
-- Keys: LEFT/RIGHT tabs, UP/DOWN scroll, SELECT refresh, CANCEL exit.
-- Last good data is cached in storage so the app shows something offline.

local STATS_URL  = "https://data.doublezero.xyz/api/stats"
local STATUS_URL = nil   -- e.g. "https://your.host/dz/status.json"
local REFRESH_MS = 60000

local C = {
  bg = 0x000000, panel = 0x0E0E12, line = 0x24242C,
  text = 0xFFFFFF, dim = 0x8A8A96,
  accent = 0x14F195, warn = 0xFFB020, bad = 0xFF4D4D,
}

-- layout -------------------------------------------------------------------
ui.bg(C.bg)
local HEAD = 42
ui.rect(0, 0, ui.W, HEAD, { color = C.panel })
ui.rect(0, HEAD, ui.W, 1, { color = C.line })

if fs.exists("art/logo.png") then
  ui.image(8, 3, "art/logo.png", { scale = 2 })          -- 16x18 -> 32x36
else
  ui.image(8, 9, { "wwww.wwww", "w..w.w..w", "w..w.w..w", "wwww.wwww" }, { scale = 3 })
end
ui.label(50, 6, "DoubleZero", { size = 20, color = C.text })
local subtitle = ui.label(50, 27, "network status", { size = 12, color = C.dim })
local stamp    = ui.label(180, 14, "", { size = 12, color = C.dim, w = 132, align = "right" })

local TAB_Y = HEAD + 6
local tabLabels = {}
local tabLine = ui.rect(0, TAB_Y + 18, 0, 2, { color = C.accent })

local LIST_Y = TAB_Y + 26
local LIST_H = ui.H - LIST_Y - 16 - 16
local list = ui.list(0, LIST_Y, ui.W, LIST_H, { "Loading..." }, {})
local footer = ui.label(8, ui.H - 30, "", { size = 12, color = C.dim, w = 304 })
ui.hint("< > tabs   SELECT refresh   CANCEL exit")

-- state --------------------------------------------------------------------
local tabs = {}          -- { {name=, rows=}, ... }
local updated = nil      -- unix seconds of the last good fetch
local tab = 1
local loading = 0
local spinner, spinPos = nil, 0

-- formatting ---------------------------------------------------------------
local function fmtInt(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function fmtM(n)          -- 257386509 -> "257.4M"
  n = tonumber(n) or 0
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(math.floor(n))
end

local function fmtBps(n)        -- bits per second -> "8.4 Tbps"
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

-- rendering ----------------------------------------------------------------
local function drawTabs()
  for _, l in ipairs(tabLabels) do l:remove() end
  tabLabels = {}
  local x = 8
  for i, t in ipairs(tabs) do
    tabLabels[#tabLabels + 1] = ui.label(x, TAB_Y, t.name, { size = 14, color = (i == tab) and C.text or C.dim })
    local w = #t.name * 8 + 4
    if i == tab then tabLine:pos(x - 2, TAB_Y + 18) tabLine:size(w, 2) end
    x = x + w + 14
  end
end

local function render()
  if #tabs == 0 then list:items({ "No data yet" }) return end
  if tab > #tabs then tab = 1 end
  drawTabs()
  local rows = tabs[tab].rows
  list:items(#rows > 0 and rows or { "Nothing here" })
  stamp:text(ago(updated))
end

local function setTab(name, rows)
  for _, t in ipairs(tabs) do
    if t.name == name then t.rows = rows return end
  end
  tabs[#tabs + 1] = { name = name, rows = rows }
end

local function save()
  storage.set("last", { tabs = tabs, updated = updated })
end

-- data: Network from /api/stats -------------------------------------------
local function rowsFromStats(s)
  return {
    { title = "Validators on DZ", right = fmtInt(s.validators_on_dz) },
    { title = "Stake share",      right = string.format("%.1f%%", tonumber(s.stake_share_pct) or 0),
      sub = fmtM(s.total_stake_sol) .. " SOL connected" },
    { title = "Users",            right = fmtInt(s.users) },
    { title = "Devices",          right = fmtInt(s.devices) },
    { title = "Links",            right = fmtInt(s.links) },
    { title = "Metros",           right = fmtInt(s.metros) },
    { title = "Contributors",     right = fmtInt(s.contributors) },
    { title = "Capacity",         right = fmtBps(s.bandwidth_bps) },
    { title = "User inbound",     right = fmtBps(s.user_inbound_bps) },
  }
end

-- data: Status from the proxy (shape in server/badge.ts) -------------------
local function rowsFromStatus(st)
  local rows = {}
  local l = st.links or {}
  rows[#rows + 1] = { title = "Overall", right = tostring(st.status or "?"):sub(1, 12) }
  rows[#rows + 1] = { title = "Links healthy", right = fmtInt(l.healthy), sub = fmtInt(l.total) .. " total" }
  if (tonumber(l.down) or 0) > 0 then
    rows[#rows + 1] = { title = "Links down", right = fmtInt(l.down) }
  end
  if (tonumber(l.degraded) or 0) > 0 then
    rows[#rows + 1] = { title = "Links degraded", right = fmtInt(l.degraded) }
  end
  for _, i in ipairs(st.issues or {}) do
    if type(i) == "table" and type(i.code) == "string" then
      rows[#rows + 1] = { title = i.code:sub(1, 30), right = tostring(i.issue or ""):sub(1, 12),
        sub = tostring(i.route or ""):sub(1, 40) }
    end
    if #rows >= 20 then break end
  end
  return rows
end

local function fetch(url, onData)
  loading = loading + 1
  spinStart()
  http.get(url, function(ok, res)
    loading = loading - 1
    if not ok then
      print("http failed: " .. tostring(res))
      footer:text("offline: " .. tostring(res))
      spinStop(C.bad)
      return
    end
    if res.status ~= 200 then
      print("server said " .. res.status)
      footer:text("server said " .. res.status)
      spinStop(C.warn)
      return
    end
    local data, err = json.decode(res.body)
    if type(data) ~= "table" then
      print("bad json: " .. tostring(err))
      footer:text("bad json")
      spinStop(C.warn)
      return
    end
    onData(data)
    updated = sys.time()
    footer:text("data.doublezero.xyz")
    save()
    render()
    spinStop(C.accent)
  end)
end

local function refresh()
  if loading > 0 then return end
  stamp:text("updating")
  fetch(STATS_URL, function(s) setTab("Network", rowsFromStats(s)) end)
  if STATUS_URL then
    fetch(STATUS_URL, function(st) setTab("Status", rowsFromStatus(st)) end)
  end
end

-- start --------------------------------------------------------------------
local cached = storage.get("last")
if type(cached) == "table" and type(cached.tabs) == "table" then
  tabs, updated = cached.tabs, cached.updated
  footer:text("cached")
end
render()
refresh()
timer.every(REFRESH_MS, refresh)

-- keys ---------------------------------------------------------------------
function on_key(k)
  if k == "select" then refresh() return true end
  if #tabs > 1 then
    if k == "right" then tab = tab % #tabs + 1 render() return true end
    if k == "left" then tab = (tab - 2) % #tabs + 1 render() return true end
  end
  return false
end

function on_exit()
  if spinner then timer.cancel(spinner) end
  led.off()
end
