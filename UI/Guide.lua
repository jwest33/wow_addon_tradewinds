-- The Guide tab: every rule in one place, with a diagram for each keyword.
-- Sections down the left, one shown at a time; the tutorial can be started
-- from here too.
local _, ns = ...
local L = ns.L
local R, C = ns.Rules, ns.Collection
local UI = ns.UI

local Gd = {}
UI.Guide = Gd

local page
local sections, buttons = {}, {}
local current = "basics"
local tutorialButton

local H = "|cffffd100"   -- headings

local function heading(text) return H .. text .. "|r" end

local BASICS = table.concat({
  heading(L["The goal"]),
  L["You and your opponent each start with |cffffffff12 Morale|r. Bring theirs to 0, or have more than they do when round 8 ends."],
  "",
  heading(L["Both at once"]),
  L["Every round you both plan in secret and lock in. Then both plans are revealed together and the round plays out."],
  "",
  heading(L["Supply"]),
  L["Each round you get Supply to spend on cards: 1 in round 1, 2 in round 2, and so on up to 6. Supply you don't spend is lost. You draw a card at the start of every round. The draws in rounds 1 to 3 never cost more than that round's Supply (round 1's is always a unit), so there's always something to play."],
}, "\n")

local LANES = table.concat({
  heading(L["Lanes"]),
  L["The board has four lanes: the columns. Your units go in the bottom row, theirs in the top row. In combat each unit strikes the enemy unit straight across from it. If nothing is across from it, it strikes the enemy's |cffffffffMorale|r instead."],
  L["Put units across from theirs to block them, and in open lanes to hit their Morale. Damage on a unit stays until it dies."],
  "",
  L["While you plan, the markers between the rows show what each lane will do if your opponent plays nothing new. Hover one for the details."],
}, "\n")

local ROUND = table.concat({
  heading(L["A round, step by step"]),
  "",
  L["|cffffffff1. Start.|r Both players draw a card and get their Supply. Round start effects happen."],
  "",
  L["|cffffffff2. Plan.|r Click a card in your hand, then where it goes (or drag it there). A unit goes in one of your empty lanes. A tactic targets an enemy lane, one of your units, or nothing. Right-click a planned card to take it back. Lock In when you're ready."],
  "",
  L["|cffffffff3. Reveal.|r Both plans are shown. All the new units arrive in their lanes, then their Arrive effects happen."],
  "",
  L["|cffffffff4. Tactics.|r Each tactic goes off, the player with |cffffffffinitiative|r first (initiative swaps every round). Because tactics come after the units arrive, a tactic aimed at an empty enemy lane hits whatever was just played there."],
  "",
  L["|cffffffff5. Combat.|r Swift units strike first, all at once. Then every other unit strikes, all at once. After each of those two steps, units with no health left die and their Fallen effects happen."],
  "",
  L["|cffffffff6. End.|r Regenerate units heal, and effects that last \"this round\" wear off. If either player's Morale is 0 or less, or it was round 8, the game is over."],
  "",
  L["Your hand holds up to 7 cards. A card drawn into a full hand is lost."],
}, "\n")

local CARD_TEXT = table.concat({
  heading(L["Words on the cards"]),
  "",
  L["|cffffffffArrive:|r happens when the unit is played, once both sides' new units are on the board."],
  L["|cffffffffFallen:|r happens when the unit dies."],
  L["|cffffffffRound start:|r happens at the start of every round while the unit is on the board."],
  L["|cffffffffFrozen:|r a frozen unit doesn't strike this round."],
  "",
  heading(L["Tactics"]),
  L["A tactic is played once, then it's gone. Its type line says what it targets:"],
  L["|cffffffffTactic: enemy lane|r  pick a lane in the top row. It hits the unit there after the reveal; some tactics do something else if the lane is empty (Fireball hits Morale instead)."],
  L["|cffffffffTactic: your unit|r  pick one of your units, or a lane you're playing a unit into this round."],
  L["|cffffffffTactic|r  no target needed."],
  "",
  heading(L["Tribes"]),
  L["Beasts, Murlocs, Undead, Defias and Dragonkin. Some cards get stronger with others of their tribe beside them or in play. A card's tribe is on the line under its name, and the Cards tab can filter by tribe."],
  "",
  heading(L["Summoned units"]),
  L["Some cards bring extra units onto the board, like Hogger's Riverpaw Runts. They aren't part of any deck."],
}, "\n")

local function winningText()
  return table.concat({
    heading(L["Winning"]),
    L["The game ends at the end of a round in which a player's Morale reaches 0, or at the end of round 8. More Morale wins. If Morale is tied, the player with more units on the board wins; if that's tied too, it's a draw."],
    "",
    heading(L["The tavern circuit"]),
    L["Eight opponents, from easy to hard. Beating one opens the next. Each has three stars:"],
    L["|cffffffffVictory|r  win. Pays a card pack."],
    L["|cffffffffDecisive|r  win with at least %d more Morale than them. Pays their signature card."]:format(C.REWARD.decisive),
    L["|cffffffffRank and file|r  win with a deck that has no rare, epic or legendary cards. Pays 2 packs."],
    L["Beat the last of them and |cffffffffheroic rematches|r open: everyone again, with their best deck and sharpest play. The first heroic win against each pays a pack and their signature card, holographic."],
    "",
    heading(L["Your deck"]),
    L["Exactly %d cards, at most 2 copies of a card (1 of a legendary). It needs at least 2 units costing 1, 4 cards costing 2 and 3 cards costing 3, which is what the early draws pick from. Build decks in the Cards tab."]:format(R.DECK_SIZE),
    "",
    heading(L["Collecting"]),
    L["Packs come from travelling (flights, boats and zeppelins), levelling and winning. Shards from duplicates and games buy packs or craft the card you want. The Packs tab lists every source."],
  }, "\n")
