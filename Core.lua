-- Startup, events, rewards and slash commands.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.ADDON_FOLDER = ADDON
-- The version from the .toc.
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMetadata and getMetadata(ADDON, "Version")) or "dev"

local PREFIX = "|cff66ccffDeckhand|r: "
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
  ns.Print("|cffffd100+%d card pack%s|r (%s). /deckhand packs to open.", n, n == 1 and "" or "s", why)
  if ns.UI and ns.UI.Toast then ns.UI.Toast("pack", why, n) end
  refresh()
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  DeckhandCharDB = DeckhandCharDB or {}
  ns.db = DeckhandCharDB
  ns.endedByUpdate = ns.Collection.Init(ns.db, ns.Rules.RULES_VERSION)
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.db then return end
  if ns.UI and ns.UI.Init then ns.UI.Init() end
  if ns.Travel then ns.Travel.Init() end
  if ns.endedByUpdate then
    local o = ns.OpponentById[ns.endedByUpdate]
    ns.Print("This update changed Deckhand's rules, so your match against %s was ended. It doesn't count as a win or a loss.",
      o and o.name or "the computer")
  end
  local m = ns.db.match
  local s = ns.db.stats
  if m then
    ns.Print("Your %s is waiting. Type /deckhand to continue.",
      m.tutorial and "tutorial" or ("game against " .. ns.OpponentById[m.opp].name))
  elseif not (ns.db.tutorial and ns.db.tutorial.done) and s.wins + s.losses + s.draws == 0 then
    ns.Print("New to Deckhand? Type /deckhand tutorial for a short guided match. It earns a card pack.")
  elseif ns.db.packs > 0 then
    ns.Print("You have %d unopened card pack%s. Type /deckhand to play.", ns.db.packs, ns.db.packs == 1 and "" or "s")
  end
end)

-- Prints (and toasts) a list of rewards from Collection: { packs = n } and
-- { shards = n }, each with a reason.
function ns.Announce(rewards)
  if not rewards then return end
  for _, r in ipairs(rewards) do
    if r.packs then
      ns.Print("|cffffd100+%d card pack%s|r (%s). /deckhand packs to open.", r.packs, r.packs == 1 and "" or "s", r.why)
      if ns.UI and ns.UI.Toast then ns.UI.Toast("pack", r.why, r.packs) end
    elseif r.shards then
      ns.Print("|cff9fdfff+%d shard%s|r (%s).", r.shards, r.shards == 1 and "" or "s", r.why)
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
BINDING_HEADER_DECKHAND = "Deckhand"
BINDING_NAME_DECKHAND_TOGGLE = "Show/hide Deckhand"

function Deckhand_Toggle()
  if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

local function onOff(word, current)
  word = (word or ""):lower()
  if word == "on" then return true elseif word == "off" then return false end
  return not current
end

local SETTINGS = {
  toast = { "toast", "Offer a game when a flight, boat or zeppelin ride starts" },
  land = { "hideOnLand", "Close the window when you land or dock" },
  combat = { "hideInCombat", "Close the window when combat starts" },
  portraits = { "portraits", "Creature portraits in card tooltips" },
  sound = { "sound", "Sound" },
  chatter = { "chatter", "Opponent lines during a match" },
  forecast = { "forecast", "Lane markers and Morale forecast while planning" },
  minimap = { "minimap", "Minimap button" },
}

local HELP = {
  "/deckhand - show or hide the game  (/deckhand play | cards | packs | guide | options opens a tab)",
  "/deckhand tutorial - a guided match against Flightmaster Dorn",
  "/deckhand end - end the match you're in (counts as a loss, no reward)",
  "/deckhand speed 1-3 - how fast rounds play out",
  "/deckhand scale 0.6-1.5 - window size;  /deckhand reset - window back to the middle",
  "/deckhand toast | land | combat | portraits | forecast | sound | chatter | minimap [on|off] - options (also in the Options tab)",
  "/deckhand icons - list card icons this client doesn't have (for bug reports)",
  "/deckhand travel [log] - what Deckhand sees of your travel (log: a line a second, to check boat detection)",
  "/deckhand rules - the rules (the Guide tab)",
}

SLASH_DECKHAND1 = "/deckhand"
SlashCmdList.DECKHAND = function(msg)
  if not ns.db then return end
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local S = ns.db.settings
  if cmd == "" then
    Deckhand_Toggle()
  elseif cmd == "play" or cmd == "cards" or cmd == "packs" or cmd == "options" or cmd == "guide" then
    ns.UI.Show(cmd)
  elseif cmd == "rules" then
    ns.UI.Show("guide")
  elseif cmd == "tutorial" then
    ns.UI.Show("play")
    ns.UI.Game.StartTutorial()
  elseif cmd == "end" or cmd == "concede" then
    if ns.db.match then ns.UI.Game.AskEndMatch() else ns.Print("You're not in a match.") end
  elseif cmd == "speed" then
    local n = tonumber(rest)
    if n and n >= 1 and n <= 3 then S.speed = n end
    ns.Print("Replay speed %s.", tostring(S.speed))
  elseif cmd == "scale" then
    local n = tonumber(rest)
    if n and n >= 0.6 and n <= 1.5 then
      S.scale = n
      ns.UI.ApplyScale()
    end
    ns.Print("Window scale %.2f.", S.scale)
  elseif cmd == "reset" then
    ns.UI.ResetPosition()
    ns.Print("Window moved back to the middle.")
  elseif SETTINGS[cmd] then
    local key, label = SETTINGS[cmd][1], SETTINGS[cmd][2]
    S[key] = onOff(rest, S[key])
    ns.Print("%s: %s.", label, S[key] and "on" or "off")
    if cmd == "minimap" then ns.UI.UpdateMinimapButton() end
  elseif cmd == "icons" then
    local missing = ns.UI.MissingIcons()
    if #missing == 0 then ns.Print("All card icons found.") end
    for _, line in ipairs(missing) do ns.Print(line) end
  elseif cmd == "travel" then
    ns.Travel.Report(rest:lower())
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end
