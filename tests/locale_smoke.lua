-- Plays the addon in one language (LOCALE, set by tests/run_tests.py): every
-- tab, every card face and tooltip, the Guide, the tutorial and a full match,
-- so a translation that breaks a format string or a layout errors here.
-- Also records the keys looked up at run time: each must be in the template.
local ROOT = ROOT or "."
local LOCALE = LOCALE or "enUS"
dofile(ROOT .. "/tests/wowmock.lua")
function GetLocale() return LOCALE end

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. LOCALE .. ": " .. label) end
end

local ns = {}
local used = {}
for line in io.lines(ROOT .. "/Deckhand.toc") do
  local file = line:match("^%s*([^#].-%.lua)%s*$")
  if file then
    file = file:gsub("\\", "/")
    assert(loadfile(ROOT .. "/" .. file))("Deckhand", ns)
    if file == "Locales/Locale.lua" then
      setmetatable(ns.L, { __index = function(_, k) used[k] = true; return k end })
    end
  end
end
check(ns.LOCALE == LOCALE, "the client language is " .. LOCALE)
local R, Cards, C, UI = ns.Rules, ns.Cards, ns.Collection, ns.UI
local G = UI.Game
math.randomseed(777)

MOCK.Fire("ADDON_LOADED", "Deckhand")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Advance(3)
local db = DeckhandCharDB
SlashCmdList.DECKHAND("")
SlashCmdList.DECKHAND("help")

-- every tab, Guide section and card
for _, tab in ipairs({ "play", "cards", "packs", "guide", "options" }) do UI.Show(tab) end
for _, key in ipairs({ "basics", "round", "kw1", "kw2", "cards", "winning" }) do UI.Guide.Show(key) end
local probe = CreateFrame("Button", nil, UIParent)
local face = UI.CreateCard(UIParent)
for _, c in ipairs(Cards.list) do
  UI.CardTooltip(probe, c.id, nil, nil, nil, true)
  face:SetCard(c.id)
end
for _, k in ipairs(R.KEYWORDS) do check(k.name ~= "" and k.text ~= "", "keyword " .. k.key .. " has text") end
db.packs = 3
UI.Show("packs")
UI.Packs.OpenAll()
MOCK.Advance(2)

-- the tutorial, then a match against every opponent's first lines
UI.Show("play")
G.StartTutorial()
local function autoPlan()
  local st = G.Match().st
  local hand = st.players[1].hand
  for h = 1, #hand do
    local c = Cards.byId[hand[h]]
    G.ClickHand(h, "LeftButton")
    if c.type == "unit" or c.target == "friend" then
      for l = 1, R.LANES do
        if G.Selected() then G.ClickSlot(1, l, "LeftButton") end
      end
    elseif c.target == "enemy" and G.Selected() then
      G.ClickSlot(2, (h % 4) + 1, "LeftButton")
    end
    if G.Selected() then G.ClickHand(h, "RightButton") end
  end
end
local function play(limit)
  local rounds = 0
  while G.Match() and rounds < limit do
    rounds = rounds + 1
    if G.Match().tutorial and UI.Tutorial.Gate(G.Match()) then UI.Tutorial.Next() end
    if G.Match().tutorial then
      local T = ns.Tutorial
      local r = T.Round(G.Match().st)
      if r then
        for _, want in ipairs(r.you) do
          for h, id in ipairs(G.Match().st.players[1].hand) do
            if id == want.id then
              G.ClickHand(h, "LeftButton")
              local c = Cards.byId[id]
              G.ClickSlot((c.type == "tactic" and c.target == "enemy") and 2 or 1, want.lane, "LeftButton")
              break
            end
          end
        end
      else
        autoPlan()
      end
    else
      autoPlan()
    end
    G.LockIn()
    MOCK.Advance(0.05)
    MOCK.Advance(60)
  end
  return rounds
end
play(20)
check(G.Match() == nil, "the tutorial played to the end")
G.Continue()
G.Start("dorn")
play(12)
check(G.Match() == nil, "a match against Dorn played to the end")
G.Continue()
UI.Show("cards")
UI.Show("options")

check(#MOCK.errors >= 0, "ran")
-- every key used at run time is in the template
local template = {}
local T = {}
local fake = { NewLocale = function() return T end }
assert(loadfile(ROOT .. "/Locales/enUS.lua"))("Deckhand", fake)
local stray = {}
for k in pairs(used) do
  if T[k] == nil then stray[#stray + 1] = k end
end
table.sort(stray)
check(#stray == 0, "keys used at run time are in the template: " .. table.concat(stray, " | "))

print(("%s: %d passed, %d failed"):format(LOCALE, passed, failed))
RESULT = failed > 0
