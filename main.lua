-- DZ Map 1.3: lay the fiber, light the world. An arcade run on the DoubleZero map.
--
-- The world (data/world.png, 160x74) is cut into 13 regions, one for each DoubleZero
-- contributor. Pick a dark region with the d-pad, press SELECT and splice the fiber: a packet
-- bounces between two metros, sometimes slow, sometimes fast; stop it in the green in the
-- middle. A region takes 3 to 6 splices in a row, and every region is faster than the last.
-- A miss costs one of 3 lives; lose them all and the map goes dark. Light all 13: a dance, and
-- the next season is faster still. With Wi-Fi the app checks in: your nearest DoubleZero metro
-- becomes home, and your best score goes on the online leaderboard.
--
-- Perks at 2 / 4 / 7 / 10 / 13 regions: titles, shark skins, metro names.
-- Keys: d-pad move, SELECT splice, CANCEL menu (secrets, leaderboard, about, links, exit).
--
-- Server: worker/worker.ts (Cloudflare). Bundled: data/world.png, data/metros.json, art/logo.png.

local HOST     = "dz-badge.hypnogaba.workers.dev"          -- also in app.json hosts
local WS_URL   = "wss://" .. HOST .. "/checkin"
local MAP_URL  = "https://" .. HOST .. "/map"
local VERSION  = "1.3"

local C = {
  bg = 0x000000, panel = 0x0E0E12, line = 0x24242C,
  text = 0xFFFFFF, dim = 0x8A8A96, land = 0x24242E,
  accent = 0x14F195, purple = 0x9945FF, lit = 0x5A2E99, fresh = 0x14F195, warn = 0xFFB020, bad = 0xFF4D4D,
  metroOff = 0x5A5A66, sea = 0x000000, cursor = 0xFFFFFF, home = 0x19D3F5,
}

local LINKS = {
  { title = "X",        sub = "@doublezero",         url = "https://x.com/doublezero" },
  { title = "Website",  sub = "doublezero.xyz",      url = "https://doublezero.xyz" },
  { title = "Discord",  sub = "community",           url = "https://discord.gg/doublezero" },
  { title = "Source",   sub = "this app, MIT",       url = "https://github.com/hypnogaba/dz-map" },
  { title = "Made by",  sub = "@hypnogaba on X",     url = "https://x.com/hypnogaba" },
}

-- The DoubleZero shark. What it says when the app opens.
local MAKO_SAYS = {
  "surface traffic is slow. down here it never is.",
  "every piece you light is one more city on fiber.",
  "the public internet takes the scenic route. i don't.",
  "the fastest shark on the fiber. fitting, no?",
  "lay the fiber. the map remembers.",
  "no packet loss in these waters.",
}

-- Perks. Reached at this many pieces in a season.
local PERKS = {
  { at = 0,  title = "newcomer",       skin = "b" },
  { at = 2,  title = "cable layer",    skin = "a" },
  { at = 4,  title = "metro builder",  skin = "v" },
  { at = 7,  title = "backbone",       skin = "p" },
  { at = 10, title = "exchange point", skin = "g" },
  { at = 13, title = "doublezero",     skin = "y" },
}
local NAMES_AT = 7                                          -- metro names on the map from this perk

-- map projection (must match server/make_world.py) -------------------------------------------
local MW, MH, TILE = 160, 74, 8
local LON0, LON1, LAT0, LAT1 = -170, 180, 74, -58
local function proj(la, lo)
  local x = math.floor((lo - LON0) / (LON1 - LON0) * MW)
  local y = math.floor((LAT0 - la) / (LAT0 - LAT1) * MH)
  return math.max(0, math.min(MW - 1, x)), math.max(0, math.min(MH - 1, y))
