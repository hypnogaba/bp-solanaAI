"""A small fake badge for DZ Map: runs main.lua in Lua 5.5 (lupa) with a mock of the badge API
that enforces the real limits we care about (8 timers, 128 UI objects, 200k instructions per
callback), then plays through the screens and checks what each fix promises.

  python3 -m venv .venv && .venv/bin/pip install lupa
  .venv/bin/python tools/fake_badge.py
"""
import json, os, sys
from lupa import lua55

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r"""
local PY = ...
local objs = 0
local function obj(kind)
  objs = objs + 1
  if objs > 128 then error("more than 128 UI objects") end
  local o = { kind = kind, shown = true, txt = "" }
  return setmetatable(o, { __index = function(t, k)
    if k == "text" then return function(self, v) if v ~= nil then self.txt = v end return self.txt end end
    if k == "show" then return function(self, v) self.shown = v end end
    if k == "remove" then return function(self) objs = objs - 1 end end
    if k == "get" then return function(self, x, y) return (x + y) % 3 == 0 end end
    return function() end
  end })
end
ui = { W = 320, H = 218 }
function ui.bg() end
for _, k in ipairs({ "label", "rect", "image", "canvas", "qr", "gradient", "bar" }) do
  ui[k] = function() return obj(k) end
end
function ui.load() return {} end
function ui.hint(t) PY.hint(t) end
function ui.toast(t) PY.toast(t) end
function ui.confirm(t, cb) PY.confirm(t) cb(true) end
led = { count = 8 }
function led.off() end function led.hex() end function led.set() end
local timers, live, nextId = {}, 0, 0
timer = {}
local function add(ms, fn, every)
  live = live + 1
  if live > 8 then error("more than 8 timers") end
  nextId = nextId + 1
  timers[nextId] = { at = PY.now() + ms, ms = ms, fn = fn, every = every }
  PY.maxtimers(live)
  return nextId
end
function timer.after(ms, fn) return add(ms, fn, false) end
function timer.every(ms, fn) return add(ms, fn, true) end
function timer.cancel(id) if timers[id] then timers[id] = nil live = live - 1 end end
function __run_timers()
  local now = PY.now()
  for id, t in pairs(timers) do
    if t.at <= now then
      if t.every then t.at = now + t.ms else timers[id] = nil live = live - 1 end
      t.fn()
    end
  end
end
sys = {}
function sys.millis() return PY.now() end
function sys.time() return PY.clock() end
function sys.exit() PY.exit() end
storage = {}
function storage.get(k) return PY.sget(k) end
function storage.set(k, v) PY.sset(k, v) end
function storage.remove(k) PY.sset(k, nil) end
fs = {}
function fs.exists() return true end
function fs.json(p) return PY.fsjson(p) end
json = {}
function json.encode(v) return PY.jenc(v) end
function json.decode(s) return PY.jdec(s) end
http = {}
function http.get(url, cb) PY.http(url, cb) end
if PY.has_ws() then
  ws = {}
  function ws.open(url, cb)
    local sock = { close = function(self) PY.wsclose() end, send = function(self, m) PY.wssend(m) end }
    PY.wsopen(url, cb)
    return sock
  end
end
"""


