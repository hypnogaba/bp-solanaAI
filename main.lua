-- DZ Map 1.0: light the DoubleZero world map together, one piece per badge per day.
--
-- Home is the map. The world (data/world.png, 160x74) is cut into 100 land pieces. Every
-- badge with Wi-Fi reveals one piece a day: the dark piece nearest to where the badge is.
-- Being within 300 km of a DoubleZero metro lights that metro too. When all 100 pieces are
-- lit the season is done and Mako the shark is pleased.
--
-- Keys: SELECT check in (one piece today) / refresh, LEFT/RIGHT browse metros,
--       DOWN about + QR codes, CANCEL exit. Mako swims in the Indian Ocean. Try UP x3.
--
-- Server: worker/worker.ts (Cloudflare). Check-in goes over ws (straight from the badge, so
-- the worker sees where the badge is); the state also comes over plain http as a fallback.
-- Bundled: data/world.png, data/metros.json, art/logo.png.

local HOST     = "dz-badge.hypnogaba.workers.dev"          -- also in app.json hosts
local WS_URL   = "wss://" .. HOST .. "/checkin"
local MAP_URL  = "https://" .. HOST .. "/map"
local VERSION  = "1.0"

local C = {
  bg = 0x000000, panel = 0x0E0E12, line = 0x24242C,
  text = 0xFFFFFF, dim = 0x8A8A96, land = 0x24242E,
  accent = 0x14F195, purple = 0x9945FF, lit = 0x5A2E99, mine = 0x9945FF, warn = 0xFFB020, bad = 0xFF4D4D,
  metroOff = 0x5A5A66, sea = 0x000000,
}

local LINKS = {
  { title = "X",        sub = "@doublezero",         url = "https://x.com/doublezero" },
  { title = "Website",  sub = "doublezero.xyz",      url = "https://doublezero.xyz" },
  { title = "Discord",  sub = "community",           url = "https://discord.gg/doublezero" },
  { title = "Source",   sub = "this app, MIT",       url = "https://github.com/hypnogaba/bp-solanaAI" },
}

-- Mako, the DoubleZero shark. What she says when the app opens.
local MAKO_SAYS = {
  "surface traffic is slow. down here it never is.",
  "every piece you light is one more city on fiber.",
  "the public internet takes the scenic route. i don't.",
  "a mako is the fastest shark. fitting, no?",
  "one piece a day. the map remembers.",
  "no packet loss in these waters.",
}

-- map projection (must match server/make_world.py and worker/worker.ts) --------------------
local MW, MH, TILE = 160, 74, 8
local LON0, LON1, LAT0, LAT1 = -170, 180, 74, -58
local function proj(la, lo)
  local x = math.floor((lo - LON0) / (LON1 - LON0) * MW)
  local y = math.floor((LAT0 - la) / (LAT0 - LAT1) * MH)
  return math.max(0, math.min(MW - 1, x)), math.max(0, math.min(MH - 1, y))
end
-- The 100 land tiles, same order as the worker (piece index = position in this list).
local TILES = {
  {0,0},{1,0},{2,0},{3,0},{4,0},{5,0},{6,0},{7,0},{8,0},{10,0},{11,0},{12,0},{13,0},{14,0},{15,0},{16,0},{17,0},{18,0},{19,0},
  {0,1},{2,1},{3,1},{4,1},{5,1},{6,1},{9,1},{10,1},{11,1},{12,1},{13,1},{14,1},{15,1},{16,1},{17,1},{18,1},
  {2,2},{3,2},{4,2},{5,2},{9,2},{10,2},{11,2},{12,2},{13,2},{14,2},{15,2},{16,2},{17,2},
  {3,3},{4,3},{5,3},{8,3},{9,3},{10,3},{11,3},{12,3},{13,3},{14,3},{15,3},{16,3},
  {4,4},{5,4},{6,4},{8,4},{9,4},{10,4},{11,4},{12,4},{14,4},{15,4},{16,4},
  {5,5},{6,5},{7,5},{10,5},{11,5},{12,5},{15,5},{16,5},{17,5},{18,5},
  {5,6},{6,6},{7,6},{10,6},{11,6},{12,6},{16,6},{17,6},{18,6},
  {5,7},{6,7},{10,7},{11,7},{16,7},{17,7},{18,7},
  {5,8},{18,8},{19,8},
}