end

local SECTIONS = {
  { key = "basics", label = L["The basics"] },
  { key = "round", label = L["A round"] },
  { key = "kw1", label = L["Keywords"] },
  { key = "kw2", label = L["More keywords"] },
  { key = "cards", label = L["Card text"] },
  { key = "winning", label = L["Winning"] },
}

local function textBlock(parent, text, width)
  local fs = UI.Text(parent, 12)
  fs:SetPoint("TOPLEFT", 0, 0)
  fs:SetWidth(width)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  fs:SetTextColor(0.85, 0.83, 0.78)
  fs:SetText(text)
  return fs
end

local function diagram(parent, key, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexture(UI.ART .. "Diagram_" .. key)
  return f
end
Gd.Diagram = diagram

-- Six keywords to a page: name, diagram, rules text.
local function keywordPage(parent, first, last)
  for i = first, last do
    local k = R.KEYWORDS[i]
    local n = i - first
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(300, 168)
    cell:SetPoint("TOPLEFT", (n % 2) * 312, -math.floor(n / 2) * 172)
    local name = UI.Text(cell, 13)
    name:SetPoint("TOPLEFT", 0, 0)
    name:SetText(k.name)
    name:SetTextColor(0.5, 0.75, 1)
    local d = diagram(cell, k.key, 208, 104)
    d:SetPoint("TOPLEFT", 0, -18)
    local t = UI.Text(cell, 11)
    t:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -4)
    t:SetWidth(296)
    t:SetJustifyH("LEFT")
    t:SetTextColor(0.85, 0.83, 0.78)
    t:SetText(k.text)
  end
end

function Gd.Show(key)
  if not sections[key] then key = "basics" end
  current = key
  for k, f in pairs(sections) do f:SetShown(k == key) end
  for k, b in pairs(buttons) do
    if k == key then
      b:SetBackdropBorderColor(1, 0.82, 0, 1)
      b.text:SetTextColor(1, 0.82, 0)
    else
      b:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
      b.text:SetTextColor(0.85, 0.85, 0.85)
    end
  end
end

function Gd.Shown() return current end

function Gd.Refresh()
  if not page then return end
  local done = ns.db.tutorial and ns.db.tutorial.done
  tutorialButton:SetText(done and L["Play the tutorial"] or (ns.Plural(C.TUTORIAL_PACKS, "Play the tutorial (+%d pack)", "Play the tutorial (+%d packs)")):format(C.TUTORIAL_PACKS))
  tutorialButton:SetEnabled(ns.db.match == nil)
  Gd.Show(current)
end

function Gd.Build(parent)
  page = parent
  local title = UI.Text(page, 14)
  title:SetPoint("TOPLEFT", 6, -4)
  title:SetText(L["Guide"])
  title:SetTextColor(1, 0.82, 0)

  local X0, Y0, CW = 176, -10, 600
  for i, s in ipairs(SECTIONS) do
    local b = CreateFrame("Button", nil, page, UI.TEMPLATE)
    b:SetSize(150, 26)
    b:SetPoint("TOPLEFT", 6, -30 - (i - 1) * 30)
    UI.Backdrop(b, { 0.12, 0.10, 0.08, 1 }, { 0.4, 0.33, 0.2 })
    b.text = UI.Text(b, 12)
    b.text:SetPoint("LEFT", 10, 0)
    b.text:SetText(s.label)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function()
      UI.Sound("tab")
      Gd.Show(s.key)
    end)
    buttons[s.key] = b

    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", page, "TOPLEFT", X0, Y0)
    f:SetSize(CW, 520)
    f:Hide()
    sections[s.key] = f
  end

  -- (anchored one below the other: translations run longer or shorter)
  local basics = textBlock(sections.basics, BASICS, CW)
  local lanes = textBlock(sections.basics, LANES, 330)
  lanes:SetPoint("TOPLEFT", basics, "BOTTOMLEFT", 0, -16)
  local d = diagram(sections.basics, "lanes", 256, 128)
  d:SetPoint("TOPLEFT", lanes, "TOPLEFT", 344, -14)
  local cap = UI.Text(sections.basics, 11)
  cap:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -6)
  cap:SetWidth(256)
  cap:SetJustifyH("LEFT")
  cap:SetTextColor(0.7, 0.7, 0.7)
  cap:SetText(L["Left: nothing across, so your unit hits their Morale. Middle: two units face each other and fight. Right: nothing of yours across, so their unit hits your Morale."])

  textBlock(sections.round, ROUND, CW)
  keywordPage(sections.kw1, 1, 6)
  keywordPage(sections.kw2, 7, #R.KEYWORDS)
  textBlock(sections.cards, CARD_TEXT, CW)
  textBlock(sections.winning, winningText(), CW)

  tutorialButton = UI.Button(page, L["Play the tutorial"], 150, 26, function() UI.Game.StartTutorial() end)
  tutorialButton:SetPoint("TOPLEFT", 6, -30 - #SECTIONS * 30 - 16)
  UI.SimpleTooltip(tutorialButton, L["Tutorial"], L["A short guided match against Flightmaster Dorn: four rounds with his help, then you finish it."],
    L["Finishing it the first time earns a card pack."])

  page:SetScript("OnShow", function() Gd.Refresh() end)
  Gd.Show(current)
end