class Badge:
    def __init__(self, storage=None, has_ws=True, ws_answer=None, clock=1795000000):
        self.L = lua55.LuaRuntime(unpack_returned_tuples=True)
        self.t = 0
        self.toasts, self.hints, self.confirms, self.sent = [], [], [], []
        self.exited = False
        self.maxt = 0
        self.storage = dict(storage or {})
        self.ws_cb = None
        self.ws_answer = ws_answer       # None = never answers
        self.clock = clock
        py = {
            "now": lambda: self.t, "clock": lambda: self.clock + self.t // 1000,
            "toast": lambda t: self.toasts.append(str(t)), "hint": lambda t: self.hints.append(str(t)),
            "confirm": lambda t: self.confirms.append(str(t)), "exit": self._exit,
            "sget": lambda k: self._to_lua(self.storage.get(k)) if isinstance(self.storage.get(k), (dict, list)) else self.storage.get(k), "sset": self._sset,
            "fsjson": self._fsjson, "jenc": self._jenc, "jdec": self._jdec,
            "http": lambda url, cb: None, "has_ws": lambda: has_ws,
            "wsopen": self._wsopen, "wsclose": lambda: None, "wssend": lambda m: self.sent.append(str(m)),
            "maxtimers": lambda n: setattr(self, "maxt", max(self.maxt, n)),
        }
        self.L.execute(MOCK, self.L.table_from(py))
        self.L.execute("""
          __icount = 0
          debug.sethook(function() __icount = __icount + 100 end, "", 100)
        """)
        self.maxi = 0
        src = open(os.path.join(ROOT, "main.lua")).read()
        self.L.execute(src + "\n__G = function() return G end; __screen = function() return screen end;"
                       " __game = function() return game end; __loading = function() return loading end;"
                       " __next = function() local j = nearestDark(cursor) cursor = j startGame(j) end;"
                       " __apply = apply; __cursor = function() return cursor end; __count = count;"
                       " __party = function() return party end; __shareQr = function() return shareQr end;"
                       " __lb = function() return lbRows end; __N = N; __start = startGame;"
                       " __track_step = function() return TRACK * GAME_TICK / passTime() end")

    def _exit(self):
        self.exited = True

    def _sset(self, k, v):
        if v is None:
            self.storage.pop(k, None)
        else:
            self.storage[k] = v

    def _fsjson(self, p):
        return self._to_lua(json.load(open(os.path.join(ROOT, str(p)))))

    def _to_lua(self, v):
        if isinstance(v, dict):
            return self.L.table_from({k: self._to_lua(x) for k, x in v.items()})
        if isinstance(v, list):
            return self.L.table_from([self._to_lua(x) for x in v])
        return v

    def _to_py(self, v):
        if hasattr(v, "items"):
            d = {k: self._to_py(x) for k, x in v.items()}
            if d and all(isinstance(k, int) for k in d):
                return [d[k] for k in sorted(d)]
            return d
        return v

    def _jenc(self, v):
        return json.dumps(self._to_py(v))

    def _jdec(self, s):
        try:
            return self._to_lua(json.loads(str(s)))
        except Exception:
            return None

    def _wsopen(self, url, cb):
        self.ws_cb = cb
        self.pending_open = True

    def call(self, name, *a):
        self.L.execute("__icount = 0")
        r = self.L.globals()[name](*a)
        self.maxi = max(self.maxi, self.L.eval("__icount"))
        return r

    def tick(self, ms=30, n=1):
        for _ in range(n):
            self.t += ms
            if self.ws_cb and getattr(self, "pending_open", False):
                self.pending_open = False
                self.ws_cb("open", None)
                if self.ws_answer is not None:
                    self.ws_cb("message", self.ws_answer)
                    self.ws_cb("close", "done")
            self.L.globals()["__run_timers"]()
            self.call("on_tick", ms)

    def key(self, k, rep=False):
        return self.call("on_key", k, rep)

    def g(self, name):
        return self.L.globals()[name]()


fails = 0


def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails += 1


def wait_run(b):
    """Tick through the get-ready pause."""
    for _ in range(100):
        gm = b.g("__game")
        if gm is None or gm.done or gm.t > 0:
            return
        b.tick(10)


def splice(b, aim="centre"):
    """One SELECT: at the green's centre, or 'miss' at the start of the track."""
    wait_run(b)
    for _ in range(2000):
        gm = b.g("__game")
        if gm is None or gm.done:
            return
        px = gm.x + 5
        centre = gm.zx + gm.zw / 2
        if gm.t > 0 and ((aim == "centre" and abs(px - centre) <= 1.5) or (aim == "miss" and px < gm.zx - 20)):
            b.key("select")
            return
        b.tick(2)


