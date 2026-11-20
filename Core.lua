-- Startup, events, rewards and slash commands.
local ADDON, ns = ...
local L, Plural = ns.L, ns.Plural
ns.ADDON = ADDON
ns.ADDON_FOLDER = ADDON
-- The version from the .toc.
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMetadata and getMetadata(ADDON, "Version")) or "dev"

local PREFIX = "|cff66ccffTradewinds|r: "
function ns.Print(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

function ns.Rand(n) return math.random(n) end
function ns.Today() return date("%Y-%m-%d") end

-- ---------------------------------------------------------------------------
-- Events. Registering an event this client doesn't have is allowed to fail.
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(frame.RegisterEvent, frame, event)
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if list then for i = 1, #list do list[i](...) end end
end)

-- ---------------------------------------------------------------------------
-- Rewards
-- ---------------------------------------------------------------------------
local function refresh()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function ns.GrantPacks(n, why)
  if not ns.db or n <= 0 then return end
  ns.db.packs = ns.db.packs + n
  ns.Print(L["|cffffd100%s|r (%s). /tradewinds packs to open."], Plural(n, "+%d card pack", "+%d card packs"):format(n), why)
  if ns.UI and ns.UI.Toast then ns.UI.Toast("pack", why, n) end
  refresh()
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  TradewindsCharDB = TradewindsCharDB or {}
  ns.db = TradewindsCharDB
  ns.endedByUpdate, ns.gamesEndedByUpdate, ns.matchDamaged = ns.Collection.Init(ns.db, ns.Rules.RULES_VERSION)
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.db then return end
  if ns.UI and ns.UI.Init then ns.UI.Init() end
  if ns.Travel then ns.Travel.Init() end
  if ns.Net then ns.Net.Init() end
  if ns.endedByUpdate or ns.matchDamaged then
    local o = ns.OpponentById[ns.endedByUpdate]
    if ns.matchDamaged then
      ns.Print(L["Your saved match against %s couldn't be read, so it was ended. It doesn't count as a win or a loss."],
        o and o.name or L["the computer"])
    else
      ns.Print(L["This update changed Tradewinds's rules, so your match against %s was ended. It doesn't count as a win or a loss."],
        o and o.name or L["the computer"])
    end
  end
  local ended = ns.gamesEndedByUpdate or 0
  if ended > 0 then
    ns.Print(Plural(ended, "%d of your games against other players couldn't carry on after this update, so it ended without a result.",
      "%d of your games against other players couldn't carry on after this update, so they ended without a result."), ended)
  end
  local m = ns.db.match
  local s = ns.db.stats
  local games = #ns.Collection.Games(ns.db)
  if games > 0 then
    local moves = ns.UI.Game.YourMoves()
    ns.Print(Plural(games, "You have %d game going against another player. Type /tradewinds to see it.",
      "You have %d games going against other players. Type /tradewinds to see them."), games)
    if moves > 0 then
      ns.Print(Plural(moves, "%d of them waits for your move.", "%d of them wait for your move."), moves)
    end
  end
  if m then
    if m.tutorial then
      ns.Print(L["Your tutorial is waiting. Type /tradewinds to continue."])
    else
      ns.Print(L["Your game against %s is waiting. Type /tradewinds to continue."], ns.OpponentById[m.opp].name)
    end
  elseif games > 0 then
    return
  elseif not (ns.db.tutorial and ns.db.tutorial.done) and s.wins + s.losses + s.draws == 0 then
    ns.Print(L["New to Tradewinds? Type /tradewinds tutorial for a short guided match. It earns a card pack."])
  elseif ns.db.packs > 0 then
    ns.Print(Plural(ns.db.packs, "You have %d unopened card pack. Type /tradewinds to play.",
      "You have %d unopened card packs. Type /tradewinds to play."), ns.db.packs)
  end
end)

-- Prints (and toasts) a list of rewards from Collection: { packs = n } and
-- { shards = n }, each with a reason.
function ns.Announce(rewards)
  if not rewards then return end
  for _, r in ipairs(rewards) do
    if r.packs then
      ns.Print(L["|cffffd100%s|r (%s). /tradewinds packs to open."], Plural(r.packs, "+%d card pack", "+%d card packs"):format(r.packs), r.why)
      if ns.UI and ns.UI.Toast then ns.UI.Toast("pack", r.why, r.packs) end
    elseif r.shards then
      ns.Print(L["|cff9fdfff%s|r (%s)."], Plural(r.shards, "+%d shard", "+%d shards"):format(r.shards), r.why)
    end
  end
  refresh()
end

ns.On("PLAYER_LEVEL_UP", function(level)
  ns.Announce(ns.Collection.LevelUp(ns.db, tonumber(level) or level))
end)

