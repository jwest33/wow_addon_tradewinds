-- The Cards tab: every card (owned ones in colour), filters, and your decks.
-- Left-click a card to put it in your deck, right-click to take it out,
-- shift-click to craft a copy with shards.
local _, ns = ...
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local B = {}
UI.Binder = B

local PAGE_W = 784
local COLS, ROWS = 6, 3
local PER = COLS * ROWS
local CELL_W, CELL_H = UI.CARD_W + 6, UI.CARD_H + 16
local GRID_Y = -24
local GRID_W = COLS * CELL_W
local NAV_Y = GRID_Y - ROWS * CELL_H - 6
local FILTER_Y = NAV_Y - 30
local DECK_X = GRID_W + 8
local DECK_W = PAGE_W - DECK_X - 2
local DECK_ROWS = 20
local ROW_H = 14
local LIST_Y = -30
local CURVE_Y = LIST_Y - DECK_ROWS * ROW_H - 6
local CHART_Y = CURVE_Y - 42       -- top of the cost chart
local CHART_H = 40

local page, deckPanel, cells, deckRows = nil, nil, {}, {}
local ctl = {}
local pageNo = 1

-- ---------------------------------------------------------------------------
-- Filters: each button cycles through its choices.
-- ---------------------------------------------------------------------------
local FILTERS = {
  { key = "own", label = "Show", width = 110, choices = {
    { "all", "all cards" }, { "owned", "owned" }, { "missing", "missing" }, { "deck", "in deck" } } },
  { key = "rarity", label = "Rarity", width = 126, choices = {
    { "all", "any" }, { "common", "common" }, { "uncommon", "uncommon" }, { "rare", "rare" }, { "epic", "epic" },
    { "legendary", "legendary" } } },
  { key = "cost", label = "Cost", width = 80, choices = {
    { "all", "any" }, { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" } } },
  { key = "kind", label = "Type", width = 124, choices = {
    { "all", "any" }, { "unit", "units" }, { "tactic", "tactics" }, { "beast", "Beasts" }, { "murloc", "Murlocs" },
    { "undead", "Undead" }, { "defias", "Defias" }, { "dragonkin", "Dragonkin" } } },
}
local filter = {}   -- key -> index into choices
for _, f in ipairs(FILTERS) do filter[f.key] = 1 end

local function chosen(key)
  for _, f in ipairs(FILTERS) do
    if f.key == key then return f.choices[filter[key]][1] end
  end
end

local function passes(c)
  local own, rarity, cost, kind = chosen("own"), chosen("rarity"), chosen("cost"), chosen("kind")
  local owned = C.Owned(ns.db, c.id)
  if own == "owned" and owned == 0 then return false end
  if own == "missing" and owned >= C.MaxCopies(c.id) then return false end
  if own == "deck" and C.Count(ns.db.deck, c.id) == 0 then return false end
  if rarity ~= "all" and c.rarity ~= rarity then return false end
  if cost ~= "all" and c.cost ~= cost then return false end
  if kind == "unit" or kind == "tactic" then
    if c.type ~= kind then return false end
  elseif kind ~= "all" and c.tribe ~= kind then
    return false
  end
  return true
end

local function list()
  local out = {}
  for _, c in ipairs(Cards.collectible) do
    if passes(c) then out[#out + 1] = c end
  end
  return out
end

function B.SetFilter(key, value)
  for _, f in ipairs(FILTERS) do
    if f.key == key then
      for i, ch in ipairs(f.choices) do
        if ch[1] == value then filter[key] = i end
      end
    end
  end
  pageNo = 1
  B.Refresh()
end

function B.Shown() return list() end

-- ---------------------------------------------------------------------------
-- Cards: deck editing and crafting
-- ---------------------------------------------------------------------------
local function cellExtra(card)
  local id = card.cardId
  local owned, inDeck = C.Owned(ns.db, id), C.Count(ns.db.deck, id)
  local lines = { ("Owned %d of %d.  In your deck: %d."):format(owned, C.MaxCopies(id), inDeck) }
  if owned > 0 then lines[#lines + 1] = "|cff40ff40Left-click: add to deck.  Right-click: take one out.|r" end
  if owned < C.MaxCopies(id) then
    local cost = C.CraftCost(id)
    lines[#lines + 1] = ("%sShift-click: craft a copy for %d shards (you have %d).|r"):format(
      ns.db.shards >= cost and "|cff9fdfff" or "|cff808080", cost, ns.db.shards)
  end
  return lines
end

-- Crafting asks first.
local crafting
if StaticPopupDialogs then
  StaticPopupDialogs.DECKHAND_CRAFT = {
    text = "Craft %s for %s shards?",
    button1 = "Craft",
    button2 = "Cancel",
    OnAccept = function() B.CraftNow() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

function B.CraftNow()
  local id = crafting
  crafting = nil
  if not id then return end
  local ok, why = C.Craft(ns.db, id)
  if ok then
    ns.Print("Crafted %s for %d shards.", UI.CardName(id), why)
    UI.Sound("rare")
  else
    UI.Error(why)
  end
  UI.Refresh()
end

function B.Craft(id)
  local ok, why = C.CanCraft(ns.db, id)
  if not ok then UI.Error(why) return end
  crafting = id
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.DECKHAND_CRAFT then
    StaticPopup_Show("DECKHAND_CRAFT", Cards.byId[id].name, why)
  else
    B.CraftNow()
  end
end

local function clickCard(id, button)
  if button ~= "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
    B.Craft(id)
    return
  end
  if button == "RightButton" then
    if C.DeckRemove(ns.db, id) then UI.Sound("back") end
  else
    local ok, why = C.DeckAdd(ns.db, id)
    if ok then UI.Sound("place") else UI.Error(why) end
  end
  B.Refresh()
end

B.Click = clickCard

function B.SelectDeck(i)
  C.SelectDeck(ns.db, i)
  UI.Sound("tab")
  B.Refresh()
end

-- ---------------------------------------------------------------------------
function B.Refresh()
  if not page then return end
  local all = list()
  local pages = math.max(1, math.ceil(#all / PER))
  if pageNo > pages then pageNo = pages end
  for i = 1, PER do
    local cell = cells[i]
    local c = all[(pageNo - 1) * PER + i]
    if c then
      local owned, inDeck = C.Owned(ns.db, c.id), C.Count(ns.db.deck, c.id)
      cell.card:SetCard(c.id)
      if owned == 0 then
        cell.card.art:SetDesaturated(true)
        cell.card:SetAlpha(0.45)
        local sig = c.signature and ns.OpponentById[c.signature]
        cell.label:SetText(sig and ("|cff808080win from " .. sig.short .. "|r")
          or C.InPacks(c.id) and "|cff808080not found yet|r" or "|cff808080not in packs|r")
      else
        cell.label:SetText(("%s%d/%d|r  %s"):format(owned >= C.MaxCopies(c.id) and "|cffffd100" or "|cffffffff",
          owned, C.MaxCopies(c.id), inDeck > 0 and ("|cff40ff40" .. inDeck .. " in deck|r") or ""))
      end
      cell:Show()
    else
      cell:Hide()
    end
  end
  ctl.none:SetShown(#all == 0)
  ctl.page:SetText(("%d / %d"):format(pageNo, pages))
  ctl.prev:SetEnabled(pageNo > 1)
  ctl.next:SetEnabled(pageNo < pages)
  local have, total = 0, #Cards.collectible
  for _, c in ipairs(Cards.collectible) do
    if C.Owned(ns.db, c.id) > 0 then have = have + 1 end
  end
  ctl.progress:SetText(("Collected %d of %d cards    |cff9fdfff%d shards|r    Showing %d"):format(have, total, ns.db.shards, #all))
  for _, f in ipairs(FILTERS) do
    ctl.filters[f.key]:SetText(f.label .. ": " .. f.choices[filter[f.key]][2])
  end

  -- deck list: one row per card, cheapest first
  local counts, ids = {}, {}
  for _, id in ipairs(ns.db.deck) do
    if not counts[id] then ids[#ids + 1] = id end
    counts[id] = (counts[id] or 0) + 1
  end
  table.sort(ids, function(a, b)
    local ca, cb = Cards.byId[a], Cards.byId[b]
    if ca.cost ~= cb.cost then return ca.cost < cb.cost end
    return ca.name < cb.name
  end)
  for i = 1, DECK_ROWS do
    local r = deckRows[i]
    local id = ids[i]
    if id then
      r.id = id
      r.cost:SetText(Cards.byId[id].cost)
      r.name:SetText(UI.CardName(id))
      r.count:SetText(counts[id] > 1 and ("x" .. counts[id]) or "")
      r:Show()
    else
      r.id = nil
      r:Hide()
    end
  end
  local n = #ns.db.deck
  ctl.deckTitle:SetText(("Deck  %s%d/20|r"):format(n == 20 and "|cff40ff40" or "|cffff8040", n))
  for i, b in ipairs(ctl.slots) do
    b:SetEnabled(i ~= ns.db.deckSlot)
  end
  local curve = C.CurveCounts(ns.db.deck)
  for i, rule in ipairs(C.CURVE) do
    local met = curve[i] >= rule.min
    ctl.curve[i]:SetText(("%s%s: %d/%d|r"):format(met and "|cff40ff40" or "|cffff8040",
      rule.unit and ("Cost " .. rule.cost .. " units") or ("Cost " .. rule.cost .. " cards"), curve[i], rule.min))
  end
  -- cost chart
  local byCost, most = {}, 1
  for _, id in ipairs(ns.db.deck) do
    local cost = Cards.byId[id].cost
    byCost[cost] = (byCost[cost] or 0) + 1
    if byCost[cost] > most then most = byCost[cost] end
  end
  for cost, bar in ipairs(ctl.bars) do
    local k = byCost[cost] or 0
    bar.fill:SetHeight(math.max(1, CHART_H * k / most))
    bar.fill:SetShown(k > 0)
    bar.count:SetText(k > 0 and k or "")
  end
  local ok, why = C.CheckDeck(ns.db)
  ctl.deckNote:SetText(ok and "|cff40ff40Ready to play.|r" or ("|cffff8040" .. why .. "|r"))
end

local function deckRow(i)
  local r = CreateFrame("Button", nil, deckPanel)
  r:SetSize(DECK_W - 6, ROW_H)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, LIST_Y - (i - 1) * ROW_H)
  r.cost = UI.Text(r, 11, "OUTLINE")
  r.cost:SetPoint("LEFT", 0, 0)
  r.cost:SetWidth(13)
  r.cost:SetTextColor(0.45, 0.7, 1)
  r.name = UI.Text(r, 10)
  r.name:SetPoint("LEFT", 16, 0)
  r.name:SetPoint("RIGHT", -20, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.count = UI.Text(r, 10)
  r.count:SetPoint("RIGHT", 0, 0)
  r.count:SetTextColor(1, 0.82, 0)
  r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self)
    if self.id then
      C.DeckRemove(ns.db, self.id)
      UI.Sound("back")
      B.Refresh()
    end
  end)
  r:SetScript("OnEnter", function(self)
    if self.id then UI.CardTooltip(self, self.id, nil, nil, { "|cff40ff40Click: take one out of the deck.|r" }) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

function B.Build(parent)
  page = parent
  ctl.progress = UI.Text(page, 11)
  ctl.progress:SetPoint("TOPLEFT", 2, -5)
  ctl.progress:SetTextColor(1, 0.82, 0)

  for i = 1, PER do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local cell = CreateFrame("Frame", nil, page)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", page, "TOPLEFT", col * CELL_W, GRID_Y - row * CELL_H)
    cell.card = UI.CreateCard(cell)
    cell.card:SetPoint("TOP", 0, 0)
    cell.card.tipExtra = cellExtra
    cell.card:SetScript("OnClick", function(self, button) clickCard(self.cardId, button) end)
    cell.label = UI.Text(cell, 9)
    cell.label:SetPoint("TOP", cell.card, "BOTTOM", 0, -2)
    cells[i] = cell
  end
  ctl.none = UI.Text(page, 12)
  ctl.none:SetPoint("CENTER", page, "TOPLEFT", GRID_W / 2, GRID_Y - 120)
  ctl.none:SetText("No cards match these filters.")
  ctl.none:SetTextColor(0.6, 0.6, 0.6)

  ctl.prev = UI.Button(page, "<", 34, 22, function() pageNo = pageNo - 1; UI.Sound("pick"); B.Refresh() end)
  ctl.prev:SetPoint("TOPLEFT", page, "TOPLEFT", GRID_W / 2 - 80, NAV_Y)
  ctl.page = UI.Text(page, 12)
  ctl.page:SetPoint("TOP", page, "TOPLEFT", GRID_W / 2, NAV_Y - 5)
  ctl.next = UI.Button(page, ">", 34, 22, function() pageNo = pageNo + 1; UI.Sound("pick"); B.Refresh() end)
  ctl.next:SetPoint("TOPLEFT", page, "TOPLEFT", GRID_W / 2 + 46, NAV_Y)
  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, d)
    local pages = math.max(1, math.ceil(#list() / PER))
    pageNo = math.max(1, math.min(pages, pageNo - d))
    B.Refresh()
  end)

  -- filters
  ctl.filters = {}
  local x = 0
  for _, f in ipairs(FILTERS) do
    local b = UI.Button(page, f.label, f.width, 22)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", x, FILTER_Y)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
      local n = #f.choices
      filter[f.key] = button == "RightButton" and ((filter[f.key] - 2) % n + 1) or (filter[f.key] % n + 1)
      pageNo = 1
      UI.Sound("pick")
      B.Refresh()
    end)
    UI.SimpleTooltip(b, f.label, "Click for the next choice, right-click for the one before.")
    ctl.filters[f.key] = b
    x = x + f.width + 4
  end
  local reset = UI.Button(page, "All", 60, 22, function()
    for _, f in ipairs(FILTERS) do filter[f.key] = 1 end
    pageNo = 1
    B.Refresh()
  end)
  reset:SetPoint("TOPLEFT", page, "TOPLEFT", x, FILTER_Y)
  UI.SimpleTooltip(reset, "All", "Clear the filters and show every card.")
  local help = UI.Text(page, 10)
  help:SetPoint("TOPLEFT", page, "TOPLEFT", 2, FILTER_Y - 30)
  help:SetText("Left-click a card: add to deck.   Right-click: take out.   Shift-click: craft with shards.")
  help:SetTextColor(0.6, 0.6, 0.6)

  -- deck
  deckPanel = CreateFrame("Frame", nil, page, UI.TEMPLATE)
  deckPanel:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 5, 2)
  deckPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 2, -2)
  UI.Backdrop(deckPanel, { 0.08, 0.07, 0.05, 0.85 }, { 0.3, 0.26, 0.18 })
  ctl.deckTitle = UI.Text(deckPanel, 12)
  ctl.deckTitle:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, -7)
  ctl.slots = {}
  for i = 1, C.DECK_SLOTS do
    local b = UI.Button(deckPanel, tostring(i), 24, 20, function() B.SelectDeck(i) end)
    b:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4 - (C.DECK_SLOTS - i) * 26, -3)
    UI.SimpleTooltip(b, "Deck " .. i, "Switch to this deck. Each of your decks is saved.")
    ctl.slots[i] = b
  end
  for i = 1, DECK_ROWS do deckRows[i] = deckRow(i) end
  ctl.curve = {}
  for i = 1, #C.CURVE do
    local fs = UI.Text(deckPanel, 10)
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y - (i - 1) * 13)
    ctl.curve[i] = fs
  end
  local curveHelp = CreateFrame("Frame", nil, deckPanel)
  curveHelp:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y)
  curveHelp:SetSize(DECK_W - 6, #C.CURVE * 13)
  curveHelp:EnableMouse(true)
  UI.SimpleTooltip(curveHelp, "Deck curve",
    "Every deck needs at least 2 units costing 1, 4 cards costing 2 and 3 cards costing 3.",
    "Your draws in rounds 1-3 are picked from these (round 1: a 1-cost unit; round 2: cost 2 or less; round 3: cost 3 or less), so you always have something to play. All other draws are random.")

  -- how many cards at each cost
  ctl.bars = {}
  local barW = math.floor((DECK_W - 6) / 6)
  for cost = 1, 6 do
    local x0 = DECK_X + (cost - 1) * barW
    local fill = deckPanel:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(0.3, 0.55, 0.95, 0.9)
    fill:SetWidth(barW - 6)
    fill:SetHeight(1)
    fill:SetPoint("BOTTOMLEFT", page, "TOPLEFT", x0 + 2, CHART_Y - 12 - CHART_H)
    local count = UI.Text(deckPanel, 9)
    count:SetPoint("BOTTOM", fill, "TOP", 0, 1)
    local label = UI.Text(deckPanel, 9)
    label:SetPoint("TOP", page, "TOPLEFT", x0 + barW / 2 - 1, CHART_Y - 13 - CHART_H)
    label:SetText(cost)
    label:SetTextColor(0.45, 0.7, 1)
    ctl.bars[cost] = { fill = fill, count = count }
  end

  ctl.deckNote = UI.Text(deckPanel, 10)
  ctl.deckNote:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CHART_Y - CHART_H - 30)
  ctl.deckNote:SetWidth(DECK_W - 6)
  ctl.deckNote:SetJustifyH("LEFT")
  local starter = UI.Button(deckPanel, "Starter", 86, 22, function()
    C.ResetDeck(ns.db)
    B.Refresh()
  end)
  starter:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X - 1, 4)
  UI.SimpleTooltip(starter, "Starter deck", "Replace this deck with the 20-card starter deck.")
  local clear = UI.Button(deckPanel, "Empty", 86, 22, function()
    C.SetDeck(ns.db, {})
    B.Refresh()
  end)
  clear:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X + 89, 4)
  UI.SimpleTooltip(clear, "Empty deck", "Take every card out of this deck, to build one from scratch.")
  page:SetScript("OnShow", function() B.Refresh() end)
end