def lay_region(b):
    """Splice until the round ends (all PERFECT)."""
    for _ in range(10):
        gm = b.g("__game")
        if gm is None or gm.done:
            return
        splice(b)


def fresh(**kw):
    b = Badge(**kw)
    b.tick(30, 60)
    if b.g("__screen") == "howto":
        b.key("back")
    return b


# 1. first launch: splash, how to play (4 pages), home
b = Badge(ws_answer=None)
b.tick(30, 60)
check("first launch opens the map, not the how-to", b.g("__screen") == "home")
check("13 regions", b.L.globals().__N == 13)

# 2. the stuck check-in clears itself (ws never answers)
check("startup check-in is loading", b.g("__loading") is True)
b.tick(30, 300)
check("watchdog: loading clears after 8 s without an answer", b.g("__loading") is False)

# 3. a round: get ready, the packet bounces with changing speed, splices light the region
b.key("select")
check("SELECT starts a round", b.g("__screen") == "game")
gm = b.g("__game")
check("packet waits a moment before it runs", gm.t < 0)
b.key("select")
check("SELECT during get ready is ignored, not a miss", not gm.done)
check("first region of the day: one splice less (3 -> 2)", gm.need == 2)
check("the green is in the middle of the track", abs(gm.zx + gm.zw / 2 - 160) <= 1)
wait_run(b)
dirs, muls = set(), set()
for _ in range(300):
    b.tick(10)
    dirs.add(gm.dir)
    muls.add(gm.mul)
    if gm.passes >= 4:
        break
check("the packet bounces back and forth", dirs == {1, -1} and gm.passes >= 1)
check("the speed changes between passes", len(muls) >= 2)
check("the packet stays on the track", 0 <= gm.pos <= 1)
b.key("back")
b.key("select")                       # new round on the same region
lay_region(b)
check("all splices PERFECT: region lit", b.g("__count") == 1)
check("PERFECT counts as a secret", b.g("__G").sec["perfect"] is True)
check("two PERFECT in a row: DOUBLE ZERO secret", b.g("__G").sec["zero"] is True)
check("score counts splices and the region", b.g("__G").score >= 2 * 150 + 500)
check("first of the day spent", b.g("__G").day != "")
b.tick(30, 100)
check("back on the map after the region", b.g("__screen") == "home")

# 4. three lives: a miss costs one, the third ends the run and the map goes dark
b.key("select")
gm = b.g("__game")
check("second region: 3 splices", gm.need == 3)
splice(b, "miss")
check("a miss costs a life", b.g("__G").lives == 2)
b.key("select")
check("SELECT after a miss retries the region", b.g("__game").done is False)
splice(b, "miss")
b.key("select")
wait_run(b)
for _ in range(2000):                 # third: no SELECT at all, the packet times out
    if b.g("__game").done:
        break
    b.tick(10)
G = b.g("__G")
check("no SELECT for 6 passes is a miss", b.g("__game").done)
check("out of lives: map dark, lives back to 3, new run", b.g("__count") == 0 and G.lives == 3 and G.score == 0 and G.runs == 1)
check("best score kept", G.top >= 800)
b.key("select")
check("after game over SELECT does not start a round", b.g("__game").over is True)
check(f"at most 8 timers at once (peak {b.maxt})", b.maxt <= 8)
check(f"under 200k instructions per callback (peak {b.maxi})", b.maxi < 200000)

# 4b. CANCEL mid-region: splice points are paid only when the region is lit (no farming)
b12 = fresh(ws_answer=None)
b12.key("select")
score0 = b12.g("__G").score
for _ in range(5):
    splice(b12)                       # one splice, then walk away
    b12.key("back")
    b12.key("select")
check("splice, CANCEL, again: the score does not grow", b12.g("__G").score == score0 and b12.g("__G").top == score0)

