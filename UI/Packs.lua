-- The Packs tab: open card packs and Windfall packs card by card, buy card
-- packs with shards, and see how close the next travel packs are.
--
-- Opening is a small ceremony: each card turns over when clicked (UI/Effects
-- FX.Flip). A rare or better glows first in its colour; an epic, a legendary
-- or a holographic card charges up for a moment before it turns, so the wait
-- is the tell. "Reveal all" turns the rest one after another, best last. A
-- line under the cards sums the pack up once they're all face up.
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
P.STAGGER = 0.15                   -- seconds between cards turned by "Reveal all"

local page
local ctl = {}
local slots = {}
-- the pack on the table: { results, shown = { bool x n } (turning or face
-- up), up = { bool x n } (face up), special = bool }
local opened
local batch   -- Open all is opening packs: milestones wait until it has said what was in them

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

-- How fancy a card from a pack is: its rarity, and holographic above all.
local function rank(r)
  return Cards.RARITY_RANK[Cards.byId[r.id].rarity] + (r.holo and 10 or 0)
end

-- "2 new cards, +3 shards": a pack's results in a line.
function P.Summary(results)
  local new, shards, holo = 0, 0, 0
  for _, r in ipairs(results) do
    if r.kind == "new" then new = new + 1 end
    if r.holo then holo = holo + 1 end
    shards = shards + (r.shards or 0)
  end
  local parts = {}
  if new > 0 then parts[#parts + 1] = "|cffffd100" .. ns.Plural(new, "%d new card", "%d new cards"):format(new) .. "|r" end
  if holo > 0 then parts[#parts + 1] = UI.Rainbow(ns.Plural(holo, "%d holographic", "%d holographic"):format(holo)) end
  if shards > 0 then parts[#parts + 1] = "|cff9fdfff" .. ns.Plural(shards, "+%d shard", "+%d shards"):format(shards) .. "|r" end
  if #parts == 0 then return L["Nothing new this time."] end
  return table.concat(parts, ", ")
end

-- Lays the slots out for a pack of n cards, centred.
local function layout(n)
  local cw = UI.CARD_W * CARD_SCALE
  local x0 = (784 - (n * (cw + CARD_GAP) - CARD_GAP)) / 2
  for i, s in ipairs(slots) do
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", page, "TOPLEFT", x0 + (i - 1) * (cw + CARD_GAP), SLOT_Y)
  end
end

local function allUp()
  if not opened then return false end
  for k = 1, #opened.results do
    if not opened.up[k] then return false end
  end
  return true
end

-- Card i is face up: its label, a flash, a word for the fancy ones.
local function faceUp(i)
  local r = opened.results[i]
  local slot = slots[i]
  opened.up[i] = true
  local c = Cards.byId[r.id]
  local col = UI.RARITY_COLOR[c.rarity]
  slot.card:Flash(col[1], col[2], col[3])
  if r.holo then
    slot.card:Float(L["Holographic!"], 0.7, 0.95, 1)
    UI.Sound("rare")
  elseif c.rarity == "legendary" or c.rarity == "epic" then
    slot.card:Float(c.rarity == "legendary" and L["Legendary!"] or L["Epic!"], col[1], col[2], col[3])
    UI.Sound(c.rarity == "legendary" and "legendary" or "rare")
  else
    UI.Sound("reveal")
  end
  slot.label:SetText(label(r))
  P.Refresh()
  -- once the whole pack is face up: the summary, and a milestone its cards
  -- reached (a whole tribe) pays now, so the news never spoils a card still
  -- face down
  if allUp() and not batch then ns.CheckMilestones() end
end

-- Turns card i over. instant: no flip (opening the next pack, Open all).
local function reveal(i, instant)
  if not opened or opened.shown[i] or not opened.results[i] then return end
  opened.shown[i] = true
  local pack = opened
  local r = opened.results[i]
  local slot = slots[i]
  local function apply() slot.card:SetCard(r.id, nil, nil, r.holo) end
  if instant or not UI.FX then
    apply()
    faceUp(i)
    return
  end
  local c = Cards.byId[r.id]
  local rr = Cards.RARITY_RANK[c.rarity]
  local fancy = r.holo or rr >= Cards.RARITY_RANK.epic
  local glow = (r.holo or rr >= Cards.RARITY_RANK.rare) and UI.RARITY_COLOR[c.rarity] or nil
  UI.Sound("flip")
  slot.flip = UI.FX.Flip(slot.card, apply, {
    glow = glow, holo = r.holo, charge = fancy and UI.FX.CHARGE or 0,
    onCharge = function() UI.Sound("charge") end,
    done = function()
      slot.flip = nil
      if opened == pack then faceUp(i) end
    end,
  })
end

-- Every card still turning ends face up now.
local function settle()
  for _, s in ipairs(slots) do
    if s.flip then s.flip:Finish() end
  end
end

-- ...and every card still face down turns at once.
local function finishAll()
  settle()
  if opened then
    for i = 1, #opened.results do reveal(i, true) end
  end
end

-- "Reveal all": the cards still face down turn one after another, the best
-- one last.
local function revealAll()
  if not opened then return end
  local order = {}
  for i = 1, #opened.results do
    if not opened.shown[i] then order[#order + 1] = i end
  end
  table.sort(order, function(a, b)
    local ra, rb = rank(opened.results[a]), rank(opened.results[b])
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  local pack = opened
  for k, i in ipairs(order) do
    if k == 1 or not UI.FX then
      reveal(i)
    else
      UI.FX.Run(0.01, function() end, function() if opened == pack then reveal(i) end end, (k - 1) * P.STAGGER, true)
    end
  end
end

-- Shows a pack's cards face down.
local function lay(results, special)
  finishAll()
  opened = { results = results, shown = {}, up = {}, special = special }
  layout(#results)
  for _, s in ipairs(slots) do
    s.card:SetBack()
    s.card:SetAlpha(1)
    s.label:SetText("")
  end
  if special then
    -- the card that's always rare or better is the last one
    slots[#results].label:SetText(("|cff%02x%02x%02x%s|r"):format(WINDFALL[1] * 255, WINDFALL[2] * 255, WINDFALL[3] * 255,
      L["Rare or better"]))
  end
end

-- Opens every pack of both kinds at once: the new cards are listed in chat,
-- and the last pack is laid out face up.
local function openAll()
  batch = true
  finishAll()
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
    batch = false
    UI.Error(L["No packs to open."])
    ns.CheckMilestones()
    return
  end
  lay(last, lastSpecial)
  finishAll()
  batch = false
  ns.Print(L["Opened %s: %s, %s from extra copies."], ns.Plural(n, "%d pack", "%d packs"):format(n),
    ns.Plural(#names, "%d new card", "%d new cards"):format(#names), ns.Plural(shards, "%d shard", "%d shards"):format(shards))
  for i = 1, #names, 6 do
    ns.Print(L["New: %s"], table.concat(names, ", ", i, math.min(#names, i + 5)))
  end
  for _, s in ipairs(special) do ns.Print("%s", s) end
  if #special > 0 then UI.Sound("rare") end
  ns.CheckMilestones()
  UI.Refresh()
end

-- kind: nil (a card pack) or "special" (a Windfall pack)
local function openPack(kind)
  finishAll()
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
P.RevealAll, P.OpenAll, P.FinishAll = revealAll, openAll, finishAll
P.Reveal = function(i) reveal(i) end
function P.Opened() return opened end
function P.Slot(i) return slots[i] end
function P.SummaryShown() return ctl.summary:IsShown() and ctl.summary:GetText() or nil end

-- A line for chat about the pack just opened (UI.Share), when it had an epic,
-- a legendary or a holographic card: the best of them. nil otherwise.
function P.ShareText()
  if not (opened and allUp()) then return nil end
  local best
  for _, r in ipairs(opened.results) do
    if (r.holo or Cards.RARITY_RANK[Cards.byId[r.id].rarity] >= Cards.RARITY_RANK.epic)
        and (not best or rank(r) > rank(best)) then
      best = r
    end
  end
  if not best then return nil end
  local c = Cards.byId[best.id]
  local what = L[c.rarity] .. (best.holo and (", " .. L["holographic"]) or "")
  local card = ("%s (%s)"):format(c.name, what)
  return opened.special and L["[Tradewinds] I just pulled %s from a Windfall pack!"]:format(card)
    or L["[Tradewinds] I just pulled %s from a card pack!"]:format(card)
end

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
  local done = opened ~= nil and allUp()
  ctl.summary:SetShown(done)
  if done then ctl.summary:SetText(P.Summary(opened.results)) end
  ctl.share:SetShown(done and P.ShareText() ~= nil)
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

-- "Ways to earn packs" and "What's in a pack": two columns of short rows,
-- an icon each, with the details in the row's tooltip.
local function infoRow(parent, x, y, w, icon, text, tipTitle, tip)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(w, 26)
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  r:EnableMouse(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(22, 22)
  r.icon:SetPoint("LEFT", 0, 0)
  if icon.art then
    r.icon:SetTexture(UI.ART .. icon.art)
    if icon.col then r.icon:SetVertexColor(icon.col[1], icon.col[2], icon.col[3]) end
  else
    r.icon:SetTexture(UI.Icon(icon))
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  r.text = UI.Text(r, 11)
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.text:SetSize(w - 32, 24)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  UI.FitText(r.text, text, 9)
  r.text:SetTextColor(0.85, 0.85, 0.85)
  UI.SimpleTooltip(r, tipTitle, tip)
  return r
end

local function buildInfo(y)
  local colW = 360
  local x1, x2 = 24, 24 + colW + 32
  local function header(x, text)
    local h = UI.Text(page, 12)
    h:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    h:SetText(text)
    h:SetTextColor(1, 0.82, 0)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.55, 0.45, 0.25, 0.5)
    line:SetSize(colW, 1)
    line:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 16)
  end
  header(x1, L["Ways to earn packs"])
  header(x2, L["What's in a pack"])
  local ROW = 30
  local y0 = y - 24
  local travelMin = C.TRAVEL_PACK_SECONDS / 60
  local left = {
    { ns.OpponentById.dorn.icon, L["Every %d minutes of travel"]:format(travelMin), L["Travel"],
      L["A card pack for every %d minutes on a flight path, boat or zeppelin. The clock carries over from trip to trip."]:format(travelMin) },
    { { art = "Star", col = { 1, 0.82, 0 } }, L["Stars, and your first win of the day"], L["Winning"],
      L["Your first win each day pays a pack. So do stars: your first win against each opponent, and winning with a deck of commons and uncommons."] },
    { { "Interface\\Icons\\INV_Enchant_ShardBrilliantSmall", "Interface\\Icons\\INV_Misc_Gem_Pearl_04" },
      L["%d shards buy one"]:format(C.PACK_COST), L["Shards"],
      L["Wins, the daily task, levels, new flight paths and extra copies give shards."] },
    { { art = "Star", col = WINDFALL }, L["Windfall packs: long trips and milestones"], L["Windfall packs"],
      (L["Every %d minutes of travel, the tutorial, every tenth level, all three stars against an opponent, heroic wins, and one of every card of a tribe. They can't be bought."]):format(
        C.TRAVEL_SPECIAL_SECONDS / 60) },
  }
  local right = {
    { { "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" },
      L["Two commons and an uncommon or better"], L["Card packs"],
      L["The third card is sometimes a rare, now and then an epic, and very rarely a legendary. You never open more than %d packs in a row without an epic."]:format(C.PITY - 1) },
    { { art = "Star", col = WINDFALL }, L["Windfall: five cards, the last rare or better"], L["Windfall packs"],
      L["Two commons, an uncommon, one like a card pack's best card, and one that's always rare or better."] },
    { { "Interface\\Icons\\INV_Misc_Gem_Pearl_04", "Interface\\Icons\\INV_Enchant_ShardBrilliantSmall" },
      L["About 1 pack in %d has a %s card"]:format(C.HOLO_ODDS, UI.Rainbow(L["holographic"])), L["Holographic"],
      L["It plays the same; it just shines."] },
    { Cards.byId[ns.OpponentById.dorn.signature].icon, L["Signature cards: win them from opponents"], L["Signature cards"],
      L["Signature cards that aren't legendary aren't in packs: win them from opponents, or craft them."] },
  }
  for i, def in ipairs(left) do infoRow(page, x1, y0 - (i - 1) * ROW, colW, def[1], def[2], def[3], def[4]) end
  for i, def in ipairs(right) do infoRow(page, x2, y0 - (i - 1) * ROW, colW, def[1], def[2], def[3], def[4]) end
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
  ctl.summary = UI.Text(page, 13, "OUTLINE")
  ctl.summary:SetPoint("TOP", page, "TOP", 0, SLOT_Y - ch - 26)
  ctl.summary:Hide()
  ctl.share = UI.Button(page, L["Share"], 70, 20, function() UI.Share(P.ShareText()) end)
  ctl.share:SetPoint("LEFT", ctl.summary, "RIGHT", 12, 0)
  UI.SimpleTooltip(ctl.share, L["Share"], L["Puts a line about it in your chat box, for you to send (or not)."])
  ctl.share:Hide()

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

  buildInfo(barY - 44)

  page:SetScript("OnShow", function() P.Refresh() end)
  page:SetScript("OnHide", function() settle() end)
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function()
      if page:IsVisible() then P.Refresh() end
    end)
  end
end
