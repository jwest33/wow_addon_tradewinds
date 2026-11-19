-- The Packs tab: open packs card by card, buy packs with shards, and see how
-- close the next flight pack is.
local _, ns = ...
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local P = {}
UI.Packs = P

local page
local ctl = {}
local slots = {}
local opened -- { results, shown = { bool x5 } }

local function sound(key)
  local id = SOUNDKIT and SOUNDKIT[key]
  if id and PlaySound then pcall(PlaySound, id) end
end

local function fmtTime(s)
  s = math.floor(s)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local KIND_LABEL = {
  new = "|cffffd100NEW!|r",
  copy = "|cffb0b0b0copy|r",
}

local function reveal(i)
  if not opened or opened.shown[i] then return end
  opened.shown[i] = true
  local r = opened.results[i]
  local slot = slots[i]
  slot.card:SetCard(r.id)
  local c = Cards.byId[r.id]
  local col = UI.RARITY_COLOR[c.rarity]
  slot.card:Flash(col[1], col[2], col[3])
  if c.rarity == "legendary" or c.rarity == "epic" then
    slot.card:Float(c.rarity == "legendary" and "Legendary!" or "Epic!", col[1], col[2], col[3])
    sound("IG_QUEST_LIST_COMPLETE")
  else
    sound("IG_SPELLBOOK_OPEN")
  end
  slot.label:SetText(r.kind == "shards" and ("|cff9fdfff+%d shard%s|r"):format(r.shards, r.shards == 1 and "" or "s")
    or KIND_LABEL[r.kind])
  P.Refresh()
end

local function revealAll()
  if not opened then return end
  for i = 1, C.PACK_SIZE do reveal(i) end
end

local function openPack()
  revealAll()
  local results = C.OpenPack(ns.db, ns.Rand)
  if not results then
    UI.Error("No packs to open.")
    return
  end
  opened = { results = results, shown = {} }
  for i = 1, C.PACK_SIZE do
    slots[i].card:SetBack()
    slots[i].label:SetText("")
  end
  sound("IG_BACKPACK_OPEN")
  UI.Refresh()
end

P.Open, P.RevealAll = openPack, revealAll

function P.Refresh()
  if not page then return end
  local db = ns.db
  ctl.count:SetText(db.packs)
  ctl.open:SetEnabled(db.packs > 0)
  ctl.open:SetText(db.packs > 0 and "Open a pack" or "No packs")
  ctl.shards:SetText(("%d / %d"):format(db.shards, C.PACK_COST))
  ctl.buy:SetEnabled(db.shards >= C.PACK_COST)
  local pending = false
  if opened then
    for i = 1, C.PACK_SIZE do
      if not opened.shown[i] then pending = true end
    end
  end
  ctl.revealAll:SetShown(pending)
  ctl.empty:SetShown(not opened)
  for i = 1, C.PACK_SIZE do slots[i]:SetShown(opened ~= nil) end
  local t = db.progress.travel or 0
  ctl.bar:SetValue(t / C.TRAVEL_PACK_SECONDS)
  ctl.barText:SetText(("Flight time toward your next pack: %s / %s%s"):format(fmtTime(t), fmtTime(C.TRAVEL_PACK_SECONDS),
    (ns.Travel and ns.Travel.IsFlying()) and "  |cff40ff40(in the air)|r" or ""))
end

