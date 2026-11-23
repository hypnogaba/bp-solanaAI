-- DZ Map 1.1: lay the fiber, light the world. A personal puzzle on the DoubleZero map.
--
-- The world (data/world.png, 160x74) is cut into 100 land pieces. Pick a dark piece with the
-- d-pad, press SELECT, and lay the fiber: a packet runs along the line, hit SELECT while it is
-- in the green and the piece lights up. Miss and the packet took the public internet. The
-- faster you get, the faster the packet. Everything is yours and stays on the badge: no Wi-Fi
-- needed. With Wi-Fi the app checks in once: near a DoubleZero metro you get a boost, and you
-- see how many pieces the whole community has laid.
--
-- Perks at 10 / 25 / 50 / 75 / 100 pieces: titles, Mako skins, metro names, season 2.
-- Keys: d-pad move, SELECT lay fiber, CANCEL menu (about, links, exit).
--
-- Server: worker/worker.ts (Cloudflare). Bundled: data/world.png, data/metros.json, art/logo.png.

local HOST     = "dz-badge.hypnogaba.workers.dev"          -- also in app.json hosts
local WS_URL   = "wss://" .. HOST .. "/checkin"
local MAP_URL  = "https://" .. HOST .. "/map"
local VERSION  = "1.1"

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
  { title = "Source",   sub = "this app, MIT",       url = "https://github.com/hypnogaba/bp-solanaAI" },
}

-- Mako, the DoubleZero shark. What she says when the app opens.
local MAKO_SAYS = {
  "surface traffic is slow. down here it never is.",
  "every piece you light is one more city on fiber.",
  "the public internet takes the scenic route. i don't.",
  "a mako is the fastest shark. fitting, no?",
  "lay the fiber. the map remembers.",
  "no packet loss in these waters.",
}

-- Perks. Reached at this many pieces in a season.
local PERKS = {
  { at = 0,   title = "newcomer",       skin = "b" },
  { at = 10,  title = "cable layer",    skin = "a" },
  { at = 25,  title = "metro builder",  skin = "v" },
  { at = 50,  title = "backbone",       skin = "p" },
  { at = 75,  title = "exchange point", skin = "g" },
  { at = 100, title = "doublezero",     skin = "y" },
}

-- map projection (must match server/make_world.py) -------------------------------------------
local MW, MH, TILE = 160, 74, 8
local LON0, LON1, LAT0, LAT1 = -170, 180, 74, -58
local function proj(la, lo)
  local x = math.floor((lo - LON0) / (LON1 - LON0) * MW)
  local y = math.floor((LAT0 - la) / (LAT0 - LAT1) * MH)
  return math.max(0, math.min(MW - 1, x)), math.max(0, math.min(MH - 1, y))
end
-- The 100 land tiles (tx, ty). Piece i = TILES[i].
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
local N = #TILES

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

-- Mako (20 x 9), facing left; the right-facing frame is the mirror. "b" is the skin colour.
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
local frenzy = {}
local frenzyUntil = 0

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
local MENU = { "Lay fiber on the next dark piece", "About DZ Map", "Links and QR codes", "Exit" }
local menuSel = 1
local menuRows = {}
for i = 1, #MENU do
  menuRows[i] = ui.label(16, BODY_Y + 8 + (i - 1) * 26, "", { size = 14, color = C.text, w = 296 })
end
local menuFoot = ui.label(8, BODY_Y + 120, "", { size = 12, color = C.dim, w = 304 })

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

-- state -------------------------------------------------------------------------------------
local screen = "home"
local metros = fs.json("data/metros.json") or {}
local land = ui.load("data/world.png")

-- Progress, in storage: p = 100 chars of 0/1, s = season, hits, miss, streak, best,
-- day = last day a daily bonus was given, home = metro code near the badge (from the worker).
local G = storage.get("g")
if type(G) ~= "table" or type(G.p) ~= "string" or #G.p ~= N then
  G = { p = string.rep("0", N), s = 1, hits = 0, miss = 0, streak = 0, best = 0, day = "", home = nil }
end
local community = storage.get("c")                          -- last answer from the worker
local cursor = 1
local sock, gotMsg, loading = nil, false, false
local spinner, spinPos = nil, 0
local joinIndex = 1
local konami, konamiAt = 0, 0
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
local function metroName(code)
  local m = code and metros[code]
  return m and m.n or (code and code:upper() or "?")
end
local function tileOf(la, lo)
  local x, y = proj(la, lo)
  local tx, ty = x // TILE, y // TILE
  for i, t in ipairs(TILES) do if t[1] == tx and t[2] == ty then return i end end
  return nil
end
local function metrosIn(i)
  local out = {}
  local t = TILES[i]
  for code, m in pairs(metros) do
    local x, y = proj(m.la, m.lo)
    if x // TILE == t[1] and y // TILE == t[2] then out[#out + 1] = code end
  end
  table.sort(out)
  return out
