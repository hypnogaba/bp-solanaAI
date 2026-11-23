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
                       " __apply = apply; __cursor = function() return cursor end; __count = count")

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


def play_round(b, aim="centre"):
    """Press SELECT when the packet is at the green's centre (or 'miss' far from it)."""
    for _ in range(400):
        gm = b.g("__game")
        if gm is None or gm.done:
            return
        px = gm.x + 5
        centre = gm.zx + gm.zw / 2
        if aim == "centre" and gm.t >= 0 and abs(px - centre) <= 2:
            b.key("select")
            return
        b.tick(10)


# 1. first launch: splash, how to play, home
b = Badge(ws_answer=None)
b.tick(30, 60)
check("first launch shows how to play", b.g("__screen") == "howto")
for _ in range(3):
    b.key("select")
check("how to play ends on the map", b.g("__screen") == "home")

# 2. the stuck check-in clears itself (ws never answers)
check("startup check-in is loading", b.g("__loading") is True)
b.tick(30, 300)
check("watchdog: loading clears after 8 s without an answer", b.g("__loading") is False)

# 3. a round: get-ready pause, a PERFECT hit, the secret, no timer overflow
b.key("select")
check("SELECT starts a round", b.g("__screen") == "game")
check("packet waits a moment before it runs", b.g("__game").t < 0)
b.key("select")
check("SELECT during get ready is ignored, not a miss", not b.g("__game").done)
play_round(b)
check("PERFECT hit lit pieces", b.g("__count") >= 2)
check("PERFECT counts as a secret", b.g("__G").sec["perfect"] is True)
b.tick(30, 100)
check("back on the map after the round", b.g("__screen") == "home")

# 4. a streak of five with all bonuses: never more than 8 timers
for _ in range(9):
    b.key("select")
    play_round(b)
    b.tick(30, 60)
check("feeding frenzy counts as a secret", b.g("__G").sec["frenzy"] is True)
check(f"at most 8 timers at once (peak {b.maxt})", b.maxt <= 8)
check(f"under 200k instructions per callback (peak {b.maxi})", b.maxi < 200000)

# 5. hit, CANCEL, new round within 1.5 s: the old return-to-map does not cut it short
b.key("select")
play_round(b)
b.key("back")
b.g("__next")
b.tick(30, 20)  # 0.6 s: inside the new round's get-ready + run
b.tick(30, 40)
gm = b.g("__game")
check("new round is not ended by the previous round's timer", b.g("__screen") == "game" or (gm and gm.done))

# 6. worker answers with an unknown metro and a boost: no crash
b2 = Badge(ws_answer=json.dumps({"c": {"pieces": 5, "badges": 2, "done": 0}, "you": {"boost": True, "metro": "zzz", "home": "zzz"}}))
b2.tick(30, 80)
check("unknown metro from the worker: no crash, community saved", b2.storage.get("c") is not None)
b2.tick(30, 80)
check("unknown home metro is kept (homeTile copes)", b2.g("__G").home == "zzz")
b2.key("back")
b2.tick(30, 30)
check("map still draws with an unknown home metro", b2.g("__screen") in ("home", "menu", "howto"))

# 7. a real metro: home secret and boost
metros = json.load(open(os.path.join(ROOT, "data/metros.json")))
code = sorted(metros)[0]
b3 = Badge(ws_answer=json.dumps({"c": {"pieces": 5, "badges": 2, "done": 0}, "you": {"boost": True, "metro": code, "home": code}}))
b3.tick(30, 120)
check("home metro stored", b3.g("__G").home == code)
check("home metro counts as a secret", b3.g("__G").sec["home"] is True)
check("metro boost lit pieces", b3.g("__count") >= 1)

# 8. garbage from the worker: no crash
b4 = Badge(ws_answer="{not json")
b4.tick(30, 80)
check("garbage answer: still running", b4.g("__screen") in ("howto", "home"))

# 9. menu: Secrets screen, konami rickroll, exit
b5 = Badge(storage={"g": None})
b5.tick(30, 60)
b5.key("back")             # skip how to play
b5.key("back")             # menu
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
for _ in range(6):
    b5.key("down")
b5.key("select")
check("Exit leaves the app", b5.exited)

# 10. an install from 1.0.1 or a partial save: no crash, old keys removed
old = Badge(storage={"map": "x" * 100, "updated": 123,
                     "g": None})
old.tick(30, 60)
check("1.0.x storage keys removed", "map" not in old.storage and "updated" not in old.storage)
b9 = Badge(storage={"g": {"p": "1" + "0" * 99}})
b9.tick(30, 60)
check("partial save (only p) loads and keeps the piece", b9.g("__count") == 1 and b9.g("__G").hits == 0)

# 11. all four secrets: rainbow Mako, no crash on the map
b10 = Badge(ws_answer=json.dumps({"c": {"pieces": 1, "badges": 1, "done": 0}, "you": {"home": code}}))
b10.tick(30, 80)
G = b10.g("__G")
for k in ("perfect", "frenzy", "rick"):
    G.sec[k] = True
b10.key("back")
b10.tick(30, 200)
check("all secrets: map keeps running", b10.g("__screen") == "home")
check("all secrets toast", any("Secret" in t or "secrets" in t for t in b10.toasts))

print("all passed" if fails == 0 else f"{fails} FAILED")
sys.exit(1 if fails else 0)