function P.Build(parent)
  page = parent

  local icon = page:CreateTexture(nil, "ARTWORK")
  icon:SetSize(52, 52)
  icon:SetPoint("TOPLEFT", 6, -6)
  icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  local label = UI.Text(page, 11)
  label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  label:SetText("Card packs")
  label:SetTextColor(0.75, 0.75, 0.75)
  ctl.count = UI.Text(page, 26, "OUTLINE")
  ctl.count:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
  ctl.count:SetTextColor(1, 0.82, 0)
  ctl.open = UI.Button(page, "Open a pack", 120, 26, openPack)
  ctl.open:SetPoint("TOPLEFT", page, "TOPLEFT", 160, -14)

  local sIcon = page:CreateTexture(nil, "ARTWORK")
  sIcon:SetSize(32, 32)
  sIcon:SetPoint("TOPLEFT", page, "TOPLEFT", 320, -10)
  sIcon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Enchant_ShardBrilliantSmall", "Interface\\Icons\\INV_Misc_Gem_Pearl_04" }))
  local sLabel = UI.Text(page, 11)
  sLabel:SetPoint("TOPLEFT", sIcon, "TOPRIGHT", 8, 0)
  sLabel:SetText("Shards")
  sLabel:SetTextColor(0.75, 0.75, 0.75)
  ctl.shards = UI.Text(page, 14, "OUTLINE")
  ctl.shards:SetPoint("TOPLEFT", sLabel, "BOTTOMLEFT", 0, -3)
  ctl.shards:SetTextColor(0.62, 0.87, 1)
  local shardHelp = CreateFrame("Frame", nil, page)
  shardHelp:SetPoint("TOPLEFT", sIcon, "TOPLEFT")
  shardHelp:SetSize(100, 34)
  shardHelp:EnableMouse(true)
  UI.SimpleTooltip(shardHelp, "Shards",
    "Cards you already have the maximum of (2, or 1 for legendaries) turn into shards: common 1, uncommon 2, rare 5, epic 10, legendary 25.",
    "Games give shards too. 20 shards buy a pack.")
  ctl.buy = UI.Button(page, "Buy a pack", 100, 22, function()
    if C.BuyPack(ns.db) then UI.Refresh() end
  end)
  ctl.buy:SetPoint("TOPLEFT", page, "TOPLEFT", 430, -14)

  local x0 = (544 - (C.PACK_SIZE * (UI.CARD_W + 14) - 14)) / 2
  for i = 1, C.PACK_SIZE do
    local s = CreateFrame("Frame", nil, page)
    s:SetSize(UI.CARD_W, UI.CARD_H + 18)
    s:SetPoint("TOPLEFT", page, "TOPLEFT", x0 + (i - 1) * (UI.CARD_W + 14), -86)
    s.card = UI.CreateCard(s)
    s.card:SetPoint("TOP")
    s.card:SetScript("OnClick", function() reveal(i) end)
    s.label = UI.Text(s, 10)
    s.label:SetPoint("TOP", s.card, "BOTTOM", 0, -3)
    s:Hide()
    slots[i] = s
  end
  ctl.empty = UI.Text(page, 11)
  ctl.empty:SetPoint("TOP", page, "TOP", 0, -130)
  ctl.empty:SetText("Open a pack to see what's inside. Click each card to turn it over.")
  ctl.empty:SetTextColor(0.6, 0.6, 0.6)
  ctl.revealAll = UI.Button(page, "Reveal all", 100, 22, revealAll)
  ctl.revealAll:SetPoint("TOP", page, "TOP", 0, -206)

  local bar = CreateFrame("StatusBar", nil, page, UI.TEMPLATE)
  bar:SetSize(420, 14)
  bar:SetPoint("TOP", page, "TOP", 0, -252)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.3, 0.6, 1)
  bar:SetMinMaxValues(0, 1)
  UI.Backdrop(bar, { 0, 0, 0, 0.6 }, { 0.3, 0.3, 0.3 })
  ctl.bar = bar
  ctl.barText = UI.Text(page, 10)
  ctl.barText:SetPoint("TOP", bar, "BOTTOM", 0, -4)

  local earn = UI.Text(page, 10)
  earn:SetPoint("TOPLEFT", page, "TOPLEFT", 64, -300)
  earn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -64, -300)
  earn:SetJustifyH("LEFT")
  earn:SetSpacing(3)
  earn:SetTextColor(0.75, 0.75, 0.75)
  earn:SetText(table.concat({
    "|cffffd100Ways to earn packs|r",
    "- Every 10 minutes on a flight path",
    "- Discovering a new flight path, and every level you gain",
    "- Your first win of the day, and your first win against each opponent",
    "- 20 shards from games and extra copies",
  }, "\n"))

  page:SetScript("OnShow", function() P.Refresh() end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
      if page:IsVisible() then P.Refresh() end
    end)
  end
end