-- header ------------------------------------------------------------------------------------
ui.bg(C.bg)
local HEAD = 42
ui.rect(0, 0, ui.W, HEAD, { color = C.panel })
ui.rect(0, HEAD, ui.W, 1, { color = C.line })
if fs.exists("art/logo.png") then ui.image(8, 3, "art/logo.png", { scale = 2 }) end
ui.label(50, 6, "DoubleZero", { size = 20, color = C.text })
local subtitle = ui.label(50, 27, "", { size = 12, color = C.dim, w = 262 })
local stamp = ui.label(180, 8, "", { size = 12, color = C.accent, w = 132, align = "right" })

local BODY_Y = HEAD + 6
local MAP_H = MH * 2                                       -- 148 px, to y = 196

-- home: the map ---------------------------------------------------------------------------
local map = ui.canvas(0, BODY_Y, MW, MH, { scale = 2, color = C.sea })
local line1 = ui.label(6, BODY_Y + MAP_H - 30, "", { size = 12, color = C.text, w = 308 })
local line2 = ui.label(6, BODY_Y + MAP_H - 16, "", { size = 12, color = C.dim, w = 308 })

-- Mako (20 x 9), facing left; the right-facing frame is the mirror.
local MAKO_L = {
  "......b.............",
  ".....bbb............",
  "....bbbb.........a..",
  "..bbbbbbbbbbbb..aa..",
  ".bkbbbbbbbbbbbbbb...",
  "bbbbbbbbbbbbbbbbb...",
  ".wwwwwwwwwwwbbb.aa..",
  "...ww...bb.......a..",
  "........a...........",
}
local MAKO_R = {}
for i, row in ipairs(MAKO_L) do MAKO_R[i] = row:reverse() end
local LANE_Y0 = BODY_Y + 102                                -- the Pacific off Chile, on screen
local LANE_X0, LANE_X1 = 2, 46
local mako = ui.image(LANE_X0, LANE_Y0, MAKO_L, { scale = 2 })
local makoX, makoDir, makoT = LANE_X1, -1, 0
local frenzy = {}                                           -- extra sharks (easter egg)
local frenzyUntil = 0

-- about -----------------------------------------------------------------------------------
local bigMako = ui.image(8, BODY_Y + 2, MAKO_R, { scale = 3 })
local aboutTitle = ui.label(80, BODY_Y + 2, "", { size = 20, color = C.text, w = 232 })
local aboutText = ui.label(8, BODY_Y + 34, "", { size = 12, color = C.dim, w = 304 })
local credit = ui.label(8, ui.H - 16 - 30, "", { size = 12, color = C.dim, w = 304 })
local credit2 = ui.label(8, ui.H - 16 - 16, "", { size = 12, color = C.accent, w = 304 })

-- qr ----------------------------------------------------------------------------------------
local qr = ui.qr and ui.qr(8, BODY_Y, 130, LINKS[1].url) or nil
local qrTitle = ui.label(150, BODY_Y + 10, "", { size = 20, color = C.text, w = 160 })
local qrSub = ui.label(150, BODY_Y + 40, "", { size = 12, color = C.dim, w = 160 })
local qrUrl = ui.label(150, BODY_Y + 60, "", { size = 12, color = C.accent, w = 160 })
local qrHint = ui.label(150, BODY_Y + 100, "scan with your phone", { size = 12, color = C.dim, w = 160 })