end
local function region(i)
  local t = TILES[i]
  local lon = LON0 + (t[1] * TILE + 4) / MW * (LON1 - LON0)
  local lat = LAT0 - (t[2] * TILE + 4) / MH * (LAT0 - LAT1)
  if lat > 15 and lon < -30 then return "North America" end
  if lat <= 15 and lon < -30 then return "South America" end
  if lon >= -30 and lon < 60 and lat > 35 then return "Europe" end
  if lon >= -30 and lon < 60 then return "Africa" end
  if lat < -8 and lon > 100 then return "Oceania" end
  return "Asia"
end
local function dist2(i, j)
  local a, b = TILES[i], TILES[j]
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
  return h ~= nil and dist2(h, i) <= 2
end
-- Two random metros, as the ends of the fiber being laid.
local codes = {}
for k in pairs(metros) do codes[#codes + 1] = k end
table.sort(codes)
local function twoMetros(i)
  local inside = metrosIn(i)
  local a = inside[1] or codes[(i * 7) % #codes + 1]
  local b = codes[(i * 13 + math.floor(sys.millis() / 1000)) % #codes + 1]
  if b == a then b = codes[(i * 13 + 1) % #codes + 1] end
  return a, b
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
local function spinStop()
  if spinner then timer.cancel(spinner) spinner = nil end
  led.off()
end
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
local function flash(colour)
  for i = 1, led.count do led.hex(i, colour) end
  timer.after(220, led.off)
end

-- drawing -----------------------------------------------------------------------------------
local fresh = {}                                            -- pieces lit this session, drawn green
local function drawMap()
  map:clear()
  map:image(land, 0, 0)
  local n = count()
  for i, tile in ipairs(TILES) do
    if lit(i) then
      local colour = fresh[i] and C.fresh or (n >= N and C.purple or C.lit)
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
    if code == G.home then
      map:rect(x - 1, y - 1, 3, 3, C.home)
    elseif lit(tileOf(m.la, m.lo) or 1) then
      map:rect(x - 1, y - 1, 3, 3, C.accent)
    else
      map:pixel(x, y, C.metroOff)
    end
  end
  local t = TILES[cursor]
  local x0, y0 = t[1] * TILE, t[2] * TILE
  local x1, y1 = math.min(MW - 1, x0 + TILE - 1), math.min(MH - 1, y0 + TILE - 1)
  map:line(x0, y0, x1, y0, C.cursor) map:line(x0, y1, x1, y1, C.cursor)
  map:line(x0, y0, x0, y1, C.cursor) map:line(x1, y0, x1, y1, C.cursor)
end

local function status()
  local n = count()
  local p = perk(n)
  stamp:text(string.format("%d/%d", n, N))
  local season = G.s > 1 and ("  season " .. G.s) or ""
  line1:text(string.format("%d/%d pieces   %s%s", n, N, p.title, season))
  if n >= N then
    line2:text("map complete. SELECT a piece for season " .. (G.s + 1))
    return
  end
  local inside = metrosIn(cursor)
  local names = {}
  for _, c in ipairs(inside) do names[#names + 1] = (n >= 50) and metroName(c) or c:upper() end
  local where = region(cursor)
  if #names > 0 then where = where .. ": " .. table.concat(names, ", ") end
  if lit(cursor) then
    line2:text(where .. "  (lit)")
  else
    line2:text(where .. (homeTurf(cursor) and "  home turf x2" or "") .. "  SELECT to lay fiber")
  end
end

local function showOnly(which)
  local home = which == "home"
  map:show(home) line1:show(home) line2:show(home) mako:show(home)
  for _, f in ipairs(frenzy) do f:show(home) end
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
    r:text((i == menuSel and "> " or "  ") .. MENU[i])
    r:color(i == menuSel and C.accent or C.text)
  end
  menuFoot:text(communityLine())
end

render = function()
  if screen == "home" then
    showOnly("home")
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
    aboutText:text("DoubleZero is dedicated fiber for Solana: validators and traders talk over private links, not the public internet. Lay fiber across the world map, one piece at a time: pick a dark piece, hit SELECT when the packet is in the green. Perks at 10, 25, 50, 75 and 100. Mako keeps count.")
    credit:text("built by @hypnogaba with Claude   MIT")
    credit2:text(communityLine())
    ui.hint("CANCEL back")
  elseif screen == "qr" then
    showOnly("qr")
    showJoin(joinIndex)
  end
end

local function go(s)
  screen = s
  render()
end
local function say(text) subtitle:text(text) end

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

-- A piece was earned at tile i. Returns how many pieces were lit in all.
local function earn(i, perfect)
  local before = count()
  reveal(i)
  local extra = {}
  if perfect then extra[#extra + 1] = "perfect: +1" end
  if homeTurf(i) then extra[#extra + 1] = "home turf: +1" end
  local d = today()
  if d ~= "" and G.day ~= d then G.day = d; extra[#extra + 1] = "daily fiber: +1" end
  local k = 0
  for _, label in ipairs(extra) do
    local j = nearestDark(i)
    if j and reveal(j) then
      k = k + 1
      timer.after(600 * k, function() ui.toast(label) end)
    end
  end
  local n = count()
  local p0, p1 = perk(before), perk(n)
  if p1.at > p0.at then
    timer.after(1200, function()
      ui.toast("perk: " .. p1.title .. (n >= 50 and p1.at == 50 and " (metro names on)" or ""))
      wave(C.purple, 3)
      applySkin()
    end)
  end
  if n >= N then
    timer.after(2200, function()
      ui.toast("The whole map is on fiber. Season " .. G.s .. " complete!")
      wave(C.accent, 5)
    end)
  end
  save()
  return n - before
end

local function startSeason()
  G.s = G.s + 1
  G.p = string.rep("0", N)
  fresh = {}
  save()
  ui.toast("Season " .. G.s .. ": faster packets, same world.")
  applySkin()
  render()
end

-- the game ----------------------------------------------------------------------------------
local function difficulty()
  local n = count()
  local speedUp = (G.s - 1) * 350
  local duration = math.max(800, 2600 - n * 15 - speedUp)
  local width = math.max(12, 56 - math.floor(n * 0.4) - (G.s - 1) * 6)
  return duration, width
end

local function startGame(i)
  if lit(i) then ui.toast("Already on fiber.") return end
  screen = "game"
  showOnly("game")
  local duration, width = difficulty()
  local a, b = twoMetros(i)
  local zx = GX0 + 60 + (sys.millis() * 7 + i * 31) % (GX1 - GX0 - 60 - width)
  if gZone then gZone:remove() end
  gZone = ui.rect(zx, GY - 9, width, 19, { color = C.accent, radius = 3 })
  gPacket:pos(GX0, GY - 5)
  gTitle:text("Lay the fiber: " .. region(i))
  gSub:text(string.format("piece %d of %d   %s", i, N, perk(count()).title))
  gFrom:text(a:upper())
  gTo:text(b:upper())
  gMsg:text("")
  gHint:text("SELECT when the packet is in the green")
  subtitle:text("packets wait for no one")
  ui.hint("SELECT now!   CANCEL back")
  game = { piece = i, t = 0, duration = duration, zx = zx, zw = width, done = false, x = GX0 }
  led.off()
end

local function endGame(hit, perfect)
  if not game or game.done then return end
  game.done = true
  local i = game.piece
  if hit then
    G.hits = G.hits + 1
    G.streak = G.streak + 1
    if G.streak > G.best then G.best = G.streak end
    local got = earn(i, perfect)
    gMsg:text(perfect and "PERFECT. Straight down the fiber." or "Connected. Piece lit.")
    gMsg:color(C.accent)
    gHint:text(string.format("+%d piece%s   streak %d", got, got == 1 and "" or "s", G.streak))
    wave(C.accent, 2)
    if G.streak > 0 and G.streak % 5 == 0 then
      frenzyUntil = sys.millis() + 6000
      timer.after(300, function() ui.toast("streak " .. G.streak .. ": feeding frenzy") end)
    end
  else
    G.miss = G.miss + 1
    G.streak = 0
    gMsg:text("Packet took the public internet. Lost.")
    gMsg:color(C.bad)
    gHint:text("SELECT try again   CANCEL back")
    flash(C.bad)
    save()
  end
  if hit then
    local n = count()
    if n % 10 == 0 then lastSync = -1 end                    -- sync community every 10 pieces
    timer.after(1500, function()
      if screen == "game" then
        cursor = nearestDark(i) or cursor
        go("home")
      end
    end)
  end
end

-- check-in: progress up, community totals + location bonus down ------------------------------
local function apply(d)
  community = d
  storage.set("c", d)
  local you = d.you
  if you then
    if you.home and not G.home then
      G.home = you.home
      save()
      ui.toast("Home metro: " .. metroName(G.home) .. ". Pieces around it count double.")
    end
    if you.boost and you.metro then
      local t = tileOf(metros[you.metro].la, metros[you.metro].lo)
      local got = 0
      for _ = 1, 3 do
        local j = t and nearestDark(t)
        if j and reveal(j) then got = got + 1 end
      end
      if got > 0 then
        save()
        if lit(cursor) then cursor = nearestDark(cursor) or cursor end
        timer.after(900, function()
          ui.toast("Near " .. metroName(you.metro) .. ": metro boost, +" .. got)
          wave(C.home, 3)
        end)
      end
    end
  end
  if screen == "home" then render() elseif screen == "menu" or screen == "about" then render() end
end

local function fetchMap()
  http.get(MAP_URL, function(ok, res)
    loading = false
    spinStop()
    if not ok or res.status ~= 200 then return end
    local d = json.decode(res.body)
    if type(d) == "table" then
      if community and community.you then d.you = nil end
      apply(d)
    end
  end)
end

local function checkin(quiet)
  if loading then return end
  loading = true
  if not quiet then spinStart() end
  if not ws then fetchMap() return end
  gotMsg = false
  sock = ws.open(WS_URL, function(event, data)
    if event == "open" then
      if sock then sock:send(json.encode({ n = count(), s = G.s })) end
    elseif event == "message" then
      local d = json.decode(data)
      if type(d) == "table" then
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

-- ticks: Mako swims, the packet runs ------------------------------------------------------------
function on_tick(ms)
  if screen == "game" and game and not game.done then
    game.t = game.t + ms
    local x = GX0 + (GX1 - GX0 - 10) * game.t / game.duration
    game.x = x
    gPacket:pos(math.floor(x), GY - 5)
    if game.t >= game.duration then endGame(false) end
    return
  end
  if screen ~= "home" then return end
  local fast = sys.millis() < frenzyUntil
  makoT = makoT + ms
  local speed = fast and 0.09 or 0.03
  makoX = makoX + makoDir * speed * ms
  local skin = perk(count()).skin
  if makoX < LANE_X0 then makoX = LANE_X0 makoDir = 1 mako:set(makoRows(skin, true)) end
  if makoX > LANE_X1 then makoX = LANE_X1 makoDir = -1 mako:set(makoRows(skin, false)) end
  local bob = math.floor(math.sin(makoT / 400) * 3)
  mako:pos(math.floor(makoX), LANE_Y0 + bob)
  if fast and #frenzy == 0 then
    for i = 1, 3 do
      frenzy[i] = ui.image(LANE_X0 + i * 20, LANE_Y0 - 30 + i * 14, makoRows(skin, false), { scale = 2 })
    end
    wave(C.bad, 3)
  end
  if #frenzy > 0 then
    if fast then
      for i, f in ipairs(frenzy) do
        local x = (makoX + i * 23) % (LANE_X1 - LANE_X0) + LANE_X0
        f:show(true)
        f:pos(math.floor(x), LANE_Y0 - 28 + i * 12 + math.floor(math.sin(makoT / 250 + i) * 4))
      end
    else
      for _, f in ipairs(frenzy) do f:show(false) end
    end
  end
end

-- cursor movement on the tile grid --------------------------------------------------------------
local function moveCursor(dx, dy)
  if dx ~= 0 then
    cursor = (cursor - 1 + dx + N) % N + 1
    return
  end
  local t = TILES[cursor]
  local best, bd = nil, 1e9
  for i, u in ipairs(TILES) do
    local rowd = (u[2] - t[2]) * dy
    if rowd > 0 then
      local d = rowd * 100 + math.abs(u[1] - t[1])
      if d < bd then bd = d; best = i end
    end
  end
  if best then cursor = best end
end

-- keys ----------------------------------------------------------------------------------------------
function on_key(k, rep)
  if screen == "game" then
    if k == "select" then
      if rep then return true end
      if game and game.done then
        if gMsg and G.streak == 0 then startGame(game.piece) end
        return true
      end
      if game then
        local px = game.x + 5
        local inZone = px >= game.zx and px <= game.zx + game.zw
        local centre = game.zx + game.zw / 2
        local perfect = inZone and math.abs(px - centre) <= math.max(3, game.zw * 0.15)
        endGame(inZone, perfect)
      end
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
        ui.confirm("Start season " .. (G.s + 1) .. "? The map goes dark again, your title stays.", function(yes)
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
      elseif menuSel == 2 then go("about")
      elseif menuSel == 3 then joinIndex = 1 go("qr")
      else return false end                                  -- CANCEL-like: exit the app
      return true
    end
    if k == "back" then go("home") return true end
    return true
  end
  if k == "back" then
    if rickTimer then timer.cancel(rickTimer) rickTimer = nil led.off() end
    if screen == "qr" or screen == "about" or screen == "rick" then go("menu") else go("home") end
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
  if lastSync == -1 and screen == "home" and not loading then
    lastSync = count()
    checkin(true)
  end
end)

-- start ---------------------------------------------------------------------------------------------
do
  local h = homeTile()
  cursor = (h and nearestDark(h)) or nearestDark(27) or 1    -- 27 = Europe, a friendly start
end
applySkin()
say(MAKO_SAYS[(sys.millis() + (sys.time() or 0)) % #MAKO_SAYS + 1])
render()
lastSync = count()
checkin(false)
