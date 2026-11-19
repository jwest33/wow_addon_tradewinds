-- The Cards tab: every card (owned ones in colour) and your deck.
-- Left-click a card to put it in your deck, right-click to take it out,
-- shift-click to craft a copy with shards.
local _, ns = ...
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local B = {}
UI.Binder = B

local COLS, ROWS = 6, 3
local PER = COLS * ROWS
local CELL_W, CELL_H = UI.CARD_W + 6, UI.CARD_H + 18
local DECK_X = COLS * CELL_W + 8
local DECK_ROWS = 20
local ROW_H = 13
local CURVE_Y = -24 - DECK_ROWS * ROW_H - 4

local page, deckPanel, cells, deckRows = nil, nil, {}, {}
local ctl = {}
local pageNo, ownedOnly = 1, false

local function list()
  local out = {}
  for _, c in ipairs(Cards.collectible) do
    if not ownedOnly or C.Owned(ns.db, c.id) > 0 then out[#out + 1] = c end
  end
  return out
end

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
    C.DeckRemove(ns.db, id)
  else
    local ok, why = C.DeckAdd(ns.db, id)
    if not ok then UI.Error(why) end
  end
  B.Refresh()
end

B.Click = clickCard

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
  ctl.page:SetText(("%d / %d"):format(pageNo, pages))
  ctl.prev:SetEnabled(pageNo > 1)
  ctl.next:SetEnabled(pageNo < pages)
  local have, total = 0, #Cards.collectible
  for _, c in ipairs(Cards.collectible) do
    if C.Owned(ns.db, c.id) > 0 then have = have + 1 end
  end
  ctl.progress:SetText(("Collected %d of %d cards    |cff9fdfff%d shards|r"):format(have, total, ns.db.shards))
  ctl.filter:SetText(ownedOnly and "Show all" or "Owned only")

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
  ctl.deckTitle:SetText(("Your deck  %s%d/20|r"):format(n == 20 and "|cff40ff40" or "|cffff8040", n))
  local counts = C.CurveCounts(ns.db.deck)
  for i, rule in ipairs(C.CURVE) do
    local met = counts[i] >= rule.min
    ctl.curve[i]:SetText(("%s%s: %d/%d|r"):format(met and "|cff40ff40" or "|cffff8040",
      rule.unit and ("Cost " .. rule.cost .. " units") or ("Cost " .. rule.cost .. " cards"), counts[i], rule.min))
  end
  local ok, why = C.CheckDeck(ns.db)
  ctl.deckNote:SetText(ok and "|cff40ff40Ready to play.|r" or ("|cffff8040" .. why .. "|r"))
end

local function deckRow(i)
  local r = CreateFrame("Button", nil, deckPanel)
  r:SetSize(544 - DECK_X - 2, ROW_H)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, -24 - (i - 1) * ROW_H)
  r.cost = UI.Text(r, 10, "OUTLINE")
  r.cost:SetPoint("LEFT", 0, 0)
  r.cost:SetWidth(12)
  r.cost:SetTextColor(0.45, 0.7, 1)
  r.name = UI.Text(r, 9)
  r.name:SetPoint("LEFT", 14, 0)
  r.name:SetPoint("RIGHT", -18, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.count = UI.Text(r, 9)
  r.count:SetPoint("RIGHT", 0, 0)
  r.count:SetTextColor(1, 0.82, 0)
  r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self)
    if self.id then
      C.DeckRemove(ns.db, self.id)
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
  ctl.progress:SetPoint("TOPLEFT", 2, -4)
  ctl.progress:SetTextColor(1, 0.82, 0)
  ctl.filter = UI.Button(page, "Owned only", 90, 20, function()
    ownedOnly = not ownedOnly
    pageNo = 1
    B.Refresh()
  end)
  ctl.filter:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 100, 0)

  for i = 1, PER do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local cell = CreateFrame("Frame", nil, page)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", page, "TOPLEFT", col * CELL_W, -26 - row * CELL_H)
    cell.card = UI.CreateCard(cell)
    cell.card:SetPoint("TOP", 0, 0)
    cell.card.tipExtra = cellExtra
    cell.card:SetScript("OnClick", function(self, button) clickCard(self.cardId, button) end)
    cell.label = UI.Text(cell, 9)
    cell.label:SetPoint("TOP", cell.card, "BOTTOM", 0, -2)
    cells[i] = cell
  end

  local navY = -26 - ROWS * CELL_H - 2
  ctl.prev = UI.Button(page, "<", 30, 20, function() pageNo = pageNo - 1; B.Refresh() end)
  ctl.prev:SetPoint("TOPLEFT", page, "TOPLEFT", COLS * CELL_W / 2 - 70, navY)
  ctl.page = UI.Text(page, 11)
  ctl.page:SetPoint("TOP", page, "TOPLEFT", COLS * CELL_W / 2, navY - 4)
  ctl.next = UI.Button(page, ">", 30, 20, function() pageNo = pageNo + 1; B.Refresh() end)
  ctl.next:SetPoint("TOPLEFT", page, "TOPLEFT", COLS * CELL_W / 2 + 40, navY)
  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, d)
    local pages = math.max(1, math.ceil(#list() / PER))
    pageNo = math.max(1, math.min(pages, pageNo - d))
    B.Refresh()
  end)

  deckPanel = CreateFrame("Frame", nil, page, UI.TEMPLATE)
  deckPanel:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 4, 2)
  deckPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 2, -2)
  UI.Backdrop(deckPanel, { 0.08, 0.07, 0.05, 0.85 }, { 0.3, 0.26, 0.18 })
  ctl.deckTitle = UI.Text(deckPanel, 11)
  ctl.deckTitle:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, -4)
  for i = 1, DECK_ROWS do deckRows[i] = deckRow(i) end
  ctl.curve = {}
  for i = 1, #C.CURVE do
    local fs = UI.Text(deckPanel, 9)
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y - (i - 1) * 12)
    ctl.curve[i] = fs
  end
  local curveHelp = CreateFrame("Frame", nil, deckPanel)
  curveHelp:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y)
  curveHelp:SetSize(544 - DECK_X - 4, #C.CURVE * 12)
  curveHelp:EnableMouse(true)
  UI.SimpleTooltip(curveHelp, "Deck curve",
    "Every deck needs at least 2 units costing 1, 4 cards costing 2 and 3 cards costing 3.",
    "Your draws in rounds 1-3 are picked from these (round 1: a 1-cost unit; round 2: cost 2 or less; round 3: cost 3 or less), so you always have something to play. All other draws are random.")
  ctl.deckNote = UI.Text(deckPanel, 9)
  ctl.deckNote:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y - #C.CURVE * 12 - 4)
  ctl.deckNote:SetWidth(544 - DECK_X - 4)
  ctl.deckNote:SetJustifyH("LEFT")
  local starter = UI.Button(deckPanel, "Starter", 51, 20, function()
    C.ResetDeck(ns.db)
    B.Refresh()
  end)
  starter:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X - 1, 2)
  UI.SimpleTooltip(starter, "Starter deck", "Replace your deck with the 20-card starter deck.")
  local clear = UI.Button(deckPanel, "Empty", 51, 20, function()
    ns.db.deck = {}
    B.Refresh()
  end)
  clear:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X + 52, 2)
  UI.SimpleTooltip(clear, "Empty deck", "Take every card out of your deck, to build one from scratch.")
  page:SetScript("OnShow", function() B.Refresh() end)
end
