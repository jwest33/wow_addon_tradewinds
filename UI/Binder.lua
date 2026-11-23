-- The Cards tab: every card (owned ones in colour), filters, and your decks.
-- Left-click a card to put it in your deck, right-click to take it out,
-- shift-click to craft a copy with shards. While a trade is open, the trade
-- (UI/Trading.lua) takes the deck panel's place and a click offers the card.
local _, ns = ...
local L = ns.L
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local B = {}
UI.Binder = B

local PAGE_W = 784
local COLS, ROWS = 5, 3
local PER = COLS * ROWS
local CARD_SCALE = 0.94
local CELL_W, CELL_H = math.floor(UI.CARD_W * CARD_SCALE + 6), math.ceil(UI.CARD_H * CARD_SCALE + 13)
local GRID_Y = -26
local GRID_W = COLS * CELL_W
local NAV_W = 112   -- the page buttons, top right of the grid
local FILTER_Y = GRID_Y - ROWS * CELL_H - 4
local DECK_X = GRID_W + 8
local DECK_W = PAGE_W - DECK_X - 2
-- The deck panel, top to bottom: the title and a bar filling up to 20
-- cards; the list (a strip per card); units, tactics and average cost; the
-- curve rules; the cost chart; whether the deck is ready; two buttons.
local DECK_ROWS = 20
local ROW_H = 15
local LIST_Y = -36
local STATS_Y = LIST_Y - DECK_ROWS * ROW_H - 6
local CHIP_H = 15
local CURVE_Y = STATS_Y - 18
local CHART_Y = CURVE_Y - 3 * CHIP_H - 6    -- top of the cost chart (the counts over the bars)
local CHART_H = 46                          -- the tallest bar
local CHART_BASE = CHART_Y - 12 - CHART_H   -- the bars stand on this line
local NOTE_Y = CHART_BASE - 20
local NOTE_H = 28
-- the chart's colours, also the swatches beside the unit and tactic counts
local UNIT_COL = { 0.88, 0.62, 0.26 }
local TACTIC_COL = { 0.62, 0.5, 1 }
-- the list's strips: bronze for units, indigo for tactics (like the cards)
local ROW_BG = { unit = { 0.30, 0.21, 0.13, 0.95 }, tactic = { 0.20, 0.17, 0.38, 0.95 } }
local MET_BG, UNMET_BG = { 0.10, 0.30, 0.10, 0.9 }, { 0.42, 0.19, 0.05, 0.9 }
local TICK = { "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\Buttons\\UI-CheckBox-Check" }
local CROSS = { "Interface\\RaidFrame\\ReadyCheck-NotReady", "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }

local page, deckPanel, cells, deckRows = nil, nil, {}, {}
local ctl = {}
local topRow = 0   -- the first row of cards shown: the wheel moves a row, the arrows a page

-- ---------------------------------------------------------------------------
-- Filters: each button cycles through its choices.
-- ---------------------------------------------------------------------------
local TRIBE_CHOICES = { { "all", L["any"] } }
for _, t in ipairs(Cards.TRIBE_ORDER) do TRIBE_CHOICES[#TRIBE_CHOICES + 1] = { t, Cards.TRIBES[t] } end

local FILTERS = {
  { key = "own", label = L["Show"], width = 100, choices = {
    { "all", L["all cards"] }, { "owned", L["owned"] }, { "missing", L["missing"] }, { "deck", L["in deck"] } } },
  { key = "rarity", label = L["Rarity"], width = 110, choices = {
    { "all", L["any"] }, { "common", L["common"] }, { "uncommon", L["uncommon"] }, { "rare", L["rare"] }, { "epic", L["epic"] },
    { "legendary", L["legendary"] } } },
  { key = "cost", label = L["Cost"], width = 66, choices = {
    { "all", L["any"] }, { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" } } },
  { key = "kind", label = L["Type"], width = 104, choices = {
    { "all", L["any"] }, { "unit", L["units"] }, { "tactic", L["tactics"] }, { "item", L["items"] } } },
  { key = "tribe", label = L["Tribe"], width = 116, choices = TRIBE_CHOICES },
}
local FILTER_GAP = 3
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
  if kind == "unit" and c.type ~= "unit" then return false end
  if kind == "tactic" and not (c.type == "tactic" and not c.item) then return false end
  if kind == "item" and not c.item then return false end
  local tribe = chosen("tribe")
  if tribe ~= "all" and c.tribe ~= tribe then return false end
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
  topRow = 0
  B.Refresh()
end

function B.Shown() return list() end
function B.Progress() return ctl.progress and ctl.progress:GetText() or "" end

-- The last row the grid can start at, for n cards.
local function lastTop(n)
  return math.max(0, math.ceil(n / COLS) - ROWS)
end

-- Scrolls the grid by d rows (positive: further down the list).
function B.Scroll(d)
  topRow = math.max(0, math.min(lastTop(#list()), topRow + d))
  B.Refresh()
end
function B.TopRow() return topRow end

-- What the deck panel says (for the tests).
function B.DeckView()
  return { count = ctl.deckCount:GetText(), units = ctl.stats.unit:GetText(), tactics = ctl.stats.tactic:GetText(),
    note = ctl.deckNote.text:GetText(), rows = (function()
      local n = 0
      for _, r in ipairs(deckRows) do if r:IsShown() then n = n + 1 end end
      return n
    end)() }
end

-- ---------------------------------------------------------------------------
-- Cards: deck editing and crafting
-- ---------------------------------------------------------------------------
local function cellExtra(card)
  local id = card.cardId
  if ns.Trade.Current() then return UI.Trading.CellExtra(id) end
  local owned, inDeck = C.Owned(ns.db, id), C.Count(ns.db.deck, id)
  local lines = { L["Owned %d of %d.  In your deck: %d."]:format(owned, C.MaxCopies(id), inDeck) }
  if owned > 0 then lines[#lines + 1] = "|cff40ff40" .. L["Left-click: add to deck.  Right-click: take one out."] .. "|r" end
  if owned < C.MaxCopies(id) then
    local cost = C.CraftCost(id)
    lines[#lines + 1] = (ns.db.shards >= cost and "|cff9fdfff" or "|cff808080")
      .. L["Shift-click: craft a copy for %d shards (you have %d)."]:format(cost, ns.db.shards) .. "|r"
  end
  return lines
end

-- Crafting asks first.
local crafting
if StaticPopupDialogs then
  StaticPopupDialogs.TRADEWINDS_CRAFT = {
    text = L["Craft %s for %s shards?"],
    button1 = L["Craft"],
    button2 = CANCEL or L["Cancel"],
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
    ns.Print(L["Crafted %s for %d shards."], UI.CardName(id), why)
    UI.Sound("rare")
    ns.CheckMilestones()
  else
    UI.Error(why)
  end
  UI.Refresh()
end

function B.Craft(id)
  local ok, why = C.CanCraft(ns.db, id)
  if not ok then UI.Error(why) return end
  crafting = id
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.TRADEWINDS_CRAFT then
    StaticPopup_Show("TRADEWINDS_CRAFT", Cards.byId[id].name, why)
  else
    B.CraftNow()
  end
end

local function clickCard(id, button)
  if ns.Trade.Current() then
    UI.Trading.Click(id, button)
    UI.Refresh()
    return
  end
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
  local trading = ns.Trade.Current() ~= nil
  local all = list()
  local last = lastTop(#all)
  if topRow > last then topRow = last end
  for i = 1, PER do
    local cell = cells[i]
    local c = all[topRow * COLS + i]
    if c then
      local owned, inDeck = C.Owned(ns.db, c.id), C.Count(ns.db.deck, c.id)
      cell.card:SetCard(c.id, nil, nil, C.IsHolo(ns.db, c.id))
      if owned == 0 then
        cell.card.art:SetDesaturated(true)
        cell.card:SetAlpha(0.45)
        local sig = c.signature and ns.OpponentById[c.signature]
        cell.label:SetText("|cff808080" .. (sig and L["win from %s"]:format(sig.short)
          or C.InPacks(c.id) and L["not found yet"] or L["not in packs"]) .. "|r")
      elseif trading then
        cell.label:SetText(UI.Trading.CellLabel(c.id))
      else
        cell.label:SetText(("%s%d/%d|r  %s"):format(owned >= C.MaxCopies(c.id) and "|cffffd100" or "|cffffffff",
          owned, C.MaxCopies(c.id), inDeck > 0 and ("|cff40ff40" .. L["%d in deck"]:format(inDeck) .. "|r") or ""))
      end
      cell:Show()
    else
      cell:Hide()
    end
  end
  ctl.none:SetShown(#all == 0)
  local pages = math.max(1, math.ceil(math.ceil(#all / COLS) / ROWS))
  ctl.page:SetText(("%d / %d"):format(topRow >= last and pages or math.floor(topRow / ROWS) + 1, pages))
  ctl.prev:SetEnabled(topRow > 0)
  ctl.next:SetEnabled(topRow < last)
  local have, total, holo = 0, #Cards.collectible, 0
  for _, c in ipairs(Cards.collectible) do
    if C.Owned(ns.db, c.id) > 0 then have = have + 1 end
    if C.IsHolo(ns.db, c.id) then holo = holo + 1 end
  end
  local tribe = chosen("tribe")
  local collected
  if tribe ~= "all" then
    local th, tt = C.TribeProgress(ns.db, tribe)
    collected = L["%s: collected %d of %d"]:format(Cards.TRIBES[tribe], th, tt) .. (th == tt and " |cffff9933*|r" or "")
  else
    collected = L["Collected %d of %d cards"]:format(have, total)
  end
  UI.FitText(ctl.progress, collected
    .. (holo > 0 and ("  (" .. L["%d %s"]:format(holo, UI.Rainbow(L["holographic"])) .. ")") or "")
    .. "    |cff9fdfff" .. ns.Plural(ns.db.shards, "%d shard", "%d shards"):format(ns.db.shards) .. "|r    "
    .. L["Showing %d"]:format(#all))
  for _, f in ipairs(FILTERS) do
    ctl.filters[f.key]:SetText(L["%s: %s"]:format(f.label, f.choices[filter[f.key]][2]))
  end
  UI.FitText(ctl.help, trading and L["Left-click a card: offer it.   Right-click: take it back.   Shift-click: offer your holographic copy."]
    or L["Left-click a card: add to deck.   Right-click: take out.   Shift-click: craft with shards."], 8)
  deckPanel:SetShown(not trading)
  UI.Trading.Refresh()
  ctl.trade:SetText(ns.Trade.Outgoing() and (CANCEL or L["Cancel"]) or L["Trade"])

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
      local c = Cards.byId[id]
      local bg = ROW_BG[c.type] or ROW_BG.unit
      r.id = id
      r.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
      r.cost:SetText(c.cost)
      r.icon:SetTexture(UI.CardIcon(id))
      r.name:SetText(UI.CardName(id))
      r.count:SetText(counts[id] > 1 and ("x" .. counts[id]) or "")
      r:Show()
    else
      r.id = nil
      r:Hide()
    end
  end
  local n, size = #ns.db.deck, ns.Rules.DECK_SIZE
  ctl.deckCount:SetText(("%d/%d"):format(n, size))
  if n == size then ctl.deckCount:SetTextColor(0.3, 1, 0.3) else ctl.deckCount:SetTextColor(1, 0.55, 0.2) end
  ctl.fill:SetValue(math.min(n, size))
  if n == size then ctl.fill:SetStatusBarColor(0.25, 0.8, 0.25) else ctl.fill:SetStatusBarColor(1, 0.6, 0.15) end
  for i, b in ipairs(ctl.slots) do
    b:SetEnabled(i ~= ns.db.deckSlot)
  end

  -- units, tactics, average cost; the bars of the chart
  local units, tactics, spent = {}, {}, 0
  for _, id in ipairs(ns.db.deck) do
    local c = Cards.byId[id]
    local t = c.type == "unit" and units or tactics
    t[c.cost] = (t[c.cost] or 0) + 1
    spent = spent + c.cost
  end
  local nu, nt, most = 0, 0, 4
  for cost = 1, 6 do
    nu, nt = nu + (units[cost] or 0), nt + (tactics[cost] or 0)
    most = math.max(most, (units[cost] or 0) + (tactics[cost] or 0))
  end
  ctl.stats.unit:SetText(ns.Plural(nu, "%d unit", "%d units"):format(nu))
  ctl.stats.tactic:SetText(ns.Plural(nt, "%d tactic", "%d tactics"):format(nt))
  UI.FitText(ctl.avg, n > 0 and L["Avg. cost %s"]:format(("%.1f"):format(spent / n)) or "", 8)
  local per = CHART_H / most
  for cost, bar in ipairs(ctl.bars) do
    local u, t = units[cost] or 0, tactics[cost] or 0
    bar.unit:SetHeight(math.max(1, u * per))
    bar.unit:SetShown(u > 0)
    bar.tactic:ClearAllPoints()
    bar.tactic:SetPoint("BOTTOMLEFT", page, "TOPLEFT", bar.x, CHART_BASE + u * per)
    bar.tactic:SetHeight(math.max(1, t * per))
    bar.tactic:SetShown(t > 0)
    bar.cap:ClearAllPoints()
    bar.cap:SetPoint("TOPLEFT", page, "TOPLEFT", bar.x, CHART_BASE + (u + t) * per)
    bar.cap:SetShown(u + t > 0)
    bar.count:ClearAllPoints()
    bar.count:SetPoint("BOTTOM", page, "TOPLEFT", bar.cx, CHART_BASE + (u + t) * per + 2)
    bar.count:SetText(u + t > 0 and (u + t) or "")
    bar.min:Hide()
  end

  -- the curve rules: a green chip when met, orange when not, and the same
  -- colour on the chart as a line the bar has to reach
  local curve = C.CurveCounts(ns.db.deck)
  for i, rule in ipairs(C.CURVE) do
    local met = curve[i] >= rule.min
    local chip, bg = ctl.curve[i], met and MET_BG or UNMET_BG
    chip.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
    chip.mark:SetTexture(UI.Icon(met and TICK or CROSS))
    chip.count:SetText(("%d/%d"):format(curve[i], rule.min))
    if met then chip.count:SetTextColor(0.55, 1, 0.55) else chip.count:SetTextColor(1, 0.7, 0.35) end
    local bar = ctl.bars[rule.cost]
    if bar then
      bar.min:ClearAllPoints()
      bar.min:SetPoint("LEFT", page, "TOPLEFT", bar.x - 3, CHART_BASE + rule.min * per)
      if met then bar.min:SetColorTexture(0.4, 1, 0.4, 0.9) else bar.min:SetColorTexture(1, 0.55, 0.2, 1) end
      bar.min:Show()
    end
  end

  local ok, why = C.CheckDeck(ns.db)
  local note, bg = ctl.deckNote, ok and MET_BG or UNMET_BG
  note.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
  note.mark:SetTexture(UI.Icon(ok and TICK or CROSS))
  if ok then note.text:SetTextColor(0.6, 1, 0.6) else note.text:SetTextColor(1, 0.75, 0.45) end
  UI.FitText(note.text, ok and L["Ready to play."] or why, 8)
end

local function deckRow(i)
  local r = CreateFrame("Button", nil, deckPanel)
  r:SetSize(DECK_W - 4, ROW_H - 1)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 1, LIST_Y - (i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetTexture(UI.ART .. "Pill")
  r.gem = r:CreateTexture(nil, "ARTWORK")
  r.gem:SetTexture(UI.ART .. "StatCost")
  r.gem:SetSize(17, 17)
  r.gem:SetPoint("LEFT", -3, 0)
  r.cost = UI.Text(r, 10, "OUTLINE")
  r.cost:SetPoint("CENTER", r.gem, "CENTER", 0, 0.5)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 3, ROW_H - 3)
  r.icon:SetPoint("LEFT", 16, 0)
  r.icon:SetTexCoord(unpack(UI.ICON_COORDS))
  r.name = UI.Text(r, 10)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetPoint("RIGHT", -24, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.count = UI.Text(r, 10, "OUTLINE")
  r.count:SetPoint("RIGHT", -7, 0)
  r.count:SetTextColor(1, 0.82, 0)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetTexture(UI.ART .. "Pill")
  r.hl:SetBlendMode("ADD")
  r.hl:SetVertexColor(1, 0.85, 0.45, 0.25)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self)
    if self.id then
      C.DeckRemove(ns.db, self.id)
      UI.Sound("back")
      B.Refresh()
    end
  end)
  r:SetScript("OnEnter", function(self)
    if self.id then UI.CardTooltip(self, self.id, nil, nil, { "|cff40ff40" .. L["Click: take one out of the deck."] .. "|r" }) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

-- A coloured strip with a tick or a cross and some text (curve rules, the
-- deck's status).
local function chip(w, h, y, size)
  local f = CreateFrame("Frame", nil, deckPanel)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 1, y)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetTexture(UI.ART .. "Pill")
  f.mark = f:CreateTexture(nil, "ARTWORK")
  f.mark:SetSize(size, size)
  f.mark:SetPoint("LEFT", 5, 0)
  return f
end

function B.Build(parent)
  page = parent
  ctl.progress = UI.Text(page, 11)
  ctl.progress:SetPoint("TOPLEFT", 2, -5)
  ctl.progress:SetWidth(GRID_W - NAV_W - 8)
  ctl.progress:SetJustifyH("LEFT")
  ctl.progress:SetWordWrap(false)
  ctl.progress:SetTextColor(1, 0.82, 0)

  for i = 1, PER do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local cell = CreateFrame("Frame", nil, page)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", page, "TOPLEFT", col * CELL_W, GRID_Y - row * CELL_H)
    cell.card = UI.CreateCard(cell)
    cell.card:SetBaseScale(CARD_SCALE)
    cell.card:SetPoint("TOP", 0, 0)
    cell.card.tipExtra = cellExtra
    cell.card:SetScript("OnClick", function(self, button) clickCard(self.cardId, button) end)
    cell.label = UI.Text(cell, 9)
    cell.label:SetPoint("TOP", cell.card, "BOTTOM", 0, -2)
    cells[i] = cell
  end
  ctl.none = UI.Text(page, 12)
  ctl.none:SetPoint("CENTER", page, "TOPLEFT", GRID_W / 2, GRID_Y - 120)
  ctl.none:SetText(L["No cards match these filters."])
  ctl.none:SetTextColor(0.6, 0.6, 0.6)

  ctl.prev = UI.Button(page, "<", 34, 22, function() UI.Sound("pick"); B.Scroll(-ROWS) end)
  ctl.prev:SetPoint("TOPLEFT", page, "TOPLEFT", GRID_W - NAV_W, -1)
  ctl.page = UI.Text(page, 12)
  ctl.page:SetPoint("TOP", page, "TOPLEFT", GRID_W - NAV_W / 2, -6)
  ctl.next = UI.Button(page, ">", 34, 22, function() UI.Sound("pick"); B.Scroll(ROWS) end)
  ctl.next:SetPoint("TOPLEFT", page, "TOPLEFT", GRID_W - 34, -1)
  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, d) B.Scroll(-d) end)   -- a row a notch

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
      topRow = 0
      UI.Sound("pick")
      B.Refresh()
    end)
    if f.key == "tribe" then
      -- every tribe's progress, and what collecting one pays
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Tribe"])
        GameTooltip:AddLine(L["Click for the next choice, right-click for the one before."], 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        for _, t in ipairs(Cards.TRIBE_ORDER) do
          local have, total = C.TribeProgress(ns.db, t)
          local done = have == total
          GameTooltip:AddDoubleLine(Cards.TRIBES[t], ("%d / %d"):format(have, total), 1, 1, 1,
            done and 1 or 0.85, done and 0.6 or 0.85, done and 0.2 or 0.85)
        end
        GameTooltip:AddLine(L["One of every card of a tribe earns a Windfall pack."], 1, 0.6, 0.2, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
      UI.SimpleTooltip(b, f.label, L["Click for the next choice, right-click for the one before."])
    end
    ctl.filters[f.key] = b
    x = x + f.width + FILTER_GAP
  end
  local reset = UI.Button(page, L["All"], 40, 22, function()
    for _, f in ipairs(FILTERS) do filter[f.key] = 1 end
    topRow = 0
    B.Refresh()
  end)
  reset:SetPoint("TOPLEFT", page, "TOPLEFT", x, FILTER_Y)
  UI.SimpleTooltip(reset, L["All"], L["Clear the filters and show every card."])
  local help = UI.Text(page, 10)
  help:SetPoint("TOPLEFT", page, "TOPLEFT", 2, FILTER_Y - 28)
  help:SetWidth(GRID_W - 4)
  help:SetJustifyH("LEFT")
  help:SetWordWrap(false)
  help:SetTextColor(0.6, 0.6, 0.6)
  ctl.help = help

  -- deck
  deckPanel = CreateFrame("Frame", nil, page, UI.TEMPLATE)
  deckPanel:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X - 5, 2)
  deckPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 2, -2)
  UI.Backdrop(deckPanel, { 0.08, 0.07, 0.05, 0.85 }, { 0.3, 0.26, 0.18 })
  ctl.deckTitle = UI.Text(deckPanel, 13)
  ctl.deckTitle:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, -8)
  ctl.deckTitle:SetText(L["Deck"])
  ctl.deckTitle:SetTextColor(1, 0.82, 0)
  ctl.deckCount = UI.Text(deckPanel, 15, "OUTLINE")
  ctl.deckCount:SetPoint("BOTTOMLEFT", ctl.deckTitle, "BOTTOMRIGHT", 7, -1)
  ctl.slots = {}
  for i = 1, C.DECK_SLOTS do
    local b = UI.Button(deckPanel, tostring(i), 24, 20, function() B.SelectDeck(i) end)
    b:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4 - (C.DECK_SLOTS - i) * 26, -3)
    UI.SimpleTooltip(b, L["Deck %d"]:format(i), L["Switch to this deck. Each of your decks is saved."])
    ctl.slots[i] = b
  end
  -- fills up to the deck's 20 cards
  local fill = CreateFrame("StatusBar", nil, deckPanel, UI.TEMPLATE)
  fill:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, -27)
  fill:SetSize(DECK_W - 6, 5)
  fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  fill:SetMinMaxValues(0, ns.Rules.DECK_SIZE)
  UI.Backdrop(fill, { 0, 0, 0, 0.7 }, { 0.3, 0.26, 0.18 })
  ctl.fill = fill
  for i = 1, DECK_ROWS do deckRows[i] = deckRow(i) end

  -- units, tactics (a swatch in their chart colour) and the average cost
  ctl.stats = {}
  for i, kind in ipairs({ "unit", "tactic" }) do
    local col = kind == "unit" and UNIT_COL or TACTIC_COL
    local sw = deckPanel:CreateTexture(nil, "ARTWORK")
    sw:SetColorTexture(col[1], col[2], col[3])
    sw:SetSize(9, 9)
    sw:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X + 1 + (i - 1) * 70, STATS_Y - 2)
    local fs = UI.Text(deckPanel, 10)
    fs:SetPoint("LEFT", sw, "RIGHT", 4, 0)
    fs:SetTextColor(0.9, 0.9, 0.9)
    ctl.stats[kind] = fs
  end
  ctl.avg = UI.Text(deckPanel, 10)
  ctl.avg:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, STATS_Y)
  ctl.avg:SetWidth(76)
  ctl.avg:SetJustifyH("RIGHT")
  ctl.avg:SetWordWrap(false)
  ctl.avg:SetTextColor(0.45, 0.7, 1)

  -- the curve rules
  ctl.curve = {}
  for i, rule in ipairs(C.CURVE) do
    local f = chip(DECK_W - 4, CHIP_H - 1, CURVE_Y - (i - 1) * CHIP_H, 12)
    f.label = UI.Text(f, 10)
    f.label:SetPoint("LEFT", f.mark, "RIGHT", 4, 0)
    f.label:SetPoint("RIGHT", -40, 0)
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)
    UI.FitText(f.label, rule.label, 8)
    f.label:SetTextColor(0.95, 0.92, 0.85)
    f.count = UI.Text(f, 10, "OUTLINE")
    f.count:SetPoint("RIGHT", -7, 0)
    ctl.curve[i] = f
  end
  local curveHelp = CreateFrame("Frame", nil, deckPanel)
  curveHelp:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CURVE_Y)
  curveHelp:SetSize(DECK_W - 6, #C.CURVE * CHIP_H)
  curveHelp:EnableMouse(true)
  UI.SimpleTooltip(curveHelp, L["Deck curve"],
    L["Every deck needs at least 2 units costing 1, 4 cards costing 2 and 3 cards costing 3."],
    L["Your draws in rounds 1-3 are picked from these (round 1: a 1-cost unit; round 2: cost 2 or less; round 3: cost 3 or less), so you always have something to play. All other draws are random."])

  -- how many cards at each cost: units under tactics, the count on top, the
  -- cost in a gem underneath, and a line where a curve rule's minimum is
  ctl.bars = {}
  local colW = math.floor((DECK_W - 6) / 6)
  local ground = deckPanel:CreateTexture(nil, "ARTWORK")
  ground:SetColorTexture(0.55, 0.45, 0.25, 0.9)
  ground:SetSize(colW * 6, 1)
  ground:SetPoint("TOPLEFT", page, "TOPLEFT", DECK_X, CHART_BASE)
  for cost = 1, 6 do
    local bar = { x = DECK_X + (cost - 1) * colW + 6, cx = DECK_X + (cost - 0.5) * colW }
    local bw = colW - 12
    bar.unit = deckPanel:CreateTexture(nil, "ARTWORK")
    bar.unit:SetColorTexture(UNIT_COL[1], UNIT_COL[2], UNIT_COL[3])
    bar.unit:SetWidth(bw)
    bar.unit:SetPoint("BOTTOMLEFT", page, "TOPLEFT", bar.x, CHART_BASE)
    bar.tactic = deckPanel:CreateTexture(nil, "ARTWORK")
    bar.tactic:SetColorTexture(TACTIC_COL[1], TACTIC_COL[2], TACTIC_COL[3])
    bar.tactic:SetWidth(bw)
    bar.cap = deckPanel:CreateTexture(nil, "ARTWORK", nil, 1)   -- a light edge on top
    bar.cap:SetColorTexture(1, 1, 1, 0.45)
    bar.cap:SetSize(bw, 2)
    bar.min = deckPanel:CreateTexture(nil, "OVERLAY")
    bar.min:SetSize(bw + 6, 2)
    bar.min:Hide()
    bar.count = UI.Text(deckPanel, 11, "OUTLINE")
    local gem = deckPanel:CreateTexture(nil, "ARTWORK")
    gem:SetTexture(UI.ART .. "StatCost")
    gem:SetSize(17, 17)
    gem:SetPoint("TOP", page, "TOPLEFT", bar.cx, CHART_BASE - 2)
    local label = UI.Text(deckPanel, 10, "OUTLINE")
    label:SetPoint("CENTER", gem, "CENTER", 0, 0.5)
    label:SetText(cost)
    ctl.bars[cost] = bar
  end

  -- ready, or what's missing
  local note = chip(DECK_W - 4, NOTE_H, NOTE_Y, 14)
  note.text = UI.Text(note, 10)
  note.text:SetPoint("TOPLEFT", note.mark, "TOPRIGHT", 5, 6)
  note.text:SetPoint("BOTTOMRIGHT", -6, 2)
  note.text:SetJustifyH("LEFT")
  note.text:SetJustifyV("MIDDLE")
  note.text:SetWordWrap(true)
  ctl.deckNote = note
  local bw = math.floor((DECK_W - 10) / 3)
  local starter = UI.Button(deckPanel, L["Starter"], bw, 22, function()
    C.ResetDeck(ns.db)
    B.Refresh()
  end)
  starter:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X - 1, 4)
  UI.SimpleTooltip(starter, L["Starter deck"], L["Replace this deck with the 20-card starter deck."])
  local clear = UI.Button(deckPanel, L["Empty"], bw, 22, function()
    C.SetDeck(ns.db, {})
    B.Refresh()
  end)
  clear:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X + bw + 2, 4)
  UI.SimpleTooltip(clear, L["Empty deck"], L["Take every card out of this deck, to build one from scratch."])
  ctl.trade = UI.Button(deckPanel, L["Trade"], bw, 22, function() UI.Trading.AskWho() end)
  ctl.trade:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", DECK_X + 2 * bw + 5, 4)
  UI.SimpleTooltip(ctl.trade, L["Trade cards"],
    L["Swap cards with another player who has Tradewinds. You both put up cards, and the trade happens once you've both accepted."],
    L["Target them first, or type their name."])

  UI.Trading.Build(page, DECK_X, DECK_W)
  page:SetScript("OnShow", function() B.Refresh() end)
end
