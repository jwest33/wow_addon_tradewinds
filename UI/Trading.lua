-- Trading, in the Cards tab. While a trade is open, the deck panel makes way
-- for it: what you give, what you get, who has accepted. Clicking a card in
-- the binder offers it. Trade.lua does the talking; this is what you see.
local _, ns = ...
local L = ns.L
local Cards, C = ns.Cards, ns.Collection
local UI = ns.UI

local TU = {}
UI.Trading = TU

local ROW_H = 20
local ROWS = C.TRADE_MAX
local GIVE_Y = -32                               -- the "You give" heading, its rows under it
local GET_Y = GIVE_Y - 18 - ROWS * ROW_H - 8      -- the same for what they give
local CHIP_Y = GET_Y - 18 - ROWS * ROW_H - 8      -- who has accepted
local CHIP_H = 18
local NOTE_Y = CHIP_Y - 2 * CHIP_H - 6
local ROW_BG = { unit = { 0.30, 0.21, 0.13, 0.95 }, tactic = { 0.20, 0.17, 0.38, 0.95 }, trap = { 0.12, 0.26, 0.15, 0.95 } }
local YES_BG, NO_BG = { 0.10, 0.30, 0.10, 0.9 }, { 0.17, 0.15, 0.12, 0.9 }
local TICK = { "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\Buttons\\UI-CheckBox-Check" }
local WAIT = { "Interface\\RaidFrame\\ReadyCheck-Waiting", "Interface\\Buttons\\UI-CheckBox-Up" }

local page, panel, X, W
local ctl = { give = {}, get = {} }

local function T() return ns.Trade end
local function short(name) return ns.Net.Short(name) end

-- ---------------------------------------------------------------------------
-- Asking and answering
-- ---------------------------------------------------------------------------
function TU.Ask(name)
  local ok, why = T().Ask(name)
  if not ok then
    UI.Error(why)
    return false
  end
  ns.Print(L["Trade request sent to %s. They have %d seconds to answer."], short(name), T().ANSWER_SECONDS)
  return true
end