# 4c. the last region of season 3 at the fastest pass: the packet never jumps over the green
b13 = fresh(ws_answer=None)
G = b13.g("__G")
G.p = "1" * 12 + "0"
G.s = 3
b13.L.globals().__start(13)
gm = b13.g("__game")
gm.mul = 0.6
L = b13.L.globals()
step = L.__track_step()
check(f"fastest pass moves {step:.1f} px per 16 ms tick, under 60% of the {gm.zw} px green", step <= gm.zw * 0.6 + 0.01)
lay_region(b13)
check("the last region of season 3 can be laid", b13.g("__count") == 13)

# 5. the whole map: party, share on X, next season
b6 = fresh(ws_answer=None)
G = b6.g("__G")
G.p = "1" * 12 + "0"
G.score = 9000
b6.key("back")                        # menu
b6.key("select")                      # next dark region
lay_region(b6)
b6.tick(30, 60)
check("13/13: the party screen", b6.g("__screen") == "party")
check("lives bonus added", b6.g("__G").score >= 9000 + 500 + 3000)
pt = b6.g("__party")
frames = set()
for _ in range(40):
    b6.tick(30)
    frames.add(pt.f)
check("the dancer dances (frames change)", len(frames) >= 3)
check("party objects shown", all(o.shown for o in pt.all.values()))
b6.key("up")
check("UP on the party: share on X", b6.g("__screen") == "share")
url = b6.g("__shareQr").txt
check("share QR is an X post with a link to the card page", url.startswith("https://x.com/intent/post?text=") and "%2Fshare%3Fs%3D" in url)
check("@doublezero once", url.count("%40doublezero") == 1)
check("share QR fits (under 260 chars)", len(url) < 260)
b6.key("back")
check("CANCEL from share: back to the party", b6.g("__screen") == "party")
b6.key("select")
check("SELECT: next season, map dark", b6.g("__G").s == 2 and b6.g("__count") == 0)

# 6. worker answers with an unknown metro and a boost: no crash, the boost is banked
b2 = Badge(ws_answer=json.dumps({"c": {"pieces": 5, "badges": 2, "done": 0}, "you": {"boost": True, "metro": "zzz", "home": "zzz", "km": 365}}))
b2.tick(30, 80)
check("unknown metro from the worker: no crash, community saved", b2.storage.get("c") is not None)
b2.tick(30, 80)
check("unknown home metro is kept", b2.g("__G").home == "zzz")
check("home toast shows the distance", any("365 km" in t for t in b2.toasts))
check("boost banked", b2.g("__G").bank == 1)
b2.key("back")
b2.tick(30, 30)
check("map still draws with an unknown home metro", b2.g("__screen") in ("home", "menu", "howto"))

# 7. a real metro: home secret, home region and the boost make the round shorter
metros = json.load(open(os.path.join(ROOT, "data/metros.json")))
b3 = fresh(ws_answer=json.dumps({"c": {"pieces": 5, "badges": 2, "done": 0}, "you": {"boost": True, "metro": "lon", "home": "lon", "km": 365}}))
b3.tick(30, 120)
G = b3.g("__G")
check("home metro stored", G.home == "lon")
check("home metro counts as a secret", G.sec["home"] is True)
if b3.g("__screen") != "home":
    b3.key("back")
b3.L.globals().__start(5)             # Western Europe: London's region
gm = b3.g("__game")
check("home + first of the day + boost: 3 -> 2 (never under 2)", gm.need == 2 and len(list(gm.used.values())) == 3)
lay_region(b3)
check("boost spent when the region is lit", b3.g("__G").bank == 0)
sent = [json.loads(m) for m in b3.sent]
check("check-in sends progress, best score and a name", sent and all(k in sent[0] for k in ("n", "s", "best", "name")))

# 8. garbage from the worker: no crash
b4 = Badge(ws_answer="{not json")
b4.tick(30, 80)
check("garbage answer: still running", b4.g("__screen") in ("howto", "home"))

# 9. leaderboard from the worker, share from the board
top = [{"n": "alice", "s": 9000}, {"n": "bob", "s": 700}]
b7 = fresh(ws_answer=json.dumps({"c": {"pieces": 5, "badges": 2, "done": 0, "top": top}}))
b7.tick(30, 40)
b7.key("back")
for _ in range(3):
    b7.key("down")
