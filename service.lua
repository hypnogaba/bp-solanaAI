-- DZ Status background service: polls the feed once a minute and notifies the
-- owner when the network status changes or a new incident appears.
-- Started from the Alerts screen (service.start). Survives app exit and reboot.

local FEED_URL = "https://dz.ponyuk.info/badge.json"
local PERIOD_S = 60

local last = storage.get("svc_last") or { status = nil, issues = {} }
local t = PERIOD_S          -- check right away on first tick
local busy = false

local function issueKey(i) return tostring(i.code) .. ":" .. tostring(i.issue) end

local function check()
  if busy then return end
  busy = true
  http.get(FEED_URL, function(ok, res)
    busy = false
    if not ok or res.status ~= 200 then service.status("feed unreachable") return end
    local f = json.decode(res.body)
    if type(f) ~= "table" then return end

    local notes = {}
    if last.status and f.status ~= last.status then
      notes[#notes + 1] = "network " .. tostring(f.status)
    end
    local seen, fresh = {}, 0
    for _, i in ipairs(f.issues or {}) do
      local k = issueKey(i)
      seen[k] = true
      if not last.issues[k] then fresh = fresh + 1 end
    end
    if last.status and fresh > 0 then
      notes[#notes + 1] = fresh .. " new incident" .. (fresh > 1 and "s" or "")
    end

    last = { status = f.status, issues = seen }
    storage.set("svc_last", last)
    service.status(tostring(f.status) .. ", " .. tostring(f.links and f.links.healthy or "?") .. " healthy links")
    service.send({ status = f.status })

    if #notes > 0 then
      local colour = (f.status == "healthy") and 0x14F195 or ((f.status == "degraded") and 0xFFB020 or 0xFF4D4D)
      service.notify(table.concat(notes, ", "), { led = colour })
    end
  end)
end

function on_tick(ms)
  t = t + 1
  if t >= PERIOD_S then
    t = 0
    check()
  end
end

function on_stop()
  storage.set("svc_last", last)
end
