-- The Packs tab: open card packs and Windfall packs card by card, buy card
-- packs with shards, and see how close the next travel packs are.
local _, ns = ...
local L = ns.L
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local P = {}
UI.Packs = P

local CARD_SCALE = 1.1
local CARD_GAP = 18
local SLOT_Y = -78
local WINDFALL = { 1, 0.6, 0.2 }   -- the colour of everything Windfall

local page
local ctl = {}
local slots = {}
local opened -- { results, shown = { bool x n }, special = bool }

local function fmtTime(s)
  s = math.floor(s)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local KIND_LABEL = {
  new = "|cffffd100" .. L["NEW!"] .. "|r",
  copy = "|cffb0b0b0" .. L["copy"] .. "|r",
}

local function label(r)
  if r.kind == "shards" then
    return "|cff9fdfff" .. ns.Plural(r.shards, "+%d shard", "+%d shards"):format(r.shards) .. "|r"
  elseif r.holo then
    return r.kind == "holo" and UI.Rainbow(L["Now holographic!"])
      or (r.kind == "new" and (KIND_LABEL.new .. " ") or "") .. UI.Rainbow(L["Holographic!"])
  end
  return KIND_LABEL[r.kind]
end
P.Label = label

-- Lays the slots out for a pack of n cards, centred.
local function layout(n)
  local cw = UI.CARD_W * CARD_SCALE
  local x0 = (784 - (n * (cw + CARD_GAP) - CARD_GAP)) / 2
  for i, s in ipairs(slots) do
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", page, "TOPLEFT", x0 + (i - 1) * (cw + CARD_GAP), SLOT_Y)
  end
end

local function reveal(i)
  if not opened or opened.shown[i] or not opened.results[i] then return end
  opened.shown[i] = true
  local r = opened.results[i]
  local slot = slots[i]
  slot.card:SetCard(r.id, nil, nil, r.holo)
  local c = Cards.byId[r.id]
  local col = UI.RARITY_COLOR[c.rarity]
  slot.card:Flash(col[1], col[2], col[3])
  if r.holo then
    slot.card:Float(L["Holographic!"], 0.7, 0.95, 1)
    UI.Sound("rare")
  elseif c.rarity == "legendary" or c.rarity == "epic" then
    slot.card:Float(c.rarity == "legendary" and L["Legendary!"] or L["Epic!"], col[1], col[2], col[3])
    UI.Sound("rare")
  else
    UI.Sound("reveal")
  end
  slot.label:SetText(label(r))
  P.Refresh()
  -- once the whole pack is face up: a milestone its cards reached (a whole
  -- tribe) pays now, so the news never spoils a card still face down
  for k = 1, #opened.results do
    if not opened.shown[k] then return end
  end
  ns.CheckMilestones()
end

local function revealAll()
  if not opened then return end
  for i = 1, #opened.results do reveal(i) end
end

-- Shows a pack's cards face down.
local function lay(results, special)
  opened = { results = results, shown = {}, special = special }
  layout(#results)
  for i, s in ipairs(slots) do
    s.card:SetBack()
    s.label:SetText("")
  end
  if special then
    -- the card that's always rare or better is the last one
    slots[#results].label:SetText(("|cff%02x%02x%02x%s|r"):format(WINDFALL[1] * 255, WINDFALL[2] * 255, WINDFALL[3] * 255,
      L["Rare or better"]))
  end
end

