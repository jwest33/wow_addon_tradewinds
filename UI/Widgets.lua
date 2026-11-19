-- Shared UI pieces: fonts and colours, icon lookup, the card frame used on the
-- board, in the hand, in the binder and in packs, and the card tooltip.
local _, ns = ...
local R, Cards = ns.Rules, ns.Cards

local UI = {}
ns.UI = UI

UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.CARD_W, UI.CARD_H = 66, 92
UI.TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

UI.RARITY_COLOR = {
  common = { 0.80, 0.80, 0.80 },
  uncommon = { 0.12, 1.00, 0.00 },
  rare = { 0.20, 0.55, 1.00 },
  epic = { 0.70, 0.30, 1.00 },
  legendary = { 1.00, 0.50, 0.00 },
}

function UI.Hex(r, g, b)
  return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

function UI.CardName(id)
  local c = Cards.byId[id]
  local col = UI.RARITY_COLOR[c.rarity]
  return UI.Hex(col[1], col[2], col[3]) .. c.name .. "|r"
end

function UI.Text(parent, size, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(UI.FONT, size or 11, flags or "")
  fs:SetTextColor(1, 1, 1)
  fs:SetShadowOffset(1, -1)
  return fs
end

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local BACKDROP2 = {
  bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function UI.Backdrop(f, bg, border, thick)
  if not f.SetBackdrop then return end
  f:SetBackdrop(thick and BACKDROP2 or BACKDROP)
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, h or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.SimpleTooltip(frame, title, ...)
  local lines = { ... }
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(type(title) == "function" and title() or title)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Red error text in the middle of the screen, like the game's own.
function UI.Error(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.25)
  else
    ns.Print(msg)
  end
end

-- ---------------------------------------------------------------------------
-- Icons: each card lists candidates; the first one this client has wins.
-- ---------------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local iconCache = {}

local function exists(path)
  if not GetFileIDFromPath then return nil end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and id or false
end

function UI.Icon(list)
  if type(list) == "string" then list = { list } end
  local key = list[1]
  local hit = iconCache[key]
  if hit then return hit end
  local found
  for _, path in ipairs(list) do
    local id = exists(path)
    if id == nil then found = list[1]; break end -- can't tell on this client: use the first
    if id then found = id; break end
  end
  found = found or QUESTION
  iconCache[key] = found
  return found
end

function UI.CardIcon(id)
  return UI.Icon(Cards.byId[id].icon)
end

-- For /deckhand icons: cards whose preferred icon isn't on this client.
function UI.MissingIcons()
  local out = {}
  if not GetFileIDFromPath then return { "This client can't check icons (no GetFileIDFromPath)." } end
  for _, c in ipairs(Cards.list) do
    if not exists(c.icon[1]) then
      local used = "question mark"
      for i = 2, #c.icon do
        if exists(c.icon[i]) then used = c.icon[i]:match("[^\\]+$"); break end
      end
      out[#out + 1] = ("%s: %s missing, using %s"):format(c.name, c.icon[1]:match("[^\\]+$"), used)
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Little animations
-- ---------------------------------------------------------------------------
local function fader(parent, duration)
  local ag = parent:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0)
  a:SetDuration(duration)
  ag:SetScript("OnFinished", function() parent:SetAlpha(0) end)
  return ag
end

-- A "+2" / "-3" that drifts up and fades, anchored over `owner`.
function UI.AttachFloat(owner)
  local f = CreateFrame("Frame", nil, owner)
  f:SetSize(60, 20)
  f:SetPoint("CENTER", owner, "CENTER", 0, 4)
  f:SetFrameLevel(owner:GetFrameLevel() + 6)
  f.text = UI.Text(f, 18, "THICKOUTLINE")
  f.text:SetPoint("CENTER")
  f:SetAlpha(0)
  local ag = f:CreateAnimationGroup()
  local move = ag:CreateAnimation("Translation")
  move:SetOffset(0, 22)
  move:SetDuration(0.9)
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0)
  fade:SetStartDelay(0.4)
  fade:SetDuration(0.5)
  ag:SetScript("OnFinished", function() f:SetAlpha(0) end)
  owner.Float = function(_, text, r, g, b)
    ag:Stop()
    f.text:SetText(text)
    f.text:SetTextColor(r or 1, g or 1, b or 1)
    f:SetAlpha(1)
    ag:Play()
  end
end

-- A full-size colour flash over `owner`.
function UI.AttachFlash(owner)
  local f = CreateFrame("Frame", nil, owner)
  f:SetAllPoints()
  f:SetFrameLevel(owner:GetFrameLevel() + 5)
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetAllPoints()
  f.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  f.tex:SetBlendMode("ADD")
  f:SetAlpha(0)
  local ag = fader(f, 0.45)
  owner.Flash = function(_, r, g, b)
    ag:Stop()
    f.tex:SetVertexColor(r or 1, g or 1, b or 1, 0.55)
    f:SetAlpha(1)
    ag:Play()
  end
end

-- ---------------------------------------------------------------------------
-- Card frame
-- ---------------------------------------------------------------------------
local Card = {}

function UI.CreateCard(parent)
  local b = CreateFrame("Button", nil, parent, UI.TEMPLATE)
  b:SetSize(UI.CARD_W, UI.CARD_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.Backdrop(b, { 0.07, 0.06, 0.05, 0.97 }, { 0.5, 0.5, 0.5 }, true)

  b.art = b:CreateTexture(nil, "ARTWORK")
  b.art:SetPoint("TOPLEFT", 4, -4)
  b.art:SetPoint("TOPRIGHT", -4, -4)
  b.art:SetHeight(46)
  b.art:SetTexCoord(0.08, 0.92, 0.17, 0.83)

  b.costBg = b:CreateTexture(nil, "OVERLAY")
  b.costBg:SetSize(17, 17)
  b.costBg:SetPoint("TOPLEFT", 1, -1)
  b.costBg:SetColorTexture(0.06, 0.14, 0.42, 0.95)
  b.cost = UI.Text(b, 12, "OUTLINE")
  b.cost:SetPoint("CENTER", b.costBg, "CENTER", 0, 0)

  b.name = UI.Text(b, 9)
  b.name:SetPoint("TOPLEFT", b.art, "BOTTOMLEFT", -2, -2)
  b.name:SetPoint("TOPRIGHT", b.art, "BOTTOMRIGHT", 2, -2)
  b.name:SetHeight(22)
  b.name:SetJustifyH("CENTER")
  b.name:SetJustifyV("TOP")
  b.name:SetWordWrap(true)

  b.kw = UI.Text(b, 8)
  b.kw:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 17)
  b.kw:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 17)
  b.kw:SetJustifyH("CENTER")
  b.kw:SetWordWrap(false)
  b.kw:SetTextColor(0.45, 0.85, 1)

  b.atkBg = b:CreateTexture(nil, "OVERLAY")
  b.atkBg:SetSize(20, 15)
  b.atkBg:SetPoint("BOTTOMLEFT", 2, 2)
  b.atkBg:SetColorTexture(0.35, 0.18, 0.02, 0.95)
  b.atk = UI.Text(b, 12, "OUTLINE")
  b.atk:SetPoint("CENTER", b.atkBg, "CENTER", 0, 0)

  b.hpBg = b:CreateTexture(nil, "OVERLAY")
  b.hpBg:SetSize(20, 15)
  b.hpBg:SetPoint("BOTTOMRIGHT", -2, 2)
  b.hpBg:SetColorTexture(0.35, 0.04, 0.04, 0.95)
  b.hp = UI.Text(b, 12, "OUTLINE")
  b.hp:SetPoint("CENTER", b.hpBg, "CENTER", 0, 0)

  b.typeText = UI.Text(b, 9)
  b.typeText:SetPoint("BOTTOM", 0, 4)
  b.typeText:SetTextColor(0.75, 0.75, 0.75)

  b.tag = UI.Text(b, 10, "OUTLINE")
  b.tag:SetPoint("TOP", b.art, "TOP", 0, -2)

  b.dim = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.dim:SetAllPoints()
  b.dim:SetColorTexture(0, 0, 0, 0.55)
  b.dim:Hide()

  -- card back (unopened pack cards)
  b.back = CreateFrame("Frame", nil, b, UI.TEMPLATE)
  b.back:SetAllPoints()
  b.back:SetFrameLevel(b:GetFrameLevel() + 3)
  UI.Backdrop(b.back, { 0.10, 0.13, 0.30, 1 }, { 0.75, 0.62, 0.25 }, true)
  b.back.icon = b.back:CreateTexture(nil, "ARTWORK")
  b.back.icon:SetSize(38, 38)
  b.back.icon:SetPoint("CENTER", 0, 6)
  b.back.icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  b.back.icon:SetDesaturated(true)
  b.back.icon:SetAlpha(0.6)
  b.back.text = UI.Text(b.back, 9)
  b.back.text:SetPoint("BOTTOM", 0, 8)
  b.back.text:SetText("click")
  b.back.text:SetTextColor(0.75, 0.7, 0.5)
  b.back:EnableMouse(false)
  b.back:Hide()

  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  UI.AttachFlash(b)
  UI.AttachFloat(b)

  for k, v in pairs(Card) do b[k] = v end
  b:SetScript("OnEnter", b.ShowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function kwLine(kw)
  local names = {}
  for _, k in ipairs(Cards.KeywordList(kw)) do names[#names + 1] = k.name end
  if #names > 2 then return names[1] .. ", " .. names[2] .. "+" end
  return table.concat(names, ", ")
end

-- id: card; unit: a unit on the board (current stats) or nil; st: the game or
-- replay view the unit is in (for attack bonuses).
function Card:SetCard(id, unit, st)
  local c = Cards.byId[id]
  self.cardId, self.unit, self.st = id, unit, st
  self.back:Hide()
  self.art:SetTexture(UI.CardIcon(id))
  self.art:SetVertexColor(1, 1, 1)
  self.art:SetDesaturated(false)
  self.cost:SetText(c.cost)
  self.name:SetText(c.name)
  local col = UI.RARITY_COLOR[c.rarity]
  self.border = col
  self:SetBackdropBorderColor(col[1], col[2], col[3], 1)
  self.tag:SetText("")
  if c.type == "unit" then
    local atk, hp, maxHp, kw = c.atk, c.hp, c.hp, c.kw
    if unit then
      atk = st and R.Attack(st, unit) or unit.atk
      hp, maxHp, kw = unit.hp, unit.maxHp, unit.kw
    end
    self.atk:SetText(atk)
    if atk > c.atk then self.atk:SetTextColor(0.3, 1, 0.3)
    elseif atk < c.atk then self.atk:SetTextColor(1, 0.4, 0.4)
    else self.atk:SetTextColor(1, 0.85, 0.3) end
    self.hp:SetText(math.max(0, hp))
    if hp < maxHp then self.hp:SetTextColor(1, 0.35, 0.35)
    elseif maxHp > c.hp then self.hp:SetTextColor(0.3, 1, 0.3)
    else self.hp:SetTextColor(1, 1, 1) end
    self.atk:Show(); self.atkBg:Show(); self.hp:Show(); self.hpBg:Show()
    self.kw:SetText(kwLine(kw))
    self.typeText:SetText("")
    if unit and unit.frozen then
      self.art:SetVertexColor(0.45, 0.7, 1)
      self.tag:SetText("Frozen")
      self.tag:SetTextColor(0.6, 0.85, 1)
    elseif unit and kw.stealth then
      self.art:SetVertexColor(0.6, 0.6, 0.7)
    end
  else
    self.atk:Hide(); self.atkBg:Hide(); self.hp:Hide(); self.hpBg:Hide()
    self.kw:SetText(c.target == "enemy" and "Target: enemy" or c.target == "friend" and "Target: yours" or "")
    self.typeText:SetText("Tactic")
  end
  self:SetDim(false)
  self:SetAlpha(1)
  self:Show()
end

function Card:SetBack(text)
  self.cardId, self.unit = nil, nil
  self.back.text:SetText(text or "click")
  self.back:Show()
  self:Show()
end

function Card:SetDim(on)
  self.dim:SetShown(on and true or false)
end

-- Gold border when selected, back to the rarity colour otherwise.
function Card:SetSelected(on)
  local col = on and { 1, 0.82, 0 } or self.border or { 0.5, 0.5, 0.5 }
  self:SetBackdropBorderColor(col[1], col[2], col[3], 1)
end

function Card:SetTag(text, r, g, b)
  self.tag:SetText(text or "")
  self.tag:SetTextColor(r or 1, g or 1, b or 1)
end

function Card:ShowTooltip()
  if not self.cardId then return end
  UI.CardTooltip(self, self.cardId, self.unit, self.st, self.tipExtra and self.tipExtra(self))
end

-- ---------------------------------------------------------------------------
-- Tooltip (with the creature's portrait beside it when there is one)
-- ---------------------------------------------------------------------------
local portrait

local function portraitFrame()
  if portrait then return portrait end
  portrait = CreateFrame("Frame", nil, GameTooltip, UI.TEMPLATE)
  portrait:SetSize(76, 76)
  portrait:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -2, 0)
  UI.Backdrop(portrait, { 0.05, 0.05, 0.05, 0.95 }, { 0.6, 0.5, 0.3 })
  portrait.tex = portrait:CreateTexture(nil, "ARTWORK")
  portrait.tex:SetPoint("TOPLEFT", 3, -3)
  portrait.tex:SetPoint("BOTTOMRIGHT", -3, 3)
  portrait:Hide()
  GameTooltip:HookScript("OnHide", function() portrait:Hide(); portrait.card = nil end)
  return portrait
end

local function showPortrait(c)
  local f = portraitFrame()
  f:Hide()
  f.card = c
  if not (c.npc and ns.db and ns.db.settings.portraits and ns.Portraits) then return end
  local shown = ns.Portraits.Apply(f.tex, c, function()
    if f.card == c and GameTooltip:IsShown() then showPortrait(c) end
  end)
  if shown then f:Show() end
end

local TARGET_HINT = {
  enemy = "Pick an enemy lane. It lands after the reveal, so it hits whatever is there by then.",
  friend = "Pick one of your units, or a lane you're playing a unit into this round.",
}

function UI.CardTooltip(owner, id, unit, st, extra)
  local c = Cards.byId[id]
  local tip = GameTooltip
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  local col = UI.RARITY_COLOR[c.rarity]
  tip:AddLine(c.name, col[1], col[2], col[3])
  local rarity = c.collectible and (c.rarity:gsub("^%l", string.upper)) or "Token"
  tip:AddDoubleLine((c.type == "unit" and "Unit" or "Tactic") .. ", " .. rarity, c.cost .. " Supply",
    0.65, 0.65, 0.65, 0.45, 0.65, 1)
  local kw = c.kw
  if c.type == "unit" then
    local atk, hp, maxHp = c.atk, c.hp, c.hp
    if unit then
      atk = st and R.Attack(st, unit) or unit.atk
      hp, maxHp, kw = unit.hp, unit.maxHp, unit.kw
    end
    tip:AddLine(("Attack %d    Health %d/%d"):format(atk, math.max(0, hp), maxHp), 1, 0.85, 0.4)
  end
  for _, k in ipairs(Cards.KeywordList(kw)) do
    tip:AddLine(k.name .. ": |cffffffff" .. k.text .. "|r", 0.45, 0.85, 1, true)
  end
  if c.text then tip:AddLine(c.text, 1, 1, 1, true) end
  if c.type == "tactic" and TARGET_HINT[c.target] then tip:AddLine(TARGET_HINT[c.target], 0.6, 0.6, 0.6, true) end
  if unit then
    if unit.frozen then tip:AddLine("Frozen: won't strike this round.", 0.6, 0.85, 1, true) end
    if (unit.tmpAtk or 0) > 0 then tip:AddLine(("+%d attack this round."):format(unit.tmpAtk), 0.3, 1, 0.3) end
  end
  if c.flavor then tip:AddLine("\"" .. c.flavor .. "\"", 0.55, 0.55, 0.55, true) end
  if extra then
    for _, line in ipairs(extra) do tip:AddLine(line, 0.85, 0.85, 0.85, true) end
  end
  tip:Show()
  showPortrait(c)
end