b7.key("select")
check("menu item 4 opens the leaderboard", b7.g("__screen") == "board")
rows = [r.txt for r in b7.g("__lb").values()]
check("board lists the top players", "alice" in rows[0] and "9000" in rows[0] and "bob" in rows[1])
b7.key("up")
check("UP on the board: share on X", b7.g("__screen") == "share")
b7.key("back")
check("CANCEL from share: back to the board", b7.g("__screen") == "board")
b7.key("back")
check("CANCEL from the board: menu", b7.g("__screen") == "menu")
b8 = fresh(ws_answer=None)
b8.tick(30, 300)
b8.key("back")
for _ in range(3):
    b8.key("down")
b8.key("select")
check("no board yet: a clear message", "Wi-Fi" in b8.g("__lb")[1].txt or "loading" in b8.g("__lb")[1].txt)

# 10. menu: Secrets screen, konami rickroll, exit
b5 = Badge(storage={"g": None})
b5.tick(30, 60)
b5.key("back")             # menu (the app opens on the map)
check("CANCEL opens the menu", b5.g("__screen") == "menu")
b5.key("down")
b5.key("down")
b5.key("select")
check("menu item 3 opens Secrets", b5.g("__screen") == "secrets")
b5.key("back")
check("CANCEL from Secrets goes back to the menu", b5.g("__screen") == "menu")
for k in ["up", "up", "down", "down", "left", "right"]:
    b5.key(k)
check("konami on the menu: rickroll", b5.g("__screen") == "rick")
check("rickroll counts as a secret", b5.g("__G").sec["rick"] is True)
b5.key("back")
b5.key("back")
b5.key("back")
check("menu again", b5.g("__screen") == "menu")
for _ in range(7):
    b5.key("down")
b5.key("select")
check("Exit leaves the app", b5.exited)

# 11. installs from 1.2 and older: 100 tiles become 13 regions, old keys removed
old = Badge(storage={"map": "x" * 100, "updated": 123, "g": None})
old.tick(30, 60)
check("1.0.x storage keys removed", "map" not in old.storage and "updated" not in old.storage)
b9 = Badge(storage={"g": {"p": "1" * 100, "sec": {"frenzy": True, "perfect": True}}})
b9.tick(30, 60)
check("1.2 save with all 100 tiles: 13/13 regions", b9.g("__count") == 13)
check("1.2 secret FEEDING FRENZY dropped, others kept", b9.g("__G").sec["frenzy"] is None and b9.g("__G").sec["perfect"] is True)
check("1.2 save gets 3 lives and a score", b9.g("__G").lives == 3 and b9.g("__G").score == 0)
b9b = Badge(storage={"g": {"p": "1" + "0" * 99}})
b9b.tick(30, 60)
check("1.2 save with one tile: no region lit", b9b.g("__count") == 0)

# 12. all four secrets: rainbow shark, no crash on the map
b10 = Badge(ws_answer=json.dumps({"c": {"pieces": 1, "badges": 1, "done": 0}, "you": {"home": "lon"}}))
b10.tick(30, 80)
G = b10.g("__G")
for k in ("perfect", "zero", "rick"):
    G.sec[k] = True
b10.tick(30, 200)
check("all secrets: map keeps running", b10.g("__screen") == "home")
check("all secrets toast", any("Secret" in t or "secrets" in t for t in b10.toasts))

# 13. cursor moves between regions in every direction and stays valid
b11 = fresh(ws_answer=None)
seen = set()
for k in ["right"] * 8 + ["down"] * 4 + ["left"] * 8 + ["up"] * 4 + ["right", "down"] * 6:
    b11.key(k)
    seen.add(b11.g("__cursor"))
check(f"the cursor reaches many regions ({len(seen)})", len(seen) >= 10 and all(1 <= c <= 13 for c in seen))

print("all passed" if fails == 0 else f"{fails} FAILED")
sys.exit(1 if fails else 0)
