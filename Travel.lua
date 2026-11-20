-- Travel: offers a game when a flight or a boat / zeppelin ride starts, counts
-- the time toward packs, and closes the window when you land or dock. Also
-- closes it in combat.
--
-- Flights: on the live Forever client UnitOnTaxi has been seen to stay true
-- after landing (OneForAll's flight timer notes this), so landing is also
-- detected from speed: taxis fly at ~30 yd/s, so once we've seen that,
-- dropping below 20 means we're down. GetUnitSpeed can be a "secret" value,
-- so every comparison is guarded.
--
-- Boats and zeppelins: the client has no "on a transport" call, so a ride is
-- recognised from movement. You stand still (your own speed is 0) while your
-- position keeps moving sideways at boat speed for several seconds. Lifts go
-- up and down, so only sideways movement counts. A crossing between
-- continents has a loading screen; the jump in position is skipped. The ride
-- ends when you've stayed put for a while, or after a long run (you walked off
-- at the dock). Not yet checked in game: `/tradewinds travel log` prints what
-- the client reports every second, to check it on a real crossing.
local _, ns = ...

local T = {}
ns.Travel = T

T.RIDE_DRIFT = 3     -- yards a second you must be carried to count as riding
T.RIDE_START = 6     -- seconds of that before a ride starts
T.RIDE_STOP = 10     -- seconds without moving that end it
T.RIDE_WALK = 30     -- seconds of running yourself that end it
T.JUMP = 150         -- yards in one second: a loading screen, not movement

local flying, fast, stopped, ticker = false, false, 0, nil
local ride = { on = false, drift = 0, still = 0, walk = 0, log = false }

local function speed()
  if not GetUnitSpeed then return nil end
  local ok, s = pcall(GetUnitSpeed, "player")
  if not ok or type(s) ~= "number" then return nil end
  if issecretvalue and issecretvalue(s) then return nil end
  return s
end

-- Map position in yards (nil in instances, or if the client hides it).
local function position()
  if not UnitPosition then return nil end
  local ok, y, x, _, inst = pcall(UnitPosition, "player")
  if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
  if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end
  return x, y, inst
end

local function onTaxi()
  return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

local function addTime()
  local earned = ns.Collection.AddTravel(ns.db, 1)
  if earned > 0 then
    ns.Print(ns.L["|cffffd100%s|r for %d minutes of travel."],
      ns.Plural(earned, "+%d card pack", "+%d card packs"):format(earned), ns.Collection.TRAVEL_PACK_SECONDS / 60)
    ns.UI.Refresh()
  end
end

-- Flights ---------------------------------------------------------------------
local function arrived(what)
  ns.UI.Toast(nil)
  if ns.db.settings.hideOnLand and ns.UI.IsShown() then
    ns.UI.Hide()
    if ns.db.match or next(ns.db.games or {}) then
      ns.Print(what == "landed" and ns.L["Landed. Your games are saved: /tradewinds to pick them up again."]
        or ns.L["Docked. Your games are saved: /tradewinds to pick them up again."])
    end
  end
  ns.UI.Refresh()
end

local function landed()
  if not flying then return end
  flying = false
  if ticker then ticker:Cancel(); ticker = nil end
  arrived("landed")
end

local function tick()
  if not flying then return end
  local s = speed()
  if s then
    if s >= 20 then fast = true end
    stopped = (s == 0) and stopped + 1 or 0
  end
  if not onTaxi() or (fast and s and s < 20) or stopped >= 3 then
    landed()
    return
  end
  addTime()
end

local function takeOff()
  if flying then return end
  if ride.on then ride.on = false end -- a flight is a flight
  flying, fast, stopped = true, false, 0
  if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, tick) end
  if ns.db.settings.toast and not ns.UI.IsShown() then ns.UI.Toast("flight") end
  ns.UI.Refresh()
end

-- Boats and zeppelins -----------------------------------------------------------
local function startRide()
  ride.on, ride.still, ride.walk = true, 0, 0
  if ns.db.settings.toast and not ns.UI.IsShown() then ns.UI.Toast("boat") end
  ns.UI.Refresh()
end

local function endRide()
  ride.on, ride.drift = false, 0
  arrived("docked")
end

local function watch()
  if flying then return end
  local x, y, inst = position()
  local s = speed()
  local d
  if x and ride.x and ride.inst == inst then
    d = math.sqrt((x - ride.x) ^ 2 + (y - ride.y) ^ 2)
  end
  ride.x, ride.y, ride.inst = x, y, inst
  if ride.log then
    ns.Print("travel: speed %s, moved %s yd, %s", s and ("%.1f"):format(s) or "?", d and ("%.1f"):format(d) or "?",
      ride.on and "riding" or ("drift " .. ride.drift))
  end
  if not d or d > T.JUMP or s == nil then return end -- no reading, or a loading screen
  if not ride.on then
    if s == 0 and d >= T.RIDE_DRIFT then ride.drift = ride.drift + 1 else ride.drift = 0 end
    if ride.drift >= T.RIDE_START then startRide() end
    return
  end
  ride.still = (d < 0.5) and ride.still + 1 or 0
  ride.walk = (s > 0) and ride.walk + 1 or 0
  if ride.still >= T.RIDE_STOP or ride.walk >= T.RIDE_WALK then
    endRide()
    return
  end
  addTime()
end

function T.IsFlying() return flying end
function T.IsRiding() return ride.on end
function T.IsTravelling() return flying or ride.on end

-- /tradewinds travel [log]: what the client reports, for checking boat
-- detection in game.
function T.Report(arg)
  if arg == "log" then
    ride.log = not ride.log
    ns.Print("Travel log %s.", ride.log and "on: one line a second (/tradewinds travel log again to stop)" or "off")
    return
  end
  local x, y, inst = position()
  local s = speed()
  ns.Print("Travel: %s. Your speed %s, position %s, taxi %s.",
    flying and "flying" or ride.on and "on a boat or zeppelin" or "not travelling",
    s and ("%.1f"):format(s) or "unknown",
    x and ("%.0f, %.0f (map %s)"):format(x, y, tostring(inst)) or "unknown", onTaxi() and "yes" or "no")
end

function T.Init()
  ns.On("PLAYER_CONTROL_LOST", function()
    C_Timer.After(0.5, function() if onTaxi() then takeOff() end end)
  end)
  ns.On("PLAYER_CONTROL_GAINED", function()
    C_Timer.After(0.5, function() if flying and not onTaxi() then landed() end end)
  end)
  -- a /reload or login in the middle of a flight
  ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2, function() if onTaxi() then takeOff() end end)
  end)
  ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.db.settings.hideInCombat then ns.UI.Hide() end
  end)
  if onTaxi() then takeOff() end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, watch) end
end
