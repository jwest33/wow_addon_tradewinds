-- Flights: offers a game when a taxi flight starts, counts flight time toward
-- packs, and closes the window when you land. Also closes it in combat.
--
-- On the live Forever client UnitOnTaxi has been seen to stay true after
-- landing (OneForAll's flight timer notes this), so landing is also detected
-- from speed: taxis fly at ~30 yd/s, so once we've seen that, dropping below
-- 20 means we're down. GetUnitSpeed can be a "secret" value, so every
-- comparison is guarded.
local _, ns = ...

local T = {}
ns.Travel = T

local flying, fast, stopped, ticker = false, false, 0, nil

local function speed()
  if not GetUnitSpeed then return nil end
  local ok, s = pcall(GetUnitSpeed, "player")
  if not ok or type(s) ~= "number" then return nil end
  if issecretvalue and issecretvalue(s) then return nil end
  return s
end

local function onTaxi()
  return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

local function landed()
  if not flying then return end
  flying = false
  if ticker then ticker:Cancel(); ticker = nil end
  ns.UI.Toast(nil)
  if ns.db.settings.hideOnLand and ns.UI.IsShown() then
    ns.UI.Hide()
    if ns.db.match then ns.Print("Landed. Your game is saved: /deckhand to pick it up again.") end
  end
  ns.UI.Refresh()
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
  local earned = ns.Collection.AddTravel(ns.db, 1)
  if earned > 0 then
    ns.Print("|cffffd100+%d card pack|r for %d minutes in the air.", earned, ns.Collection.TRAVEL_PACK_SECONDS / 60)
    ns.UI.Refresh()
  end
end

local function takeOff()
  if flying then return end
  flying, fast, stopped = true, false, 0
  if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, tick) end
  if ns.db.settings.toast and not ns.UI.IsShown() then ns.UI.Toast("flight") end
  ns.UI.Refresh()
end

function T.IsFlying() return flying end

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
end