-- Opens every pack of both kinds at once: the new cards are listed in chat,
-- and the last pack is laid out as usual.
local function openAll()
  revealAll()
  local n, shards, last, lastSpecial, names, special = 0, 0, nil, false, {}, {}
  for _, kind in ipairs({ "normal", "special" }) do
    local k = kind == "special" and "special" or nil
    while true do
      local results = C.OpenPack(ns.db, ns.Rand, k)
      if not results then break end
      n, last, lastSpecial = n + 1, results, k ~= nil
      for _, r in ipairs(results) do
        if r.kind == "new" then names[#names + 1] = UI.CardName(r.id) end
        if r.holo then special[#special + 1] = L["%s: %s"]:format(UI.Rainbow(L["Holographic"]), UI.CardName(r.id)) end
        if Cards.byId[r.id].rarity == "legendary" then special[#special + 1] = L["%s: %s"]:format(L["Legendary"], UI.CardName(r.id)) end
        shards = shards + (r.shards or 0)
      end
    end
  end
  if n == 0 then
    UI.Error(L["No packs to open."])
    return
  end
  lay(last, lastSpecial)
  revealAll()
  ns.Print(L["Opened %s: %s, %s from extra copies."], ns.Plural(n, "%d pack", "%d packs"):format(n),
    ns.Plural(#names, "%d new card", "%d new cards"):format(#names), ns.Plural(shards, "%d shard", "%d shards"):format(shards))
  for i = 1, #names, 6 do
    ns.Print(L["New: %s"], table.concat(names, ", ", i, math.min(#names, i + 5)))
  end
  for _, s in ipairs(special) do ns.Print("%s", s) end
  if #special > 0 then UI.Sound("rare") end
  UI.Refresh()
end

-- kind: nil (a card pack) or "special" (a Windfall pack)
local function openPack(kind)
  revealAll()
  local results = C.OpenPack(ns.db, ns.Rand, kind)
  if not results then
    UI.Error(L["No packs to open."])
    return
  end
  lay(results, kind == "special")
  UI.Sound("packOpen")
  UI.Refresh()
end

P.Open = function() openPack(nil) end
P.OpenSpecial = function() openPack("special") end
P.RevealAll, P.OpenAll = revealAll, openAll

function P.Refresh()
  if not page then return end
  local db = ns.db
  local special = db.specialPacks or 0
  ctl.count:SetText(db.packs)
  ctl.open:SetEnabled(db.packs > 0)
  ctl.open:SetText(db.packs > 0 and L["Open a pack"] or L["No packs"])
  ctl.openAll:SetEnabled(db.packs + special > 1)
  ctl.openSpecial:SetEnabled(special > 0)
  ctl.special:SetText(L["Windfall packs: %d"]:format(special))
  if special > 0 then
    ctl.special:SetTextColor(WINDFALL[1], WINDFALL[2], WINDFALL[3])
  else
    ctl.special:SetTextColor(0.5, 0.5, 0.5)
  end
  ctl.shards:SetText(("%d / %d"):format(db.shards, C.PACK_COST))
  ctl.buy:SetEnabled(db.shards >= C.PACK_COST)
  local pending = false
  if opened then
    for i = 1, #opened.results do
      if not opened.shown[i] then pending = true end
    end
  end
  ctl.revealAll:SetShown(pending)
  ctl.empty:SetShown(not opened)
  for i, s in ipairs(slots) do s:SetShown(opened ~= nil and i <= #opened.results) end
  local t = db.progress.travel or 0
  ctl.bar:SetValue(t / C.TRAVEL_PACK_SECONDS)
  local T = ns.Travel
  local where = (T and T.IsFlying()) and L["(in the air)"] or (T and T.IsRiding()) and L["(on board)"]
  ctl.barText:SetText(L["Travel time toward your next pack: %s / %s"]:format(fmtTime(t), fmtTime(C.TRAVEL_PACK_SECONDS))
    .. (where and ("  |cff40ff40" .. where .. "|r") or ""))
  local w = db.progress.specialTravel or 0
  ctl.windBar:SetValue(w / C.TRAVEL_SPECIAL_SECONDS)
  ctl.windText:SetText(L["Toward your next Windfall pack: %s / %s"]:format(fmtTime(w), fmtTime(C.TRAVEL_SPECIAL_SECONDS)))
end

function P.Build(parent)
  page = parent

  local icon = page:CreateTexture(nil, "ARTWORK")
  icon:SetSize(52, 52)
  icon:SetPoint("TOPLEFT", 6, -6)
  icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  local label = UI.Text(page, 11)
  label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  label:SetText(L["Card packs"])
  label:SetTextColor(0.75, 0.75, 0.75)
  ctl.count = UI.Text(page, 26, "OUTLINE")
  ctl.count:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
  ctl.count:SetTextColor(1, 0.82, 0)
  ctl.open = UI.Button(page, L["Open a pack"], 120, 24, P.Open)
  ctl.open:SetPoint("TOPLEFT", page, "TOPLEFT", 160, -8)
  ctl.openAll = UI.Button(page, L["Open all"], 90, 24, openAll)
  ctl.openAll:SetPoint("LEFT", ctl.open, "RIGHT", 6, 0)
  UI.SimpleTooltip(ctl.openAll, L["Open all"], L["Opens every pack you have, Windfall packs too. The new cards are listed in chat."])

  -- Windfall packs: five cards, one of them rare or better
  ctl.openSpecial = UI.Button(page, L["Open a Windfall pack"], 160, 22, P.OpenSpecial)
  ctl.openSpecial:SetPoint("TOPLEFT", page, "TOPLEFT", 160, -38)
  ctl.special = UI.Text(page, 12, "OUTLINE")
  ctl.special:SetPoint("LEFT", ctl.openSpecial, "RIGHT", 8, 0)
  local windHelp = CreateFrame("Frame", nil, page)
  windHelp:SetPoint("LEFT", ctl.special, "LEFT")
  windHelp:SetSize(130, 20)
  windHelp:EnableMouse(true)
  local windTip = { L["Windfall packs"],
    L["Five cards, and the last one is always rare or better."],
    (L["You earn them every %d minutes of travel and for milestones: the tutorial, every tenth level, all three stars against an opponent, heroic wins, and one of every card of a tribe. They can't be bought."]):format(
      C.TRAVEL_SPECIAL_SECONDS / 60) }
  UI.SimpleTooltip(windHelp, windTip[1], windTip[2], windTip[3])
  UI.SimpleTooltip(ctl.openSpecial, windTip[1], windTip[2], windTip[3])

  local sIcon = page:CreateTexture(nil, "ARTWORK")
  sIcon:SetSize(32, 32)
  sIcon:SetPoint("TOPLEFT", page, "TOPLEFT", 470, -10)
  sIcon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Enchant_ShardBrilliantSmall", "Interface\\Icons\\INV_Misc_Gem_Pearl_04" }))
  local sLabel = UI.Text(page, 11)
  sLabel:SetPoint("TOPLEFT", sIcon, "TOPRIGHT", 8, 0)
  sLabel:SetText(L["Shards"])
  sLabel:SetTextColor(0.75, 0.75, 0.75)
  ctl.shards = UI.Text(page, 14, "OUTLINE")
  ctl.shards:SetPoint("TOPLEFT", sLabel, "BOTTOMLEFT", 0, -3)
  ctl.shards:SetTextColor(0.62, 0.87, 1)
  local shardHelp = CreateFrame("Frame", nil, page)
  shardHelp:SetPoint("TOPLEFT", sIcon, "TOPLEFT")
  shardHelp:SetSize(100, 34)
  shardHelp:EnableMouse(true)
  UI.SimpleTooltip(shardHelp, L["Shards"],
    (L["A card you already have the maximum of (2, or 1 for legendaries) turns into shards: common %d, uncommon %d, rare %d, epic %d."]):format(
      C.SHARD_VALUE.common, C.SHARD_VALUE.uncommon, C.SHARD_VALUE.rare, C.SHARD_VALUE.epic),
    (L["Games, levels, flight paths and the daily task give shards too. %d shards buy a pack. In the Cards tab, shift-click a card to craft it with shards."]):format(C.PACK_COST))
  ctl.buy = UI.Button(page, L["Buy a pack"], 100, 22, function()
    if C.BuyPack(ns.db) then UI.Refresh() end
  end)
  ctl.buy:SetPoint("TOPLEFT", page, "TOPLEFT", 600, -14)

  -- the pack's cards, a little bigger than anywhere else; as many slots as
  -- the biggest pack, laid out for the pack that's open
  local cw, ch = UI.CARD_W * CARD_SCALE, UI.CARD_H * CARD_SCALE
  for i = 1, math.max(C.PACK_SIZE, C.SPECIAL_SIZE) do
    local s = CreateFrame("Frame", nil, page)
    s:SetSize(cw, ch + 18)
    s.card = UI.CreateCard(s)
    s.card:SetBaseScale(CARD_SCALE)
    s.card:SetPoint("TOP")
    s.card:SetScript("OnClick", function() reveal(i) end)
    s.label = UI.Text(s, 10)
    s.label:SetPoint("TOP", s.card, "BOTTOM", 0, -3)
    s:Hide()
    slots[i] = s
  end
  layout(C.PACK_SIZE)
  ctl.empty = UI.Text(page, 11)
  ctl.empty:SetPoint("TOP", page, "TOP", 0, -140)
  ctl.empty:SetText(L["Open a pack to see what's inside. Click each card to turn it over."])
  ctl.empty:SetTextColor(0.6, 0.6, 0.6)
  ctl.revealAll = UI.Button(page, L["Reveal all"], 100, 22, revealAll)
  ctl.revealAll:SetPoint("TOP", page, "TOP", 0, SLOT_Y - ch - 22)

  -- the two travel clocks
  local barY = SLOT_Y - ch - 52
  local bar = CreateFrame("StatusBar", nil, page, UI.TEMPLATE)
  bar:SetSize(250, 14)
  bar:SetPoint("TOPRIGHT", page, "TOP", -10, barY)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.3, 0.6, 1)
  bar:SetMinMaxValues(0, 1)
  UI.Backdrop(bar, { 0, 0, 0, 0.6 }, { 0.3, 0.3, 0.3 })
  ctl.bar = bar
  ctl.barText = UI.Text(page, 10)
  ctl.barText:SetPoint("TOP", bar, "BOTTOM", 0, -3)
  local windBar = CreateFrame("StatusBar", nil, page, UI.TEMPLATE)
  windBar:SetSize(250, 14)
  windBar:SetPoint("TOPLEFT", page, "TOP", 10, barY)
  windBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  windBar:SetStatusBarColor(WINDFALL[1], WINDFALL[2], WINDFALL[3])
  windBar:SetMinMaxValues(0, 1)
  UI.Backdrop(windBar, { 0, 0, 0, 0.6 }, { 0.3, 0.3, 0.3 })
  ctl.windBar = windBar
  ctl.windText = UI.Text(page, 10)
  ctl.windText:SetPoint("TOP", windBar, "BOTTOM", 0, -3)

  local earn = UI.Text(page, 10)
  earn:SetPoint("TOPLEFT", page, "TOPLEFT", 110, barY - 40)
  earn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -110, barY - 40)
  earn:SetJustifyH("LEFT")
  earn:SetSpacing(2)
  earn:SetTextColor(0.75, 0.75, 0.75)
  earn:SetText(table.concat({
    "|cffffd100" .. L["Ways to earn packs"] .. "|r",
    L["- Every %d minutes on a flight path, boat or zeppelin"]:format(C.TRAVEL_PACK_SECONDS / 60),
    L["- Your first win of the day, and stars: your first win against each opponent, and winning with a deck of commons and uncommons"],
    L["- %d shards. Wins, the daily task, levels, new flight paths and extra copies give shards"]:format(C.PACK_COST),
    "|cffffd100" .. L["What's in a pack"] .. "|r",
    L["- Two commons and an uncommon, which is sometimes a rare, now and then an epic, and very rarely a legendary"],
    L["- Signature cards that aren't legendary aren't in packs: win them from opponents, or craft them"],
    L["- About 1 pack in %d has a %s card. It plays the same; it just shines"]:format(C.HOLO_ODDS, UI.Rainbow(L["holographic"])),
    "|cffff9933" .. L["Windfall packs"] .. "|r",
    (L["- Five cards: two commons, an uncommon, one like a pack's best card, and one that's always rare or better. Every %d minutes of travel, and for milestones (point at the button above)"]):format(
      C.TRAVEL_SPECIAL_SECONDS / 60),
  }, "\n"))

  page:SetScript("OnShow", function() P.Refresh() end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
      if page:IsVisible() then P.Refresh() end
    end)
  end
end