-- state -------------------------------------------------------------------------------------
local screen = "home"
local metros = fs.json("data/metros.json") or {}
local codes = {}                                            -- metro codes, sorted
for k in pairs(metros) do codes[#codes + 1] = k end
table.sort(codes)
local land = ui.load("data/world.png")
local state = storage.get("map")                            -- last answer from the worker
local updated = storage.get("updated")
local sel = 0                                               -- 0: none, else index into codes
local sock, gotMsg = nil, false
local loading = false
local spinner, spinPos = nil, 0
local joinIndex = 1
local konami, konamiAt = 0, 0
local ups, upsAt = 0, 0
local rickTimer = nil
local celebrated = false

-- helpers -----------------------------------------------------------------------------------
local function ago(unix)
  local now = sys.time()
  if not unix or not now then return "" end
  local d = math.max(0, now - unix)
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return (d // 60) .. "m ago" end
  return (d // 3600) .. "h ago"
end
local function metroName(code)
  local m = code and metros[code]
  return m and m.n or (code and code:upper() or "?")
end
local function litCount(code)
  if not state or not state.m then return 0 end
  for _, e in ipairs(state.m) do if e[1] == code then return tonumber(e[2]) or 0 end end
  return 0
end
local function mineSet()
  local s = {}
  for _, i in ipairs(state and state.you and state.you.mine or {}) do s[i] = true end
  return s
end
local function pieceName(i)
  local t = TILES[(i or -1) + 1]
  if not t then return "" end
  local lon = LON0 + (t[1] * TILE + 4) / MW * (LON1 - LON0)
  local lat = LAT0 - (t[2] * TILE + 4) / MH * (LAT0 - LAT1)
  if lat > 15 and lon < -30 then return "North America" end
  if lat <= 15 and lon < -30 then return "South America" end
  if lon >= -30 and lon < 60 and lat > 35 then return "Europe" end
  if lon >= -30 and lon < 60 then return "Africa" end
  if lat < -8 and lon > 100 then return "Oceania" end
  return "Asia"
end

-- LEDs --------------------------------------------------------------------------------------
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
  if spinner then timer.cancel(spinner) spinner = nil end
  led.off()
  if colour then
    for i = 1, led.count do led.hex(i, colour) end
    timer.after(200, led.off)
  end
end
-- The fiber wave: a pulse of DZ green running across the eight LEDs, then dark.
local function wave(colour, times)
  local step, n = 0, (times or 2) * (led.count + 2)
  local t
  t = timer.every(45, function()
    led.off()
    local i = step % (led.count + 2)
    for k = 0, 2 do
      local j = i - k
      if j >= 1 and j <= led.count then
        local r, g, b = (colour >> 16) & 255, (colour >> 8) & 255, colour & 255
        local f = k == 0 and 1 or (k == 1 and 0.4 or 0.12)
        led.set(j, math.floor(r * f), math.floor(g * f), math.floor(b * f))
      end
    end
    step = step + 1
    if step >= n then timer.cancel(t) led.off() end
  end)
end

-- drawing -----------------------------------------------------------------------------------
local function drawMap()
  map:clear()
  map:image(land, 0, 0)                                     -- land in C.land (dark), sea clear
  local t = state and state.t or ""
  local mine = mineSet()
  local today = state and state.you and state.you.piece
  for i, tile in ipairs(TILES) do
    local on = t:sub(i, i) == "1"
    if on then
      local colour = mine[i - 1] and C.mine or C.lit
      if today == i - 1 then colour = C.accent end
      local x0, y0 = tile[1] * TILE, tile[2] * TILE
      for y = y0, math.min(MH - 1, y0 + TILE - 1) do
        for x = x0, math.min(MW - 1, x0 + TILE - 1) do
          if map:get(x, y) then map:pixel(x, y, colour) end
        end
      end
    end
  end
  for _, code in ipairs(codes) do
    local m = metros[code]
    local x, y = proj(m.la, m.lo)
    if litCount(code) > 0 then
      map:rect(x - 1, y - 1, 3, 3, C.accent)
    else
      map:pixel(x, y, C.metroOff)
    end
  end
  if sel > 0 then
    local m = metros[codes[sel]]
    local x, y = proj(m.la, m.lo)
    map:line(x - 3, y - 3, x + 3, y - 3, C.text) map:line(x - 3, y + 3, x + 3, y + 3, C.text)
    map:line(x - 3, y - 3, x - 3, y + 3, C.text) map:line(x + 3, y - 3, x + 3, y + 3, C.text)
  end
end

local function status()
  if not state then
    line1:text("The map is dark. Join Wi-Fi and press SELECT.")
    line2:text("one piece per badge per day")
    stamp:text("")
    return
  end
  local lit = state.m and #state.m or 0
  local total = 0
  for _ in pairs(metros) do total = total + 1 end
  stamp:text(string.format("%d/%d", tonumber(state.n) or 0, tonumber(state.N) or 100))
  if sel > 0 then
    local code = codes[sel]
    local n = litCount(code)
    line1:text(string.format("%s  %s", code:upper(), metroName(code)))
    line2:text(n > 0 and (n .. (n == 1 and " badge lit it" or " badges lit it")) or "dark: be the first within 300 km")
    return
  end
  line1:text(string.format("%d/%d pieces   %d/%d metros   %d badges", tonumber(state.n) or 0, tonumber(state.N) or 100, lit, total, tonumber(state.b) or 0))
  local you = state.you
  if state.done then
    line2:text("map complete! season " .. tostring(state.s) .. ". thank you, all of you.")
  elseif you then
    local where = you.metro and (you.metro:upper()) or (you.near and (you.near:upper() .. " " .. tostring(you.km) .. "km") or "?")
    if you.piece then
      line2:text(string.format("you: %s  +1 today (%s)  %d total", where, pieceName(you.piece), tonumber(you.n) or 0))
    elseif you.again == "tomorrow" then
      line2:text(string.format("you: %s  %d pieces  next piece tomorrow", where, tonumber(you.n) or 0))
    else
      line2:text("you: " .. where .. "  SELECT to add a piece")
    end
  else
    line2:text("SELECT to add your piece   " .. ago(updated))
  end
end

local function showOnly(which)
  local home = which == "home"
  map:show(home) line1:show(home) line2:show(home) mako:show(home)
  for _, f in ipairs(frenzy) do f:show(home) end
  local about = which == "about"
  bigMako:show(about) aboutTitle:show(about) aboutText:show(about) credit:show(about) credit2:show(about)
  local q = which == "qr"
  if qr then qr:show(q) end
  qrTitle:show(q) qrSub:show(q) qrUrl:show(q) qrHint:show(q)
end

local function showJoin(i)
  joinIndex = ((i - 1) % #LINKS) + 1
  local l = LINKS[joinIndex]
  if qr then qr:text(l.url) end
  qrTitle:text(l.title)
  qrSub:text(l.sub)
  qrUrl:text((l.url:gsub("^https://", "")))
  subtitle:text("links  " .. joinIndex .. "/" .. #LINKS)
  ui.hint("< > next   CANCEL back")
end

local function render()
  if screen == "home" then
    showOnly("home")
    drawMap()
    status()
    ui.hint("SELECT check in   < > metros   DOWN about")
  elseif screen == "about" then
    showOnly("about")
    subtitle:text("about")
    aboutTitle:text("DZ Map " .. VERSION)
    aboutText:text("DoubleZero is dedicated fiber for Solana: validators and traders talk over private links, not the public internet. Light the world map with the community: one piece per badge per day, from wherever you are. Mako keeps count.")
    credit:text("built by @hypnogaba with Claude   MIT")
    credit2:text("SELECT links and QR codes")
    ui.hint("SELECT links   CANCEL back")
  elseif screen == "qr" then
    showOnly("qr")
    showJoin(joinIndex)
  end
end

local function go(s)
  screen = s
  render()
end

-- check-in ------------------------------------------------------------------------------------
local function say(text) subtitle:text(text) end

local function apply(d, checkedIn)
  state = d
  updated = sys.time()
  storage.set("map", d) storage.set("updated", updated)
  local you = d.you
  if checkedIn and you then
    if you.piece then
      ui.toast(string.format("+1 piece: %s  (%d/%d)", pieceName(you.piece), tonumber(d.n) or 0, tonumber(d.N) or 100))
      wave(C.accent, 2)
      say(you.isNew and "welcome to the map. mako noticed." or "another piece of the world. nice.")
    elseif you.again == "tomorrow" then
      ui.toast("Already placed today. Come back tomorrow.")
      say("one a day keeps the map honest.")
    end
    if you.lit then
      timer.after(900, function() ui.toast("You lit " .. metroName(you.metro) .. "!") wave(C.purple, 2) end)
    end
  end
  if d.done and not celebrated then
    celebrated = true
    timer.after(1800, function() ui.toast("The map is complete. All of it.") wave(C.accent, 4) end)
  end
  if screen == "home" then render() end
end

local function fetchMap()
  http.get(MAP_URL, function(ok, res)
    loading = false
    if not ok or res.status ~= 200 then
      spinStop(C.bad)
      say(state and ("offline, showing " .. ago(updated)) or "offline: no map yet")
      return
    end
    local d = json.decode(res.body)
    if type(d) ~= "table" then spinStop(C.warn) return end
    if state and state.you then d.you = state.you end     -- keep what we know about this badge
    spinStop(C.accent)
    apply(d, false)
  end)
end

local function checkin()
  if loading then return end
  loading = true
  spinStart()
  say("checking in...")
  if not ws then fetchMap() return end                      -- Solana OS before 0.5.1
  gotMsg = false
  sock = ws.open(WS_URL, function(event, data)
    if event == "message" then
      local d = json.decode(data)
      if type(d) == "table" then
        gotMsg = true
        loading = false
        spinStop(nil)
        apply(d, true)
      end
      if sock then sock:close() end
    elseif event == "close" then
      sock = nil
      if not gotMsg then
        -- "offline", "not linked", "unreachable", "busy", ...: fall back to the plain map.
        say(data == "offline" and "no Wi-Fi: showing the last map" or ("check-in failed: " .. tostring(data)))
        fetchMap()
      end
    end
  end)
end

-- easter eggs -----------------------------------------------------------------------------------
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

-- UP UP UP on the map: a feeding frenzy. More sharks, faster, LEDs chase. Six seconds.
local function startFrenzy()
  if #frenzy == 0 then
    for i = 1, 3 do
      frenzy[i] = ui.image(LANE_X0 + i * 20, LANE_Y0 - 30 + i * 14, MAKO_L, { scale = 2 })
    end
  end
  for _, f in ipairs(frenzy) do f:show(true) end
  frenzyUntil = sys.millis() + 6000
  ui.toast("mako: faster than the internet")
  say("feeding frenzy. no packets were harmed.")
  wave(C.bad, 3)
end

-- Mako swims --------------------------------------------------------------------------------------
function on_tick(ms)
  if screen ~= "home" then return end
  local fast = sys.millis() < frenzyUntil
  makoT = makoT + ms
  local speed = fast and 0.09 or 0.03                       -- px per ms
  makoX = makoX + makoDir * speed * ms
  if makoX < LANE_X0 then makoX = LANE_X0 makoDir = 1 mako:set(MAKO_R) end
  if makoX > LANE_X1 then makoX = LANE_X1 makoDir = -1 mako:set(MAKO_L) end
  local bob = math.floor(math.sin(makoT / 400) * 3)
  mako:pos(math.floor(makoX), LANE_Y0 + bob)
  if #frenzy > 0 then
    if fast then
      for i, f in ipairs(frenzy) do
        local x = (makoX + i * 23) % (LANE_X1 - LANE_X0) + LANE_X0
        f:pos(math.floor(x), LANE_Y0 - 28 + i * 12 + math.floor(math.sin(makoT / 250 + i) * 4))
      end
    else
      for _, f in ipairs(frenzy) do f:show(false) end
    end
  end
end

-- keys ----------------------------------------------------------------------------------------------
function on_key(k, rep)
  if rep then return true end
  if screen == "home" then
    if k == "select" then checkin() return true end
    if k == "right" then sel = (sel + 1) % (#codes + 1) ups = 0 render() return true end
    if k == "left" then sel = (sel - 1) % (#codes + 1) ups = 0 render() return true end
    if k == "down" then ups = 0 go("about") return true end
    if k == "up" then
      if sys.millis() - upsAt > 1500 then ups = 0 end
      upsAt = sys.millis()
      ups = ups + 1
      if ups >= 3 then ups = 0 startFrenzy() end
      return true
    end
    return false                                             -- CANCEL exits the app
  end
  if k == "back" then
    if rickTimer then timer.cancel(rickTimer) rickTimer = nil led.off() end
    if screen == "qr" then go("about") else go("home") end
    return true
  end
  if screen == "about" then
    if k == "select" then go("qr") return true end
    local seq = { "up", "up", "down", "down", "left", "right" }
    if sys.millis() - konamiAt > 3000 then konami = 0 end
    konamiAt = sys.millis()
    if k == seq[konami + 1] then konami = konami + 1 else konami = (k == "up") and 1 or 0 end
    if konami == #seq then konami = 0 rickroll() end
    return true
  end
  if screen == "qr" then
    if k == "right" then showJoin(joinIndex + 1) return true end
    if k == "left" then showJoin(joinIndex - 1) return true end
    return true
  end
  return true
end

function on_exit()
  if spinner then timer.cancel(spinner) end
  if rickTimer then timer.cancel(rickTimer) end
  if sock then sock:close() end
  led.off()
end

-- start ---------------------------------------------------------------------------------------------
say(MAKO_SAYS[(sys.millis() + (sys.time() or 0)) % #MAKO_SAYS + 1])
render()
checkin()