end
-- The 100 land tiles (tx, ty), 8 x 8 px each. They are grouped into the 13 regions below.
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
-- Region of each tile, in TILES order: a = REGIONS[1] ... m = REGIONS[13].
local TILE_REGION = "aaaabbbbbeffjjjkkkkaaabbbeeffjjjkkkcccceeffijlllcccggggiiillcccggggiilldddhhhmmmmdddhhhmmmddhhmmmdmm"
local REGIONS = {
  "Alaska", "Canada", "USA and Mexico", "South America", "Western Europe", "Eastern Europe",
  "North Africa", "Southern Africa", "Middle East and India", "Russia and Central Asia",
  "Siberia", "East Asia", "Oceania",
}
local N = #REGIONS                                          -- 13 pieces: one per contributor
local PIECE_TILES, PIECE_C = {}, {}                         -- tiles of each piece, centre (tx, ty)
local TILE_PIECE, TILE_AT = {}, {}
for i = 1, N do PIECE_TILES[i] = {} end
for t, tile in ipairs(TILES) do
  local r = TILE_REGION:byte(t) - 96
  TILE_PIECE[t] = r
  TILE_AT[tile[1] * 100 + tile[2]] = t
  local list = PIECE_TILES[r]
  list[#list + 1] = t
end
for i = 1, N do
  local sx, sy = 0, 0
  for _, t in ipairs(PIECE_TILES[i]) do sx = sx + TILES[t][1] sy = sy + TILES[t][2] end
  PIECE_C[i] = { sx / #PIECE_TILES[i], sy / #PIECE_TILES[i] }
end
local LIVES = 3
local GAME_TICK = 16                                        -- ms; smoother packet in rounds

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

-- The shark (20 x 9), facing left; the right-facing frame is the mirror. "b" is the skin colour.
local MAKO_BASE = {
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
local function makoRows(skin, mirror)
  local rows = {}
  for i, row in ipairs(MAKO_BASE) do
    local r = (row:gsub("b", skin))
    rows[i] = mirror and r:reverse() or r
  end
  return rows
end
local LANE_Y0 = BODY_Y + 102                                -- the Pacific off Chile, on screen
local LANE_X0, LANE_X1 = 2, 46
local mako = ui.image(LANE_X0, LANE_Y0, makoRows("b", false), { scale = 2 })
local makoX, makoDir, makoT = LANE_X1, -1, 0
local RAINBOW = { "a", "v", "p", "g", "y" }
local rainbowLook = ""
local party = nil                                           -- full-screen dance, built after all other UI

-- game: lay the fiber ---------------------------------------------------------------------
local GX0, GX1, GY = 24, 296, BODY_Y + 78
local gTitle = ui.label(8, BODY_Y + 4, "", { size = 20, color = C.text, w = 304 })
local gSub = ui.label(8, BODY_Y + 30, "", { size = 12, color = C.dim, w = 304 })
local gFrom = ui.label(8, GY - 30, "", { size = 12, color = C.accent, w = 100 })
local gTo = ui.label(212, GY - 30, "", { size = 12, color = C.accent, w = 100, align = "right" })
local gTrack = ui.rect(GX0, GY - 1, GX1 - GX0, 3, { color = C.line })
local gZone = nil
local gPacket = ui.rect(GX0, GY - 5, 10, 10, { color = C.text, radius = 2 })
local gMsg = ui.label(8, GY + 30, "", { size = 14, color = C.text, w = 304 })
local gHint = ui.label(8, GY + 54, "", { size = 12, color = C.dim, w = 304 })

-- menu / about / qr ------------------------------------------------------------------------
local MENU = { "Lay fiber on the next dark region", "How to play", "Secrets", "Leaderboard", "About DZ Map", "Links and QR codes", "Settings", "Exit" }
local menuSel = 1
local menuRows = {}
for i = 1, #MENU do
  menuRows[i] = ui.label(16, BODY_Y + 2 + (i - 1) * 16, "", { size = 14, color = C.text, w = 296 })
end
local menuFoot = ui.label(8, BODY_Y + 132, "", { size = 12, color = C.dim, w = 304 })

local bigMako = ui.image(8, BODY_Y + 2, makoRows("b", true), { scale = 3 })
local aboutTitle = ui.label(80, BODY_Y + 2, "", { size = 20, color = C.text, w = 232 })
local aboutText = ui.label(8, BODY_Y + 34, "", { size = 12, color = C.dim, w = 304 })
local credit = ui.label(8, ui.H - 16 - 30, "", { size = 12, color = C.dim, w = 304 })
local credit2 = ui.label(8, ui.H - 16 - 16, "", { size = 12, color = C.accent, w = 304 })

local qr = ui.qr and ui.qr(8, BODY_Y, 130, LINKS[1].url) or nil
local qrTitle = ui.label(150, BODY_Y + 10, "", { size = 20, color = C.text, w = 160 })
local qrSub = ui.label(150, BODY_Y + 40, "", { size = 12, color = C.dim, w = 160 })
local qrUrl = ui.label(150, BODY_Y + 60, "", { size = 12, color = C.accent, w = 160 })
local qrHint = ui.label(150, BODY_Y + 100, "scan with your phone", { size = 12, color = C.dim, w = 160 })
-- share on X: a bigger QR on the right, the score on the left
local shareQr = ui.qr and ui.qr(146, BODY_Y - 4, 168, "https://x.com/doublezero") or nil
local shTitle = ui.label(8, BODY_Y + 4, "Share on X", { size = 20, color = C.text, w = 136 })
local shScore = ui.label(8, BODY_Y + 40, "", { size = 20, color = C.warn, w = 136 })
local shNote = ui.label(8, BODY_Y + 70, "", { size = 12, color = C.dim, w = 136 })

-- splash, how to play, settings ------------------------------------------------------------
local splashMako = ui.image(100, BODY_Y + 10, makoRows("b", true), { scale = 6 })
local splashTitle = ui.label(0, BODY_Y + 76, "DZ Map", { size = 20, color = C.text, w = 320, align = "center" })
local splashSub = ui.label(8, BODY_Y + 100, "", { size = 12, color = C.dim, w = 304, align = "center" })
local HOWTO = {
  { "1. Pick a region", "The world is 13 dark regions, one for each DoubleZero contributor. Move with the d-pad and press SELECT on a dark one." },
  { "2. Splice the fiber", "The packet bounces between two metros, sometimes slow, sometimes fast. Press SELECT while it is in the green in the middle. A region takes 3 to 6 splices in a row. Dead centre is PERFECT: more points." },
  { "3. Three lives", "A miss costs a life and the region starts over. Lose all three and the whole map goes dark: start again. Light all 13 for a party, then the next season is faster." },
  { "4. Bonuses", "The first region of the day, your home metro's region and a metro boost each need one splice less. With Wi-Fi the app finds your nearest DoubleZero metro and puts your best score on the leaderboard." },
}
local howtoPage = 1
local howtoTitle = ui.label(8, BODY_Y + 4, "", { size = 20, color = C.text, w = 304 })
local howtoText = ui.label(8, BODY_Y + 32, "", { size = 12, color = C.dim, w = 304 })
local howtoFoot = ui.label(8, BODY_Y + 128, "", { size = 12, color = C.accent, w = 304 })
local SETTINGS = { "LEDs", "Reset progress", "Back" }
local setSel = 1
local setRows = {}
for i = 1, #SETTINGS do
  setRows[i] = ui.label(16, BODY_Y + 8 + (i - 1) * 26, "", { size = 14, color = C.text, w = 296 })
end
local setFoot = ui.label(8, BODY_Y + 100, "", { size = 12, color = C.dim, w = 304 })
-- Secrets: listed with hints in the menu. All four make the shark a rainbow.
local SECRETS = {
  { id = "perfect", name = "PERFECT", hint = "Splicing: SELECT dead centre of the green.", how = "SELECT in the middle of the green: +50" },
  { id = "zero", name = "DOUBLE ZERO", hint = "Splicing: PERFECT, then PERFECT again.", how = "2 PERFECT in a row: zero gap, zero loss" },
  { id = "home", name = "HOME METRO", hint = "Join Wi-Fi, open the app: it finds your metro.", how = "Wi-Fi: your home region needs a splice less" },
  { id = "rick", name = "NEVER GONNA", hint = "On the main menu: up up down down, then...", how = "UP UP DOWN DOWN LEFT RIGHT on the main menu" },
}
local secRows = {}
for i = 1, #SECRETS do
  secRows[i] = {
    ui.label(8, BODY_Y + 2 + (i - 1) * 32, "", { size = 12, color = C.warn, w = 304 }),
    ui.label(20, BODY_Y + 16 + (i - 1) * 32, "", { size = 12, color = C.text, w = 292 }),
  }
end
local secFoot = ui.label(8, BODY_Y + 132, "", { size = 12, color = C.purple, w = 304 })
local LB_ROWS = 9
local lbRows = {}
for i = 1, LB_ROWS do
  lbRows[i] = ui.label(16, BODY_Y + 2 + (i - 1) * 14, "", { size = 12, color = C.text, w = 296 })
end
local lbFoot = ui.label(8, BODY_Y + 134, "", { size = 12, color = C.dim, w = 304 })

-- state -------------------------------------------------------------------------------------
local screen = "home"
local metros = fs.json("data/metros.json") or {}
local land = ui.load("data/world.png")

-- Progress, in storage: p = 13 chars of 0/1 (one per region), s = season, lives, score (this
-- run), top (best ever), bank (metro boosts), runs, hits, miss, streak, best,
-- day = last day a daily bonus was given, home = metro code near the badge (from the worker).
local G = storage.get("g")
if type(G) ~= "table" or type(G.p) ~= "string" then          -- any length: migrated below
  G = { p = string.rep("0", N), s = 1, hits = 0, miss = 0, streak = 0, best = 0, day = "", home = nil }
end
if #G.p == #TILES then                                      -- 1.2 and older: 100 tiles -> 13 regions
  local np = {}
  for i = 1, N do
    local on = 0
    for _, t in ipairs(PIECE_TILES[i]) do if G.p:sub(t, t) == "1" then on = on + 1 end end
    np[i] = (on * 2 >= #PIECE_TILES[i]) and "1" or "0"
  end
  G.p = table.concat(np)
elseif #G.p ~= N then
  G.p = string.rep("0", N)
end
G.sec = type(G.sec) == "table" and G.sec or {}
G.sec.frenzy = nil                                          -- 1.2 secret, replaced by DOUBLE ZERO
if G.lives == nil then G.lives = LIVES end
for _, k in ipairs({ "s", "hits", "miss", "streak", "best", "lives", "score", "top", "bank", "runs" }) do
  G[k] = math.floor(tonumber(G[k]) or 0)
end
if G.s < 1 then G.s = 1 end
if G.lives < 1 or G.lives > LIVES then G.lives = LIVES end
if type(G.day) ~= "string" then G.day = "" end
if G.home ~= nil and type(G.home) ~= "string" then G.home = nil end
if type(G.sec) ~= "table" then G.sec = {} end
storage.remove("map")                                       -- 1.0.x keys, no longer used
storage.remove("updated")
if G.leds == nil then G.leds = true end
if G.seen == nil then G.seen = false end                   -- how-to-play shown once
local function ledsOn() return G.leds ~= false end
local community = storage.get("c")                          -- last answer from the worker
local cursor = 1
local sock, gotMsg, loading = nil, false, false
local spinner, spinPos = nil, 0
local joinIndex = 1
local konami, konamiAt = 0, 0
local loadingAt, synced, lastTry = 0, false, 0
local makoLine = ""
local roundId = 0
local rickTimer = nil
local game = nil                                            -- the current round
local lastSync = -1

-- helpers -----------------------------------------------------------------------------------
local function count()
  local n = 0
  for i = 1, N do if G.p:sub(i, i) == "1" then n = n + 1 end end
  return n
end
local function lit(i) return G.p:sub(i, i) == "1" end
local function setLit(i)
  G.p = G.p:sub(1, i - 1) .. "1" .. G.p:sub(i + 1)
end
local function save()
  storage.set("g", G)
end
local function perk(n)
  local p = PERKS[1]
  for _, q in ipairs(PERKS) do if n >= q.at then p = q end end
  return p
end
local function nextPerk(n)
  for _, q in ipairs(PERKS) do if n < q.at then return q end end
  return nil
end
local function today()
  local t = sys.time()
  if not t then return "" end
  return tostring(t // 86400)
end
-- Delayed jobs run from on_tick: the badge allows only 8 timers at once.
local jobs = {}
local function later(ms, fn) jobs[#jobs + 1] = { at = sys.millis() + ms, fn = fn } end
local function runJobs()
  if #jobs == 0 then return end
  local now, due = sys.millis(), {}
  for k = #jobs, 1, -1 do
    if jobs[k].at <= now then due[#due + 1] = table.remove(jobs, k) end
  end
  for k = #due, 1, -1 do due[k].fn() end
end
local function secCount()
  local n = 0
  for _, it in ipairs(SECRETS) do if G.sec[it.id] then n = n + 1 end end
  return n
end
local function metroName(code)
  local m = code and metros[code]
  return m and m.n or (code and code:upper() or "?")
end
local function tileOf(la, lo)                              -- piece (region) at a place
  local x, y = proj(la, lo)
  local t = TILE_AT[(x // TILE) * 100 + y // TILE]
  return t and TILE_PIECE[t] or nil
end
local function metrosIn(i)
  local out = {}
  for code, m in pairs(metros) do
    if type(m) == "table" and tonumber(m.la) and tonumber(m.lo) and tileOf(m.la, m.lo) == i then out[#out + 1] = code end
  end
  table.sort(out)
  return out
end
local function region(i)
  return REGIONS[i] or "?"
end
local function dist2(i, j)
  local a, b = PIECE_C[i], PIECE_C[j]
  return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2
end
local function nearestDark(from)
  local best, bd = nil, 1e9
  for i = 1, N do
    if not lit(i) then
      local d = dist2(from, i)
      if d < bd then bd = d; best = i end
    end
  end
  return best
end
local function homeTile()
  local m = G.home and metros[G.home]
  return m and tileOf(m.la, m.lo) or nil
end
local function homeTurf(i)
  local h = homeTile()
  return h ~= nil and h == i
end
-- Two random metros, as the ends of the fiber being laid.
local codes = {}
for k in pairs(metros) do codes[#codes + 1] = k end
table.sort(codes)
local function twoMetros(i)
  if #codes == 0 then return "?", "?" end
  local inside = metrosIn(i)
  local a = inside[1] or codes[(i * 7) % #codes + 1]
  local b = codes[(i * 13 + math.floor(sys.millis() / 1000)) % #codes + 1]
  if b == a then b = codes[(i * 13 + 1) % #codes + 1] end
  return a, b
end

-- LEDs --------------------------------------------------------------------------------------
local function spinStart()
  if spinner or not ledsOn() then return end
  spinPos = 0
  spinner = timer.every(70, function()
    led.off()
    led.hex(spinPos % 6 + 1, C.accent)
    spinPos = spinPos + 1
  end)
end
local function spinStop()
  if spinner then timer.cancel(spinner) spinner = nil end
  led.off()
end
local waveTimer = nil
local function wave(colour, times)
  if not ledsOn() then return end
  if waveTimer then timer.cancel(waveTimer) waveTimer = nil end   -- one wave at a time
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
    if step >= n then timer.cancel(t) waveTimer = nil led.off() end
  end)
  waveTimer = t
end
local function flash(colour)
  if not ledsOn() then return end
  for i = 1, led.count do led.hex(i, colour) end
  later(220, led.off)
end

-- drawing -----------------------------------------------------------------------------------
local fresh = {}                                            -- pieces lit this session, drawn green
local function drawMap()
  map:clear()
  map:image(land, 0, 0)
  local n = count()
  for i = 1, N do
    if lit(i) then
      local colour = fresh[i] and C.fresh or (n >= N and C.purple or C.lit)
      for _, t in ipairs(PIECE_TILES[i]) do
        local x0, y0 = TILES[t][1] * TILE, TILES[t][2] * TILE
        for y = y0, math.min(MH - 1, y0 + TILE - 1) do
          for x = x0, math.min(MW - 1, x0 + TILE - 1) do
            if map:get(x, y) then map:pixel(x, y, colour) end
          end
        end
      end
    end
  end
  for _, code in ipairs(codes) do
    local m = metros[code]
    local x, y = proj(m.la, m.lo)
    if code == G.home then
      map:rect(x - 1, y - 1, 3, 3, C.home)
    elseif lit(tileOf(m.la, m.lo) or 0) then
      map:rect(x - 1, y - 1, 3, 3, C.accent)
    else
      map:pixel(x, y, C.metroOff)
    end
  end
  -- cursor: the outline of the region (edges of its tiles that do not touch another of its tiles)
  for _, t in ipairs(PIECE_TILES[cursor] or {}) do
    local tx, ty = TILES[t][1], TILES[t][2]
    local x0, y0 = tx * TILE, ty * TILE
    local x1, y1 = math.min(MW - 1, x0 + TILE - 1), math.min(MH - 1, y0 + TILE - 1)
    local function mine(dx, dy)
      local u = TILE_AT[(tx + dx) * 100 + ty + dy]
      return u and TILE_PIECE[u] == cursor
    end
    if not mine(0, -1) then map:line(x0, y0, x1, y0, C.cursor) end
    if not mine(0, 1) then map:line(x0, y1, x1, y1, C.cursor) end
    if not mine(-1, 0) then map:line(x0, y0, x0, y1, C.cursor) end
    if not mine(1, 0) then map:line(x1, y0, x1, y1, C.cursor) end
  end
end

local function status()
  local n = count()
  local p = perk(n)
  stamp:text(string.format("%d/%d  lives %d", n, N, G.lives))
  local season = G.s > 1 and ("  season " .. G.s) or ""
  line1:text(string.format("%d/%d  score %d  %s%s", n, N, G.score, p.title, season))
  if n >= N then
    line2:text("map complete. SELECT a piece for season " .. (G.s + 1))
    return
  end
  local inside = metrosIn(cursor)
  local names = {}
  for _, c in ipairs(inside) do names[#names + 1] = (n >= NAMES_AT) and metroName(c) or c:upper() end
  local where = region(cursor)
  if #names > 0 then where = where .. ": " .. table.concat(names, ", ") end
  if lit(cursor) then
    line2:text(where .. "  (lit)")
  else
    line2:text(where .. (homeTurf(cursor) and "  home" or "") .. "  SELECT splice")
  end
end

local function showOnly(which)
  local home = which == "home"
  map:show(home) line1:show(home) line2:show(home) mako:show(home)
  local g = which == "game"
  gTitle:show(g) gSub:show(g) gFrom:show(g) gTo:show(g) gTrack:show(g) gPacket:show(g) gMsg:show(g) gHint:show(g)
  if gZone then gZone:show(g) end
  local menu = which == "menu"
  for _, r in ipairs(menuRows) do r:show(menu) end
  menuFoot:show(menu)
  local about = which == "about"
  bigMako:show(about) aboutTitle:show(about) aboutText:show(about) credit:show(about) credit2:show(about)
  local q = which == "qr"
  if qr then qr:show(q) end
  qrTitle:show(q) qrSub:show(q) qrUrl:show(q) qrHint:show(q)
  local sp = which == "splash"
  splashMako:show(sp) splashTitle:show(sp) splashSub:show(sp)
  local h = which == "howto"
  howtoTitle:show(h) howtoText:show(h) howtoFoot:show(h)
  local st = which == "settings"
  for _, r in ipairs(setRows) do r:show(st) end
  setFoot:show(st)
  local sc = which == "secrets"
  for _, r in ipairs(secRows) do r[1]:show(sc) r[2]:show(sc) end
  secFoot:show(sc)
  local sh = which == "share"
  if shareQr then shareQr:show(sh) end
  shTitle:show(sh) shScore:show(sh) shNote:show(sh)
  local lb = which == "board"
  for _, r in ipairs(lbRows) do r:show(lb) end
  lbFoot:show(lb)
  local pt = which == "party"
  if party then for _, o in ipairs(party.all) do o:show(pt) end end
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

local function communityLine()
  local c = community and community.c
  if not c then return "community: connect Wi-Fi to see the totals" end
  return string.format("community: %d pieces by %d badges, %d complete", tonumber(c.pieces) or 0, tonumber(c.badges) or 0, tonumber(c.done) or 0)
end

local render
local function renderMenu()
  for i, r in ipairs(menuRows) do
    local label = MENU[i] == "Secrets" and ("Secrets  " .. secCount() .. "/" .. #SECRETS) or MENU[i]
    r:text((i == menuSel and "> " or "  ") .. label)
    r:color(i == menuSel and C.accent or C.text)
  end
  menuFoot:text(communityLine())
end

render = function()
  if screen == "home" then
    showOnly("home")
    subtitle:text(makoLine)
    drawMap()
    status()
    ui.hint("d-pad pick a piece   SELECT lay fiber   CANCEL menu")
  elseif screen == "menu" then
    showOnly("menu")
    subtitle:text("menu")
    renderMenu()
    ui.hint("UP/DOWN   SELECT choose   CANCEL back")
  elseif screen == "about" then
    showOnly("about")
    subtitle:text("about")
    aboutTitle:text("DZ Map " .. VERSION)
    aboutText:text("DoubleZero is dedicated fiber for Solana: validators and traders talk over private links, not the public internet. Light the world map, one region per contributor: stop the bouncing packet in the green, splice after splice. Three lives. The shark keeps count.")
    credit:text("built by @hypnogaba with Claude   MIT")
    credit2:text(communityLine())
    ui.hint("CANCEL back")
  elseif screen == "qr" then
    showOnly("qr")
    showJoin(joinIndex)
  elseif screen == "howto" then
    showOnly("howto")
    subtitle:text("how to play  " .. howtoPage .. "/" .. #HOWTO)
    howtoTitle:text(HOWTO[howtoPage][1])
    howtoText:text(HOWTO[howtoPage][2])
    howtoFoot:text(howtoPage < #HOWTO and "SELECT next" or "SELECT start laying fiber")
    ui.hint("SELECT next   CANCEL skip")
  elseif screen == "secrets" then
    showOnly("secrets")
    subtitle:text("secrets  " .. secCount() .. "/" .. #SECRETS)
    for i, it in ipairs(SECRETS) do
      local got = G.sec[it.id]
      secRows[i][1]:text((got and "+ " or "? ") .. it.name)
      secRows[i][1]:color(got and C.accent or C.warn)
      secRows[i][2]:text(got and it.how or it.hint)
      secRows[i][2]:color(got and C.dim or C.text)
    end
    secFoot:text(secCount() == #SECRETS and "All found: the shark is a rainbow now." or "Find all four: the shark turns rainbow.")
    ui.hint("CANCEL back")
  elseif screen == "board" then
    showOnly("board")
    subtitle:text("leaderboard")
    local top = community and type(community.c) == "table" and community.c.top
    if type(top) ~= "table" or #top == 0 then
      lbRows[1]:text(loading and "loading..." or "No scores yet. Join Wi-Fi to load the board.")
      for i = 2, LB_ROWS do lbRows[i]:text("") end
    else
      for i = 1, LB_ROWS do
        local r = top[i]
        if type(r) == "table" then
          lbRows[i]:text(string.format("%d. %-16s %7d", i, tostring(r.n or "?"):sub(1, 16), math.floor(tonumber(r.s) or 0)))
          lbRows[i]:color(i == 1 and C.warn or C.text)
        else
          lbRows[i]:text("")
        end
      end
    end
    lbFoot:text(string.format("your best %d   this run %d", G.top, G.score))
    ui.hint("SELECT refresh   UP share on X   CANCEL back")
  elseif screen == "party" then
    showOnly("party")
    party.sub:text(string.format("season %d   score %d   lives left %d", G.s, G.score, G.lives))
    ui.hint("SELECT next season   UP share on X   CANCEL map")
  elseif screen == "settings" then
    showOnly("settings")
    subtitle:text("settings")
    for i, r in ipairs(setRows) do
      local label = SETTINGS[i]
      if i == 1 then label = label .. ": " .. (ledsOn() and "on" or "off") end
      r:text((i == setSel and "> " or "  ") .. label)
      r:color(i == setSel and C.accent or C.text)
    end
    setFoot:text(string.format("hits %d   misses %d   best streak %d   season %d", G.hits, G.miss, G.best, G.s))
    ui.hint("UP/DOWN   SELECT   CANCEL back")
  end
end

local function go(s)
  screen = s
  if sys.tick then sys.tick(s == "game" and GAME_TICK or 30) end
  render()
end
local function say(text) subtitle:text(text) end
local function findSecret(id)
  if G.sec[id] then return end
  G.sec[id] = true
  save()
  local n = secCount()
  later(1800, function()
    if n == #SECRETS then
      ui.toast("All 4 secrets! The shark is a rainbow now.")
      wave(C.warn, 4)
    else
      ui.toast("Secret " .. n .. "/" .. #SECRETS .. " found. Hints: menu > Secrets")
    end
  end)
end

-- rewards -----------------------------------------------------------------------------------
local function applySkin()
  local p = perk(count())
  mako:set(makoRows(p.skin, makoDir > 0))
  bigMako:set(makoRows(p.skin, true))
end

local function reveal(i, why)
  if lit(i) then return false end
  setLit(i)
  fresh[i] = true
  if why then ui.toast(why) end
  return true
end

-- A region was lit. Returns how many regions are lit.
local function earn(i)
  local before = count()
  reveal(i)
  G.score = G.score + 500 * G.s
  if G.score > G.top then G.top = G.score end
  save()
  local n = count()
  local p0, p1 = perk(before), perk(n)
  if p1.at > p0.at then
    later(1200, function()
      ui.toast("perk: " .. p1.title .. (p1.at == NAMES_AT and " (metro names on)" or ""))
      wave(C.purple, 3)
      applySkin()
    end)
  end
  return n
end

local function newRun()
  G.p = string.rep("0", N)
  G.lives = LIVES
  G.score = 0
  G.s = 1
  G.runs = G.runs + 1
  fresh = {}
  save()
  applySkin()
end

local function startSeason()
  G.s = G.s + 1
  G.p = string.rep("0", N)
  G.lives = LIVES
  fresh = {}
  save()
  lastSync = -1
  ui.toast("Season " .. G.s .. ": faster packets, same world.")
  applySkin()
  render()
end

-- the game ----------------------------------------------------------------------------------
-- A round lays one region: `need` splices in a row. The packet bounces between the ends of the
-- track; every pass picks a new speed (slow, normal or fast). SELECT in the green = a splice.
local SPEEDS = { 0.6, 0.8, 1.0, 1.0, 1.5 }                  -- pass time multipliers: low = fast
local MAX_PASSES = 6                                        -- no SELECT for this many passes = miss
local TRACK = GX1 - GX0 - 10
-- Time for one pass at this speed. Never so fast that one tick moves more than 60% of the green,
-- or the packet could jump over it and the region could not be laid.
local function passTime()
  return math.max(game.passMs * game.mul, TRACK * GAME_TICK / (game.zw * 0.6))
end
local function difficulty()
  local n = count()
  local passMs = math.max(260, 950 - n * 45 - (G.s - 1) * 80)
  local width = math.max(12, 40 - n * 2 - (G.s - 1) * 4)
  local need = 3 + n // 4
  return passMs, width, need
end

local function launch()                                     -- (re)start the packet for the next splice
  game.t = -450
  game.pos, game.dir, game.passes = 0, 1, 0
  game.mul = SPEEDS[math.random(#SPEEDS)]
  game.x = GX0
  gPacket:pos(GX0, GY - 5)
end

local function roundText()
  gSub:text(string.format("splice %d/%d   lives %d   score %d +%d", game.got, game.need, G.lives, G.score, game.pts))
end

local function startGame(i)
  if lit(i) then ui.toast("Already on fiber.") return end
  screen = "game"
  if sys.tick then sys.tick(GAME_TICK) end
  showOnly("game")
  local passMs, width, need = difficulty()
  local why = {}
  if homeTurf(i) then need = need - 1 why[#why + 1] = "home" end
  local d = today()
  if d ~= "" and G.day ~= d then need = need - 1 why[#why + 1] = "first of the day" end
  if G.bank > 0 then need = need - 1 why[#why + 1] = "metro boost" end
  need = math.max(2, need)
  local a, b = twoMetros(i)
  local zx = (GX0 + GX1) // 2 - width // 2
  if gZone then gZone:remove() end
  gZone = ui.rect(zx, GY - 9, width, 19, { color = C.accent, radius = 3 })
  gTitle:text(region(i))
  gFrom:text(a:upper())
  gTo:text(b:upper())
  gMsg:text("")
  gMsg:color(C.text)
  gHint:text(#why > 0 and ("one splice less: " .. table.concat(why, ", ")) or "SELECT when the packet is in the green")
  subtitle:text("packets wait for no one")
  ui.hint("SELECT now!   CANCEL back")
  roundId = roundId + 1
  game = { piece = i, passMs = passMs, zx = zx, zw = width, need = need, got = 0, done = false,
           id = roundId, perfRun = 0, used = why, pts = 0 }
  roundText()
  launch()
  led.off()
end

local function endGame(hit)
  if not game or game.done then return end
  game.done = true
  local i = game.piece
  if hit then
    for _, w in ipairs(game.used) do                       -- spend the bonuses this round used
      if w == "first of the day" then G.day = today() end
      if w == "metro boost" then G.bank = G.bank - 1 end
    end
    G.hits = G.hits + 1
    G.streak = G.streak + 1
    if G.streak > G.best then G.best = G.streak end
    G.score = G.score + game.pts
    local n = earn(i)
    gMsg:text("Region on fiber: " .. region(i))
    gMsg:color(C.accent)
    gHint:text(string.format("+%d   %d/%d regions", game.pts + 500 * G.s, n, N))
    wave(C.accent, 2)
    lastSync = -1                                           -- send progress and score
    local id = game.id
    later(1500, function()
      if not (game and game.id == id and screen == "game") then return end
      if n >= N then
        G.score = G.score + 1000 * G.lives
        if G.score > G.top then G.top = G.score end
        save()
        go("party")
        wave(C.purple, 6)
      else
        cursor = nearestDark(i) or cursor
        go("home")
      end
    end)
    return
  end
  G.miss = G.miss + 1
  G.streak = 0
  G.lives = G.lives - 1
  flash(C.bad)
  if G.lives <= 0 then
    local final = G.score
    lastSync = -1
    newRun()
    gMsg:text("Out of lives. The map goes dark.")
    gMsg:color(C.bad)
    gHint:text(string.format("run score %d   best %d   CANCEL map", final, G.top))
    game.over = true
  else
    save()
    gMsg:text("Packet took the public internet. Lives: " .. G.lives)
    gMsg:color(C.bad)
    gHint:text("SELECT try again   CANCEL back")
  end
end

-- one SELECT while the packet runs
local function splice()
  local px = game.x + 5
  local inZone = px >= game.zx and px <= game.zx + game.zw
  if not inZone then endGame(false) return end
  local centre = game.zx + game.zw / 2
  local perfect = math.abs(px - centre) <= math.max(2, game.zw * 0.12)
  game.got = game.got + 1
  game.pts = game.pts + (100 + (perfect and 50 or 0)) * G.s   -- paid when the region is lit
  if perfect then
    findSecret("perfect")
    game.perfRun = game.perfRun + 1
    if game.perfRun == 2 then
      findSecret("zero")
      later(200, function() ui.toast("00: zero gap, zero loss") end)
    end
  else
    game.perfRun = 0
  end
  if game.got >= game.need then endGame(true) return end
  gMsg:text(perfect and "PERFECT splice" or "Spliced")
  gMsg:color(C.accent)
  roundText()
  launch()
end

-- check-in: progress up, community totals + location bonus down ------------------------------
local function apply(d)
  synced = true
  community = d
  storage.set("c", d)
  local you = d.you
  if you then
    if type(you.home) == "string" and you.home ~= "" then findSecret("home") end
    if type(you.home) == "string" and you.home ~= "" and not G.home then
      G.home = you.home
      save()
      local far = tonumber(you.km)
      ui.toast("Home metro: " .. metroName(G.home) .. (far and (", " .. math.floor(far) .. " km") or "") .. ". Pieces around it count double.")
    end
    if you.boost and type(you.metro) == "string" then
      G.bank = math.min(3, G.bank + 1)
      save()
      later(900, function()
        ui.toast("Near " .. metroName(you.metro) .. ": metro boost, next region needs a splice less")
        wave(C.home, 3)
      end)
    end
  end
  if screen == "home" or screen == "menu" or screen == "about" or screen == "board" then render() end
end

local function fetchMap()
  http.get(MAP_URL, function(ok, res)
    loading = false
    spinStop()
    if not ok or res.status ~= 200 then return end
    local okd, d = pcall(json.decode, res.body)
    if okd and type(d) == "table" then
      if community and community.you then d.you = nil end
      apply(d)
    end
  end)
end

local function ownerName()
  local ok, n = pcall(function() return badge and badge.owner and badge.owner() end)
  return (ok and type(n) == "string" and n ~= "") and n or "anon"
end

local function checkin(quiet)
  if loading then return end
  loading = true
  loadingAt = sys.millis()
  lastTry = loadingAt
  if not quiet then spinStart() end
  if not ws then fetchMap() return end
  gotMsg = false
  sock = ws.open(WS_URL, function(event, data)
    if event == "open" then
      if sock then sock:send(json.encode({ n = count(), s = G.s, best = G.top, name = ownerName() })) end
    elseif event == "message" then
      local okd, d = pcall(json.decode, data)
      if okd and type(d) == "table" then
        gotMsg = true
        loading = false
        spinStop()
        apply(d)
      end
      if sock then sock:close() end
    elseif event == "close" then
      sock = nil
      if not gotMsg then
        loading = false
        spinStop()
        if data ~= "offline" then fetchMap() end
      end
    end
  end)
end

-- easter egg: konami on the menu ---------------------------------------------------------------
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
  findSecret("rick")
  local hue = 0
  if rickTimer then timer.cancel(rickTimer) rickTimer = nil end
  if not ledsOn() then return end
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

-- party: the whole map is on fiber. A full-screen dance (built last so it draws on top) ------
local DANCE = {
  { "y..............y", "y.....oooo.....y", ".y...oooooo...y.", ".y...yyyyyy...y.", "..y..ykyyky..y..", "..y..yyyyyy..y..", "...v..yyyy..v...", "...vvvvvvvvvv...", "....vvvvvvvv....", "....vvgggvvv....", "....vvgvgvvv....", "....vvgggvvv....", "....vvvvvvvv....", "....bbbbbbbb....", "....bbb..bbb....", "...bbb....bbb...", "...bbb....bbb...", "..bbb......bbb..", "..www......www..", ".www........www." },
  { "................", "......oooo......", ".....oooooo.....", ".....yyyyyy.....", ".....ykyyky.....", ".....yyyyyy.....", "......yyyy......", "...vvvvvvvvvv...", "..vvvvvvvvvvvv..", "..vv.vgggvv.vv..", "..vv.vgvgvv.vv..", "..yy.vgggvv.yy..", ".....vvvvvv.....", ".....bbbbbb.....", ".....bb..bb.....", ".....bb..bb.....", "....bb....bb....", "....bb....bb....", "....ww....ww....", "...www....www..." },
  { "y...............", "y.....oooo......", ".y...oooooo.....", ".y...yyyyyy.....", "..y..ykyyky.....", "..y..yyyyyy.....", "...v..yyyy......", "...vvvvvvvvvvvyy", "....vvvvvvvv....", "....vvgggvvv....", "....vvgvgvvv....", "....vvgggvvv....", "....vvvvvvvv....", "....bbbbbbbb....", "....bbb..bbbbb..", "....bbb....bbbw.", "....bbb......ww.", "....bbb.........", "....www.........", "...wwww........." },
  { "...............y", "......oooo.....y", ".....oooooo...y.", ".....yyyyyy...y.", ".....ykyyky..y..", ".....yyyyyy..y..", "......yyyy..v...", "yyvvvvvvvvvvv...", "....vvvvvvvv....", "....vvvgggvv....", "....vvvgvgvv....", "....vvvgggvv....", "....vvvvvvvv....", "....bbbbbbbb....", "..bbbbb..bbb....", ".wbbb....bbb....", ".ww......bbb....", ".........bbb....", ".........www....", ".........wwww..." },
}
local RAINBOW_HEX = { C.accent, C.purple, C.warn, C.home, C.bad }
party = { t = 0, f = 1, flash = 0 }
party.bg = ui.rect(0, 0, ui.W, ui.H, { color = C.bg })
party.title = ui.label(0, 10, "THE WORLD IS ON FIBER", { size = 20, color = C.accent, w = ui.W, align = "center" })
party.dancer = ui.image(120, 40, DANCE[1], { scale = 4 })
party.left = ui.image(14, 100, makoRows("y", true), { scale = 3 })
party.right = ui.image(246, 100, makoRows("v", false), { scale = 3 })
party.sub = ui.label(0, 162, "", { size = 12, color = C.text, w = ui.W, align = "center" })
party.sub2 = ui.label(0, 180, "13 of 13 regions: every contributor lit", { size = 12, color = C.dim, w = ui.W, align = "center" })
party.all = { party.bg, party.title, party.dancer, party.left, party.right, party.sub, party.sub2 }

-- share on X: a QR the phone scans; X opens with the post, the link shows the picture card
local shareBack = "menu"
local function urlenc(t)
  return (t:gsub("[^%w%-%._~]", function(c) return c == " " and "+" or string.format("%%%02X", string.byte(c)) end))
end
local function openShare(back)
  shareBack = back or "menu"
  local score, n = math.max(G.score, 0), count()
  if screen == "party" or n == 0 then score = math.max(score, G.top) end
  local text = string.format("I lit %d/13 regions on @doublezero fiber in DZ Map on my Breakpoint badge. Score %d", n, score)
  local link = string.format("https://%s/share?s=%d&r=%d", HOST, score, n)
  local url = "https://x.com/intent/post?text=" .. urlenc(text) .. "&url=" .. urlenc(link)
  screen = "share"
  showOnly("share")
  if shareQr then shareQr:text(url) end
  shScore:text(tostring(score))
  shNote:text(shareQr and (n .. "/13 regions. Scan with your phone: X opens with the post and a picture.")
                       or "Update Solana OS to show the QR.")
  subtitle:text("share")
  ui.hint("CANCEL back")
end

local function openBoard()
  go("board")
  if not loading then
    loading = true
    loadingAt = sys.millis()
    fetchMap()
  end
end

-- ticks: the shark swims, the packet runs ------------------------------------------------------------
function on_tick(ms)
  runJobs()
  if loading and sys.millis() - loadingAt > 8000 then     -- no answer: give up, try later
    loading = false
    spinStop()
    if sock then sock:close() sock = nil end
  end
  if screen == "game" and game and not game.done then
    game.t = game.t + ms
    if game.t > 0 then
      local step = math.min(ms, game.t) / passTime()
      game.pos = game.pos + game.dir * step
      if game.pos >= 1 or game.pos <= 0 then                 -- bounce: new pass, new speed
        game.pos = math.max(0, math.min(1, game.pos))
        game.dir = -game.dir
        game.passes = game.passes + 1
        game.mul = SPEEDS[math.random(#SPEEDS)]
        if game.passes >= MAX_PASSES then
          game.x = -100                                     -- off the track: a sure miss
          endGame(false)
          return
        end
      end
      game.x = GX0 + TRACK * game.pos
      gPacket:pos(math.floor(game.x), GY - 5)
    end
    return
  end
  if screen == "party" and party then
    party.t = party.t + ms
    local f = (party.t // 220) % #DANCE + 1
    if f ~= party.f then party.f = f party.dancer:set(DANCE[f]) end
    local bob = math.floor(math.sin(party.t / 150) * 6)
    party.left:pos(14, 100 + bob)
    party.right:pos(246, 100 - bob)
    if party.t - party.flash > 2600 then party.flash = party.t wave(RAINBOW_HEX[(party.t // 2600) % #RAINBOW_HEX + 1], 1) end
    return
  end
  if screen ~= "home" then return end
  makoT = makoT + ms
  local speed = 0.03
  makoX = makoX + makoDir * speed * ms
  local skin = perk(count()).skin
  if secCount() == #SECRETS then                              -- all secrets: rainbow shark
    skin = RAINBOW[(makoT // 300) % #RAINBOW + 1]
    local look = skin .. (makoDir > 0 and ">" or "<")
    if look ~= rainbowLook then rainbowLook = look mako:set(makoRows(skin, makoDir > 0)) end
  end
  if makoX < LANE_X0 then makoX = LANE_X0 makoDir = 1 mako:set(makoRows(skin, true)) end
  if makoX > LANE_X1 then makoX = LANE_X1 makoDir = -1 mako:set(makoRows(skin, false)) end
  local bob = math.floor(math.sin(makoT / 400) * 3)
  mako:pos(math.floor(makoX), LANE_Y0 + bob)
end

-- cursor movement on the tile grid --------------------------------------------------------------
local function moveCursor(dx, dy)
  local c = PIECE_C[cursor]
  local best, bd = nil, 1e9
  for i = 1, N do
    if i ~= cursor then
      local ex, ey = PIECE_C[i][1] - c[1], PIECE_C[i][2] - c[2]
      local along = ex * dx + ey * dy                       -- distance in the asked direction
      if along > 0.3 then
        local side = math.abs(ex * dy) + math.abs(ey * dx)  -- and off to the side
        local d = along + side * 2
        if d < bd then bd = d best = i end
      end
    end
  end
  if best then cursor = best end
end

-- keys ----------------------------------------------------------------------------------------------
function on_key(k, rep)
  if screen == "game" then
    if k == "select" then
      if rep then return true end
      if game and not game.done and game.t < 0 then return true end   -- get ready: not yet
      if game and game.done then
        if not game.over and G.lives > 0 and not lit(game.piece) then startGame(game.piece) end
        return true
      end
      if game then splice() end
      return true
    end
    if k == "back" then game = nil go("home") return true end
    return true
  end
  if rep and k ~= "left" and k ~= "right" and k ~= "up" and k ~= "down" then return true end
  if screen == "home" then
    if k == "left" then moveCursor(-1, 0) render() return true end
    if k == "right" then moveCursor(1, 0) render() return true end
    if k == "up" then moveCursor(0, -1) render() return true end
    if k == "down" then moveCursor(0, 1) render() return true end
    if k == "select" then
      if count() >= N then
        ui.confirm("Start season " .. (G.s + 1) .. "? The map goes dark again, packets get faster.", function(yes)
          if yes then startSeason() end
        end)
        return true
      end
      startGame(cursor)
      return true
    end
    if k == "back" then menuSel = 1 go("menu") return true end
    return true
  end
  if screen == "menu" then
    local seq = { "up", "up", "down", "down", "left", "right" }
    if sys.millis() - konamiAt > 3000 then konami = 0 end
    konamiAt = sys.millis()
    if k == seq[konami + 1] then konami = konami + 1 else konami = (k == "up") and 1 or 0 end
    if konami == #seq then konami = 0 rickroll() return true end
    if k == "up" then menuSel = (menuSel - 2) % #MENU + 1 renderMenu() return true end
    if k == "down" then menuSel = menuSel % #MENU + 1 renderMenu() return true end
    if k == "select" then
      if menuSel == 1 then
        local j = nearestDark(cursor)
        if j then cursor = j startGame(j) else go("home") end
      elseif menuSel == 2 then howtoPage = 1 go("howto")
      elseif menuSel == 3 then go("secrets")
      elseif menuSel == 4 then openBoard()
      elseif menuSel == 5 then go("about")
      elseif menuSel == 6 then joinIndex = 1 go("qr")
      elseif menuSel == 7 then setSel = 1 go("settings")
      else                                                   -- Exit
        if sys.exit then sys.exit() else return false end
      end
      return true
    end
    if k == "back" then go("home") return true end
    return true
  end
  if screen == "splash" then
    return true                                              -- it ends by itself
  end
  if screen == "share" then
    if k == "back" or k == "select" then go(shareBack) end
    return true
  end
  if screen == "party" then
    if k == "up" then openShare("party") return true end
    if k == "select" then startSeason() go("home") end
    if k == "back" then go("home") end
    return true
  end
  if screen == "board" then
    if k == "up" then openShare("board") return true end
    if k == "select" then openBoard() end
    if k == "back" then go("menu") end
    return true
  end
  if screen == "howto" then
    if k == "select" then
      if howtoPage < #HOWTO then howtoPage = howtoPage + 1 render() else G.seen = true save() go("home") end
    elseif k == "back" then G.seen = true save() go("home") end
    return true
  end
  if screen == "settings" then
    if k == "up" then setSel = (setSel - 2) % #SETTINGS + 1 render() return true end
    if k == "down" then setSel = setSel % #SETTINGS + 1 render() return true end
    if k == "select" then
      if setSel == 1 then G.leds = not ledsOn() save() led.off() render()
      elseif setSel == 2 then
        ui.confirm("Reset the map? Regions, lives and season start over. Your best score stays.", function(yes)
          if yes then
            G = { p = string.rep("0", N), s = 1, hits = 0, miss = 0, streak = 0, best = 0, day = "", home = G.home, leds = G.leds,
                  seen = true, sec = G.sec, lives = LIVES, score = 0, top = G.top, bank = 0, runs = G.runs }
            fresh = {}
            save()
            applySkin()
            ui.toast("Fresh map. The shark forgets nothing, but fine.")
            go("home")
          end
        end)
      else go("menu") end
      return true
    end
    if k == "back" then go("menu") return true end
    return true
  end
  if k == "back" then
    if rickTimer then timer.cancel(rickTimer) rickTimer = nil led.off() end
    if screen == "qr" or screen == "about" or screen == "rick" or screen == "secrets" then go("menu") else go("home") end
    return true
  end
  if screen == "qr" then
    if k == "right" then showJoin(joinIndex + 1) return true end
    if k == "left" then showJoin(joinIndex - 1) return true end
  end
  return true
end

function on_exit()
  if spinner then timer.cancel(spinner) end
  if rickTimer then timer.cancel(rickTimer) end
  if sock then sock:close() end
  led.off()
end

-- periodic community sync (every 10 pieces, see endGame) ----------------------------------------
timer.every(4000, function()
  if screen ~= "home" or loading then return end
  if lastSync == -1 or (not synced and sys.millis() - lastTry > 300000) then   -- offline at start: retry every 5 min
    lastSync = count()
    checkin(true)
  end
end)

-- start ---------------------------------------------------------------------------------------------
do
  local h = homeTile()
  cursor = (h and nearestDark(h)) or nearestDark(5) or 1     -- 5 = Western Europe, a friendly start
end
applySkin()
local line = MAKO_SAYS[(sys.millis() + (sys.time() or 0)) % #MAKO_SAYS + 1]
makoLine = line
say(line)
screen = "splash"
showOnly("splash")
splashMako:set(makoRows(perk(count()).skin, true))
splashSub:text(line)
ui.hint("")
wave(C.accent, 1)
later(1600, function()
  if screen ~= "splash" then return end
  go("home")                                               -- the map first; How to play is in the menu
end)
lastSync = count()
checkin(true)