-- The Trade button: the name box (your target's name filled in), or, while
-- you wait for an answer, it takes the request back.
function TU.AskWho()
  if T().Outgoing() then
    T().CancelAsk()
    return
  end
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.TRADEWINDS_TRADE_WHO then
    StaticPopup_Show("TRADEWINDS_TRADE_WHO")
  end
end

function TU.Answer(accept)
  T().Answer(accept)
end

if StaticPopupDialogs then
  StaticPopupDialogs.TRADEWINDS_TRADE = {
    text = L["%s wants to trade Tradewinds cards with you."],
    button1 = L["Accept"],
    button2 = L["Decline"],
    OnAccept = function() TU.Answer(true) end,
    OnCancel = function(_, _, reason) if reason == "clicked" then TU.Answer(false) end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
  }
  local function nameIn(popup)
    local eb = popup.editBox or popup.EditBox
    return eb and eb:GetText() or ""
  end
  StaticPopupDialogs.TRADEWINDS_TRADE_WHO = {
    text = L["Trade cards with which player? They need Tradewinds too."],
    button1 = L["Trade"],
    button2 = CANCEL or L["Cancel"],
    hasEditBox = true,
    maxLetters = 64,
    OnShow = function(self)
      local eb = self.editBox or self.EditBox
      if eb then
        local target = UnitIsPlayer and UnitIsPlayer("target") and UnitName("target")
        eb:SetText(target or "")
        eb:SetFocus()
      end
    end,
    OnAccept = function(self) TU.Ask(nameIn(self)) end,
    EditBoxOnEnterPressed = function(self)
      local popup = self:GetParent()
      TU.Ask(nameIn(popup))
      popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

-- ---------------------------------------------------------------------------
-- What Trade.lua tells us
-- ---------------------------------------------------------------------------
function TU.OnRequest(name)
  ns.Print(L["%s wants to trade Tradewinds cards with you."], name)
  UI.Sound("challenge")
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.TRADEWINDS_TRADE then
    StaticPopup_Show("TRADEWINDS_TRADE", name)
  end
  UI.Refresh()
end

function TU.OnRequestGone(why)
  if StaticPopup_Hide then StaticPopup_Hide("TRADEWINDS_TRADE") end
  if why then ns.Print(why) end
  UI.Refresh()
end

-- The trade window opens in the Cards tab, showing the cards you own.
function TU.OnOpen(name)
  ns.Print(L["Trading with %s: pick the cards to offer in the Cards tab."], name)
  UI.Sound("challenge")
  UI.Show("cards")
  if UI.Binder then UI.Binder.SetFilter("own", "owned") end
end

function TU.OnClose(why)
  if why then
    ns.Print(why)
    UI.Error(why)
  end
  UI.Sound("back")
  UI.Refresh()
end

function TU.OnTheirOffer()
  UI.Sound("pick")
  UI.Refresh()
end

function TU.OnTheyAccepted()
  UI.Sound("lock")
  UI.Refresh()
end

local function copyName(id, holo)
  return UI.CardName(id) .. (holo and (" (" .. UI.Rainbow(L["holographic"]) .. ")") or "")
end

-- The trade went through: what changed hands, in the chat.
function TU.OnDone(name, gave, got, trimmed)
  UI.Sound("rare")
  ns.Print(L["Trade with %s done."], name)
  local list = {}
  for i, e in ipairs(gave) do list[i] = copyName(e.id, e.holo) end
  ns.Print(L["You gave: %s."], #list > 0 and table.concat(list, ", ") or L["nothing"])
  list = {}
  for i, r in ipairs(got) do
    local s = copyName(r.id, r.holo)
    if r.kind == "new" then
      s = s .. " |cff40ff40(" .. L["new"] .. ")|r"
    elseif r.kind == "holo" then
      s = s .. " (" .. L["your copy is holographic now"] .. ")"
    elseif r.kind == "shards" then
      s = s .. " |cff9fdfff(" .. ns.Plural(r.shards, "+%d shard", "+%d shards"):format(r.shards) .. ")|r"
    end
    list[i] = s
  end
  ns.Print(L["You got: %s."], #list > 0 and table.concat(list, ", ") or L["nothing"])
  if #trimmed > 0 then
    list = {}
    for i, e in ipairs(trimmed) do list[i] = L["%s (deck %d)"]:format(UI.CardName(e.id), e.slot) end
    ns.Print(L["Taken out of your decks, since you have fewer copies now: %s."], table.concat(list, ", "))
  end
  UI.Refresh()
end

-- ---------------------------------------------------------------------------
-- The binder while trading: a click offers a card
-- ---------------------------------------------------------------------------
function TU.Click(id, button)
  local ok, why
  if button == "RightButton" then
    ok = T().Withdraw(id)
    if ok then UI.Sound("back") end
  else
    ok, why = T().Offer(id, (IsShiftKeyDown and IsShiftKeyDown()) and true or nil)
    if ok then UI.Sound("place") elseif why then UI.Error(why) end
  end
end

function TU.CellExtra(id)
  local plain, holo = T().Offered(id)
  local lines = { L["Owned %d of %d.  In your offer: %d."]:format(C.Owned(ns.db, id), C.MaxCopies(id), plain + holo) }
  if C.Owned(ns.db, id) > 0 then
    lines[#lines + 1] = "|cff40ff40" .. L["Left-click: offer a copy.  Right-click: take one back."] .. "|r"
    local _, shiny = C.Spare(ns.db, id)
    if shiny then lines[#lines + 1] = UI.Rainbow(L["Shift-click: offer your holographic copy."]) end
  end
  return lines
end

-- Under a card in the binder: how many you have, and how many you offer.
function TU.CellLabel(id)
  local owned, max = C.Owned(ns.db, id), C.MaxCopies(id)
  local plain, holo = T().Offered(id)
  return ("%s%d/%d|r  %s"):format(owned >= max and "|cffffd100" or "|cffffffff", owned, max,
    plain + holo > 0 and ("|cff6fe0ff" .. L["%d offered"]:format(plain + holo) .. "|r") or "")
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
-- Copies grouped into rows (a card's holographic copy apart), cheapest first.
local function groups(offer)
  local out, at = {}, {}
  for _, e in ipairs(offer) do
    local key = e.id .. (e.holo and "*" or "")
    local g = at[key]
    if not g then
      g = { id = e.id, holo = e.holo and true or nil, n = 0 }
      at[key] = g
      out[#out + 1] = g
    end
    g.n = g.n + 1
  end
  table.sort(out, function(a, b)
    local ca, cb = Cards.byId[a.id], Cards.byId[b.id]
    if ca.cost ~= cb.cost then return ca.cost < cb.cost end
    if ca.name ~= cb.name then return ca.name < cb.name end
    return (a.holo and 1 or 0) < (b.holo and 1 or 0)
  end)
  return out
end

-- What each row you'd get does to your collection (new, more shards, ...).
local function preview(rows)
  local list, of = {}, {}
  for gi, g in ipairs(rows) do
    for _ = 1, g.n do
      list[#list + 1] = { id = g.id, holo = g.holo }
      of[#list] = gi
    end
  end
  for i, r in ipairs(C.PreviewAdd(ns.db, list)) do
    local g = rows[of[i]]
    g.new = g.new or r.kind == "new"
    g.shine = g.shine or r.kind == "holo"
    g.shards = (g.shards or 0) + (r.shards or 0)
  end
end

local function rowTip(r)
  local g = r.group
  if not g then return end
  local lines = {}
  if r.give then
    lines[1] = "|cff40ff40" .. L["Click: take one back."] .. "|r"
  else
    lines[1] = L["You have %d of %d."]:format(C.Owned(ns.db, g.id), C.MaxCopies(g.id))
    if g.new then
      lines[2] = "|cff40ff40" .. L["New to your collection."] .. "|r"
    elseif g.shine then
      lines[2] = UI.Rainbow(L["Your copy turns holographic."])
    elseif g.shards > 0 then
      lines[2] = "|cff9fdfff" .. L["You have every copy you can use, so it turns into shards (%d)."]:format(g.shards) .. "|r"
    end
  end
  UI.CardTooltip(r, g.id, nil, nil, lines, g.holo)
end

local function offerRow(i, y, give)
  local r = CreateFrame("Button", nil, panel)
  r.give = give
  r:SetSize(W - 4, ROW_H - 2)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", X - 1, y - 18 - (i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetTexture(UI.ART .. "Pill")
  r.gem = r:CreateTexture(nil, "ARTWORK")
  r.gem:SetTexture(UI.ART .. "StatCost")
  r.gem:SetSize(20, 20)
  r.gem:SetPoint("LEFT", -3, 0)
  r.cost = UI.Text(r, 11, "OUTLINE")
  r.cost:SetPoint("CENTER", r.gem, "CENTER", 0, 0.5)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 4, ROW_H - 4)
  r.icon:SetPoint("LEFT", 19, 0)
  r.icon:SetTexCoord(unpack(UI.ICON_COORDS))
  r.tag = UI.Text(r, 9, "OUTLINE")
  r.tag:SetPoint("RIGHT", -6, 0)
  r.tag:SetWidth(52)
  r.tag:SetJustifyH("RIGHT")
  r.tag:SetWordWrap(false)
  r.count = UI.Text(r, 10, "OUTLINE")
  r.count:SetTextColor(1, 0.82, 0)
  r.name = UI.Text(r, 10)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetTexture(UI.ART .. "Pill")
  r.hl:SetBlendMode("ADD")
  r.hl:SetVertexColor(0.55, 0.95, 0.85, 0.22)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self)
    if self.give and self.group and T().Withdraw(self.group.id, self.group.holo or false) then
      UI.Sound("back")
      UI.Refresh()
    end
  end)
  r:SetScript("OnEnter", rowTip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

-- A strip with a tick (or an hourglass) and a line of text.
local function chip(y)
  local f = CreateFrame("Frame", nil, panel)
  f:SetSize(W - 4, CHIP_H - 2)
  f:SetPoint("TOPLEFT", page, "TOPLEFT", X - 1, y)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetTexture(UI.ART .. "Pill")
  f.mark = f:CreateTexture(nil, "ARTWORK")
  f.mark:SetSize(13, 13)
  f.mark:SetPoint("LEFT", 5, 0)
  f.text = UI.Text(f, 10)
  f.text:SetPoint("LEFT", f.mark, "RIGHT", 5, 0)
  f.text:SetPoint("RIGHT", -6, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(false)
  return f
end

local function setChip(f, yes, text)
  local bg = yes and YES_BG or NO_BG
  f.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
  f.mark:SetTexture(UI.Icon(yes and TICK or WAIT))
  UI.FitText(f.text, text, 8)
  if yes then f.text:SetTextColor(0.6, 1, 0.6) else f.text:SetTextColor(0.75, 0.75, 0.75) end
end

local function heading(y)
  local h = UI.Text(panel, 11)
  h:SetPoint("TOPLEFT", page, "TOPLEFT", X, y)
  h:SetWidth(W - 50)
  h:SetJustifyH("LEFT")
  h:SetWordWrap(false)
  h:SetTextColor(1, 0.82, 0)
  local n = UI.Text(panel, 10)
  n:SetPoint("TOPRIGHT", page, "TOPLEFT", X + W - 8, y)
  n:SetTextColor(0.7, 0.7, 0.7)
  local none = UI.Text(panel, 10)
  none:SetPoint("TOPLEFT", page, "TOPLEFT", X + 4, y - 22)
  none:SetTextColor(0.5, 0.5, 0.5)
  return h, n, none
end

local function fill(rows, offer, give)
  local list = groups(offer)
  if not give then preview(list) end
  for i, r in ipairs(rows) do
    local g = list[i]
    r.group = g
    if g then
      local c = Cards.byId[g.id]
      local bg = ROW_BG[c.type] or ROW_BG.unit
      r.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
      r.cost:SetText(c.cost)
      r.icon:SetTexture(UI.CardIcon(g.id))
      r.count:SetText(g.n > 1 and ("x" .. g.n) or "")
      local tag = ""
      if not give then
        if g.new then tag = "|cff40ff40" .. L["New"] .. "|r"
        elseif g.shine then tag = UI.Rainbow(L["Holo"])
        elseif g.shards > 0 then tag = "|cff9fdfff" .. ns.Plural(g.shards, "+%d shard", "+%d shards"):format(g.shards) .. "|r" end
      end
      UI.FitText(r.tag, tag, 7)
      local right = (tag ~= "" and 58 or 6)
      r.count:ClearAllPoints()
      r.count:SetPoint("RIGHT", -right, 0)
      r.name:SetPoint("RIGHT", -(right + (g.n > 1 and 22 or 0)), 0)
      UI.FitText(r.name, g.holo and UI.Rainbow(c.name) or UI.CardName(g.id), 8)
      r:Show()
    else
      r:Hide()
    end
  end
  return #list
end

function TU.Refresh()
  if not panel then return end
  local c = T().Current()
  panel:SetShown(c ~= nil)
  if not c then return end
  local name = short(c.name)
  UI.FitText(ctl.title, L["Trade with %s"]:format(name), 10)
  fill(ctl.give, c.mine, true)
  fill(ctl.get, c.theirs, false)
  ctl.giveCount:SetText(("%d/%d"):format(#c.mine, C.TRADE_MAX))
  ctl.getCount:SetText(("%d/%d"):format(#c.theirs, C.TRADE_MAX))
  UI.FitText(ctl.getHead, L["%s gives"]:format(name), 8)
  ctl.giveNone:SetShown(#c.mine == 0)
  ctl.getNone:SetShown(#c.theirs == 0)

  local mine, theirs = c.accepted ~= nil, c.theyAccepted and true or false
  setChip(ctl.me, mine, mine and L["You have accepted"] or L["You haven't accepted yet"])
  setChip(ctl.them, theirs, (theirs and L["%s has accepted"] or L["%s hasn't accepted yet"]):format(name))

  -- what's going on, and what to look out for
  local lines = {}
  if c.note then
    lines[#lines + 1] = "|cffffa040" .. c.note .. "|r"
  elseif mine and theirs then
    lines[#lines + 1] = "|cff60ff60" .. L["You've both accepted. Trading..."] .. "|r"
  elseif theirs then
    lines[#lines + 1] = "|cff60ff60" .. L["%s has accepted. Accept to trade."]:format(name) .. "|r"
  elseif mine then
    lines[#lines + 1] = L["Waiting for %s to accept."]:format(name)
  else
    lines[#lines + 1] = L["Click your cards on the left to offer them. When you're both happy, both accept."]
  end
  local trims = C.TradeTrims(ns.db, c.mine)
  if trims > 0 then
    lines[#lines + 1] = "|cffffa040" .. ns.Plural(trims, "Giving these away takes %d card out of your decks.",
      "Giving these away takes %d cards out of your decks."):format(trims) .. "|r"
  end
  UI.FitText(ctl.note, table.concat(lines, "\n"), 8)

  local busy = c.committing or (mine and theirs)
  ctl.accept:SetEnabled(not mine and not busy and (#c.mine + #c.theirs) > 0)
  ctl.accept:SetText(mine and L["Accepted"] or L["Accept"])
  ctl.cancel:SetEnabled(not c.committing)
end

-- What the panel shows, without colours (for the tests).
function TU.View()
  local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local function names(rows)
    local out = {}
    for _, r in ipairs(rows) do
      if r:IsShown() then
        local s, n, tag = plain(r.name:GetText()), r.count:GetText(), plain(r.tag:GetText())
        out[#out + 1] = s .. (n ~= "" and (" " .. n) or "") .. (tag ~= "" and (" [" .. tag .. "]") or "")
      end
    end
    return out
  end
  return { shown = panel and panel:IsShown() or false, title = ctl.title:GetText(), give = names(ctl.give),
    get = names(ctl.get), me = ctl.me.text:GetText(), them = ctl.them.text:GetText(), note = plain(ctl.note:GetText()),
    canAccept = ctl.accept:IsEnabled(), canCancel = ctl.cancel:IsEnabled() }
end

-- Built by the Cards tab, over its deck panel (x, w: the panel's left edge
-- and width on the page).
function TU.Build(parent, x, w)
  page, X, W = parent, x, w
  panel = CreateFrame("Frame", nil, page, UI.TEMPLATE)
  panel:SetPoint("TOPLEFT", page, "TOPLEFT", X - 5, 2)
  panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 2, -2)
  UI.Backdrop(panel, { 0.05, 0.08, 0.08, 0.92 }, { 0.3, 0.62, 0.56 })
  ctl.title = UI.Text(panel, 13)
  ctl.title:SetPoint("TOPLEFT", page, "TOPLEFT", X, -8)
  ctl.title:SetWidth(W - 8)
  ctl.title:SetJustifyH("LEFT")
  ctl.title:SetWordWrap(false)
  ctl.title:SetTextColor(0.55, 1, 0.9)

  local h
  h, ctl.giveCount, ctl.giveNone = heading(GIVE_Y)
  h:SetText(L["You give"])
  ctl.giveNone:SetText(L["Nothing yet."])
  ctl.getHead, ctl.getCount, ctl.getNone = heading(GET_Y)
  ctl.getNone:SetText(L["Nothing yet."])
  for i = 1, ROWS do
    ctl.give[i] = offerRow(i, GIVE_Y, true)
    ctl.get[i] = offerRow(i, GET_Y, false)
  end

  ctl.me = chip(CHIP_Y)
  ctl.them = chip(CHIP_Y - CHIP_H)
  ctl.note = UI.Text(panel, 10)
  ctl.note:SetPoint("TOPLEFT", page, "TOPLEFT", X, NOTE_Y)
  ctl.note:SetSize(W - 8, 64)
  ctl.note:SetJustifyH("LEFT")
  ctl.note:SetJustifyV("TOP")
  ctl.note:SetWordWrap(true)
  ctl.note:SetTextColor(0.8, 0.8, 0.8)

  local bw = math.floor((W - 8) / 2)
  ctl.accept = UI.Button(panel, L["Accept"], bw, 22, function()
    local ok, why = T().Accept()
    if ok then UI.Sound("lock") elseif why then UI.Error(why) end
    UI.Refresh()
  end)
  ctl.accept:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", X - 1, 4)
  UI.SimpleTooltip(ctl.accept, L["Accept"], L["The trade happens once you've both accepted. Any change to either side takes both acceptances back."])
  ctl.cancel = UI.Button(panel, CANCEL or L["Cancel"], bw, 22, function()
    if T().Cancel() then ns.Print(L["You cancelled the trade."]) end
  end)
  ctl.cancel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", X + bw + 3, 4)
  panel:Hide()
end