-- "New flight path discovered!" (the message is the second argument on newer
-- clients, the first on older ones)
ns.On("UI_INFO_MESSAGE", function(a, b)
  local target = ERR_NEWTAXIPATH
  if target and (a == target or b == target) then ns.Announce(ns.Collection.FlightPath(ns.db)) end
end)

-- ---------------------------------------------------------------------------
-- Slash commands, key binding, addon compartment
-- ---------------------------------------------------------------------------
BINDING_HEADER_TRADEWINDS = "Tradewinds"
BINDING_NAME_TRADEWINDS_TOGGLE = L["Show/hide Tradewinds"]

function Tradewinds_Toggle()
  if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

local function onOff(word, current)
  word = (word or ""):lower()
  if word == "on" then return true elseif word == "off" then return false end
  return not current
end

-- The commands themselves stay in English in every language.
local SETTINGS = {
  toast = { "toast", L["Offer a game when a flight, boat or zeppelin ride starts"] },
  land = { "hideOnLand", L["Close the window when you land or dock"] },
  combat = { "hideInCombat", L["Close the window when combat starts"] },
  sound = { "sound", L["Sound"] },
  chatter = { "chatter", L["Opponent lines during a match"] },
  forecast = { "forecast", L["Lane markers and Morale forecast while planning"] },
  minimap = { "minimap", L["Minimap button"] },
}

local HELP = {
  L["/tradewinds - show or hide the game  (/tradewinds play | cards | packs | guide | options opens a tab)"],
  L["/tradewinds tutorial - a guided match against Flightmaster Dorn"],
  L["/tradewinds challenge [name] - challenge another player who has Tradewinds (no name: your target)"],
  L["/tradewinds end - end the match you're in (counts as a loss, no reward)"],
  L["/tradewinds speed 1-3 - how fast rounds play out"],
  L["/tradewinds scale 0.6-1.5 - window size;  /tradewinds reset - window back to the middle"],
  L["/tradewinds toast | land | combat | forecast | sound | chatter | minimap [on|off] - options (also in the Options tab)"],
  L["/tradewinds icons - list card icons this client doesn't have (for bug reports)"],
  L["/tradewinds travel [log] - what Tradewinds sees of your travel (log: a line a second, to check boat detection)"],
  L["/tradewinds rules - the rules (the Guide tab)"],
}

SLASH_TRADEWINDS1 = "/tradewinds"
SlashCmdList.TRADEWINDS = function(msg)
  if not ns.db then return end
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local S = ns.db.settings
  if cmd == "" then
    Tradewinds_Toggle()
  elseif cmd == "play" or cmd == "cards" or cmd == "packs" or cmd == "options" or cmd == "guide" then
    ns.UI.Show(cmd)
  elseif cmd == "rules" then
    ns.UI.Show("guide")
  elseif cmd == "tutorial" then
    ns.UI.Show("play")
    ns.UI.Game.StartTutorial()
  elseif cmd == "challenge" or cmd == "duel" then
    local name = rest ~= "" and rest or (UnitIsPlayer and UnitIsPlayer("target") and UnitName("target")) or nil
    if name then
      ns.UI.Show("play")
      ns.UI.Game.Challenge(name)
    else
      ns.Print(L["Type /tradewinds challenge Name, or target the player first."])
    end
  elseif cmd == "end" or cmd == "concede" then
    if ns.UI.Game.Match() then
      ns.UI.Game.AskEndMatch()
    else
      ns.Print(L["Open the game you want to end first (Your games, on the Play tab)."])
    end
  elseif cmd == "speed" then
    local n = tonumber(rest)
    if n and n >= 1 and n <= 3 then S.speed = n end
    ns.Print(L["Replay speed %s."], tostring(S.speed))
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n >= 0.6 and n <= 1.5 then
      S.scale = n
      ns.UI.ApplyScale()
    end
    ns.Print(L["Window scale %.2f."], S.scale)
  elseif cmd == "reset" then
    ns.UI.ResetPosition()
    ns.Print(L["Window moved back to the middle."])
  elseif SETTINGS[cmd] then
    local key, label = SETTINGS[cmd][1], SETTINGS[cmd][2]
    S[key] = onOff(rest, S[key])
    ns.Print(L["%s: %s."], label, S[key] and L["on"] or L["off"])
    if cmd == "minimap" then ns.UI.UpdateMinimapButton() end
  elseif cmd == "icons" then
    local missing = ns.UI.MissingIcons()
    if #missing == 0 then ns.Print(L["All card icons found."]) end
    for _, line in ipairs(missing) do ns.Print(line) end
  elseif cmd == "travel" then
    ns.Travel.Report(rest:lower())
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end
