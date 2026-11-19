-- Shared UI pieces: fonts and colours, icon lookup, sounds, the card frame
-- used on the board, in the hand, in the binder and in packs, and the card
-- tooltip.
local _, ns = ...
local R, Cards = ns.Rules, ns.Cards

local UI = {}
ns.UI = UI

UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.CARD_W, UI.CARD_H = 92, 128
UI.TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
UI.ART = "Interface\\AddOns\\" .. ns.ADDON_FOLDER .. "\\Art\\"   -- textures made by tools/gen_art.py

-- text colours (names, tooltips)
UI.RARITY_COLOR = {
  common = { 0.80, 0.80, 0.80 },
  uncommon = { 0.12, 1.00, 0.00 },
  rare = { 0.20, 0.55, 1.00 },
  epic = { 0.70, 0.30, 1.00 },
  legendary = { 1.00, 0.50, 0.00 },
}
-- card border tints: the same hues, toned down
local BORDER_COLOR = {
  common = { 0.62, 0.62, 0.62 },
  uncommon = { 0.27, 0.74, 0.22 },
  rare = { 0.26, 0.50, 0.95 },
  epic = { 0.64, 0.34, 0.90 },
  legendary = { 0.96, 0.56, 0.12 },
}

function UI.Hex(r, g, b)
  return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Each letter a step further round the colour wheel (holographic labels).
function UI.Rainbow(s)
  local out, n = {}, #s
  for i = 1, n do
    local h = ((i - 1) / math.max(1, n) * 0.85) * 6
    local r = math.min(1, math.max(0, math.abs(h - 3) - 1))
    local g = math.min(1, math.max(0, 2 - math.abs(h - 2)))
    local b = math.min(1, math.max(0, 2 - math.abs(h - 4)))
    out[i] = UI.Hex(0.45 + r * 0.55, 0.45 + g * 0.55, 0.45 + b * 0.55) .. s:sub(i, i)
  end
  return table.concat(out) .. "|r"
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
-- Sounds: each has a list of the game's own sound kit names; the first one
-- this client has is played. Off with the Sound option.
-- ---------------------------------------------------------------------------
local SOUNDS = {
  pick = { "IG_ABILITY_PAGE_TURN", "IG_CHARACTER_INFO_TAB" },
  place = { "IG_ABILITY_ICON_DROP", "IG_BACKPACK_CLOSE" },
  back = { "IG_BACKPACK_CLOSE", "IG_CHARACTER_INFO_CLOSE" },
  lock = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "IG_CHARACTER_INFO_TAB" },
  tactic = { "IG_SPELLBOOK_OPEN", "IG_ABILITY_PAGE_TURN" },
  win = { "IG_QUEST_LIST_COMPLETE", "IG_QUEST_LIST_OPEN" },
  lose = { "IG_QUEST_LOG_ABANDON_QUEST", "IG_QUEST_LIST_CLOSE", "IG_MAINMENU_CLOSE" },
  packOpen = { "IG_BACKPACK_OPEN" },
  reveal = { "IG_SPELLBOOK_OPEN" },
  rare = { "IG_QUEST_LIST_COMPLETE" },
  tab = { "IG_CHARACTER_INFO_TAB" },
}

function UI.Sound(key)
  if not (ns.db and ns.db.settings.sound and PlaySound and SOUNDKIT) then return end
  for _, name in ipairs(SOUNDS[key] or {}) do
    local id = SOUNDKIT[name]
    if id then
      pcall(PlaySound, id)
      return
    end
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
  f.text = UI.Text(f, 20, "THICKOUTLINE")
  f.text:SetPoint("CENTER")
  f:SetAlpha(0)
  local ag = f:CreateAnimationGroup()
  local move = ag:CreateAnimation("Translation")
  move:SetOffset(0, 26)
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
  f:SetPoint("TOPLEFT", 2, -2)
  f:SetPoint("BOTTOMRIGHT", -2, 2)
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

-- A short jab toward the target and back: owner:Lunge(dy).
function UI.AttachLunge(owner)
  local ag = owner:CreateAnimationGroup()
  local out = ag:CreateAnimation("Translation")
  out:SetDuration(0.09)
  out:SetOrder(1)
  local back = ag:CreateAnimation("Translation")
  back:SetDuration(0.16)
  back:SetOrder(2)
  owner.Lunge = function(_, dy)
    ag:Stop()
    out:SetOffset(0, dy)
    back:SetOffset(0, -dy)
    ag:Play()
  end
end

-- ---------------------------------------------------------------------------
-- Card frame. The frame art is three layers: the icon, the card body with a
-- window over the icon (Art/CardBase), and a grey border tinted by rarity
-- (Art/CardBorder). Positions come from the texture's layout (tools/gen_art.py)
-- scaled by K.
-- ---------------------------------------------------------------------------
local Card = {}
local K = UI.CARD_W / 256      -- texture pixels to screen units
local V = 358 / 512            -- the card fills the top of its 256x512 texture
local ART_BOX = { 16, 16, 240, 166 }
local NAME_BOX = { 10, 158, 246, 214 }
local TEXT_BOX = { 16, 220, 240, 320 }
local KEYWORD_COLOR = "|cff1c3f7a"

local function badge(b, file, point, x, y, r, g, bl)
  local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
  t:SetTexture(UI.ART .. file)
  t:SetSize(25, 25)
  t:SetPoint("CENTER", b, point, x, y)
  t:SetVertexColor(r, g, bl)
  local fs = UI.Text(b, 13, "OUTLINE")
  fs:SetPoint("CENTER", t, "CENTER", 0, 0)
  return t, fs
end

function UI.CreateCard(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(UI.CARD_W, UI.CARD_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  b.art = b:CreateTexture(nil, "BACKGROUND")
  b.art:SetPoint("TOPLEFT", ART_BOX[1] * K, -ART_BOX[2] * K)
  b.art:SetSize((ART_BOX[3] - ART_BOX[1]) * K, (ART_BOX[4] - ART_BOX[2]) * K)
  b.art:SetTexCoord(0.08, 0.92, 0.22, 0.78)

  -- holographic foil over the art, and a prismatic ring over the border
  -- (shown on holographic cards only; UI.HoloTick animates them)
  b.foil = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.foil:SetAllPoints(b.art)
  b.foil:SetTexture(UI.ART .. "Holo")
  b.foil:SetBlendMode("ADD")
  b.foil:SetAlpha(0.42)
  b.foil:Hide()

  b.base = b:CreateTexture(nil, "BORDER")
  b.base:SetAllPoints()
  b.base:SetTexture(UI.ART .. "CardBase")
  b.base:SetTexCoord(0, 1, 0, V)

  b.frame = b:CreateTexture(nil, "ARTWORK")
  b.frame:SetAllPoints()
  b.frame:SetTexture(UI.ART .. "CardBorder")
  b.frame:SetTexCoord(0, 1, 0, V)

  b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.ring:SetAllPoints()
  b.ring:SetTexture(UI.ART .. "HoloRing")
  b.ring:SetTexCoord(0, 1, 0, V)
  b.ring:SetBlendMode("ADD")
  b.ring:Hide()

  b.name = UI.Text(b, 8)
  b.name:SetPoint("CENTER", b, "TOP", 0, -(NAME_BOX[2] + NAME_BOX[4]) / 2 * K)
  b.name:SetSize((NAME_BOX[3] - NAME_BOX[1] - 8) * K, (NAME_BOX[4] - NAME_BOX[2]) * K)
  b.name:SetJustifyH("CENTER")
  b.name:SetJustifyV("MIDDLE")
  b.name:SetWordWrap(true)
  b.name:SetTextColor(0.98, 0.94, 0.84)

  -- keywords and the card's short rules text, on the parchment
  b.text = UI.Text(b, 8)
  b.text:SetPoint("CENTER", b, "TOP", 0, -(TEXT_BOX[2] + TEXT_BOX[4]) / 2 * K)
  b.text:SetSize((TEXT_BOX[3] - TEXT_BOX[1] - 10) * K, (TEXT_BOX[4] - TEXT_BOX[2] - 6) * K)
  b.text:SetJustifyH("CENTER")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetWordWrap(true)
  b.text:SetTextColor(0.18, 0.13, 0.08)
  b.text:SetShadowOffset(0, 0)

  b.costBg, b.cost = badge(b, "Gem", "TOPLEFT", 8, -8, 0.24, 0.47, 1)
  b.atkBg, b.atk = badge(b, "BadgeAttack", "BOTTOMLEFT", 8, 8, 1, 0.59, 0.16)
  b.hpBg, b.hp = badge(b, "BadgeHealth", "BOTTOMRIGHT", -8, 8, 0.88, 0.2, 0.2)

  b.typeText = UI.Text(b, 8)
  b.typeText:SetPoint("BOTTOM", 0, 3)
  b.typeText:SetTextColor(0.75, 0.72, 0.62)

  b.tag = UI.Text(b, 11, "OUTLINE")
  b.tag:SetPoint("TOP", b.art, "TOP", 0, -3)

  b.dim = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.dim:SetPoint("TOPLEFT", 2, -2)
  b.dim:SetPoint("BOTTOMRIGHT", -2, 2)
  b.dim:SetColorTexture(0, 0, 0, 0.55)
  b.dim:Hide()

  -- card back (unopened pack cards)
  b.back = CreateFrame("Frame", nil, b)
  b.back:SetAllPoints()
  b.back:SetFrameLevel(b:GetFrameLevel() + 3)
  b.back.tex = b.back:CreateTexture(nil, "ARTWORK")
  b.back.tex:SetAllPoints()
  b.back.tex:SetTexture(UI.ART .. "CardBack")
  b.back.tex:SetTexCoord(0, 1, 0, V)
  b.back.text = UI.Text(b.back, 9)
  b.back.text:SetPoint("BOTTOM", 0, 12)
  b.back.text:SetText("click")
  b.back.text:SetTextColor(0.85, 0.75, 0.5)
  b.back:EnableMouse(false)
  b.back:Hide()

  -- under the mouse: the card's own border lights up gold (textures in the
  -- HIGHLIGHT layer are only drawn while the mouse is over the frame)
  b.glow = b:CreateTexture(nil, "HIGHLIGHT")
  b.glow:SetAllPoints()
  b.glow:SetTexture(UI.ART .. "CardBorder")
  b.glow:SetTexCoord(0, 1, 0, V)
  b.glow:SetVertexColor(1, 0.8, 0.25)
  b.glow:SetBlendMode("ADD")
  b.wash = b:CreateTexture(nil, "HIGHLIGHT")
  b.wash:SetPoint("TOPLEFT", 4, -4)
  b.wash:SetPoint("BOTTOMRIGHT", -4, 4)
  b.wash:SetColorTexture(1, 0.9, 0.6, 0.10)
  b.wash:SetBlendMode("ADD")
  UI.AttachFlash(b)
  UI.AttachFloat(b)
  UI.AttachLunge(b)

  for k, v in pairs(Card) do b[k] = v end
  b:SetScript("OnEnter", b.ShowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- What's printed on the card: its keywords, then its short rules text.
local function faceText(c, kw)
  local names = {}
  for _, k in ipairs(Cards.KeywordList(kw)) do names[#names + 1] = k.name end
  local parts = {}
  if #names > 0 then parts[1] = KEYWORD_COLOR .. table.concat(names, ", ") .. "|r" end
  if c.short then parts[#parts + 1] = c.short end
  return table.concat(parts, "\n")
end
UI.FaceText = faceText

local TACTIC_LABEL = { enemy = "Tactic: enemy lane", friend = "Tactic: your unit", none = "Tactic" }

-- id: card; unit: a unit on the board (current stats) or nil; st: the game or
-- replay view the unit is in (for attack bonuses); holo: draw it holographic.
function Card:SetCard(id, unit, st, holo)
  local c = Cards.byId[id]
  self.cardId, self.unit, self.st = id, unit, st
  self.back:Hide()
  self:SetHolo(holo)
  self.art:SetTexture(UI.CardIcon(id))
  self.art:SetVertexColor(1, 1, 1)
  self.art:SetDesaturated(false)
  self.cost:SetText(c.cost)
  self.name:SetText(c.name)
  self.border = BORDER_COLOR[c.rarity]
  self.frame:SetVertexColor(self.border[1], self.border[2], self.border[3])
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
    else self.atk:SetTextColor(1, 1, 1) end
    self.hp:SetText(math.max(0, hp))
    if hp < maxHp then self.hp:SetTextColor(1, 0.75, 0.2)
    elseif maxHp > c.hp then self.hp:SetTextColor(0.3, 1, 0.3)
    else self.hp:SetTextColor(1, 1, 1) end
    self.atk:Show(); self.atkBg:Show(); self.hp:Show(); self.hpBg:Show()
    self.text:SetText(faceText(c, kw))
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
    self.text:SetText(c.short or "")
    self.typeText:SetText(TACTIC_LABEL[c.target] or "Tactic")
  end
  self:SetDim(false)
  self:SetAlpha(1)
  self:Show()
end

function Card:SetBack(text)
  self.cardId, self.unit = nil, nil
  self:SetHolo(false)
  self.back.text:SetText(text or "click")
  self.back:Show()
  self:Show()
end

-- Holographic cards: the foil slides across the art and the ring brightens
-- and fades. One OnUpdate drives every holographic card on screen.
local holoCards = {}
local holoClock = 0

function UI.HoloTick(elapsed)
  holoClock = holoClock + (elapsed or 0)
  local any = false
  for b in pairs(holoCards) do
    any = true
    if b:IsVisible() then
      local t = holoClock + b.holoPhase
      local u = (t * 0.045) % 0.5
      b.foil:SetTexCoord(u, u + 0.5, 0, 1)
      b.ring:SetAlpha(0.72 + 0.28 * math.sin(t * 2.1))
    end
  end
  return any
end

local holoDriver
function Card:SetHolo(on)
  on = on and true or false
  self.holo = on
  self.foil:SetShown(on)
  self.ring:SetShown(on)
  if on then
    if not self.holoPhase then self.holoPhase = math.random() * 10 end
    holoCards[self] = true
    if not holoDriver then
      holoDriver = CreateFrame("Frame")
      holoDriver:SetScript("OnUpdate", function(_, elapsed) UI.HoloTick(elapsed) end)
    end
    UI.HoloTick(0)
  else
    holoCards[self] = nil
  end
end

function Card:SetDim(on)
  self.dim:SetShown(on and true or false)
end

-- Gold border when selected, back to the rarity colour otherwise.
function Card:SetSelected(on)
  local col = on and { 1, 0.86, 0.2 } or self.border or BORDER_COLOR.common
  self.frame:SetVertexColor(col[1], col[2], col[3])
end

function Card:SetTag(text, r, g, b)
  self.tag:SetText(text or "")
  self.tag:SetTextColor(r or 1, g or 1, b or 1)
end

function Card:ShowTooltip()
  if not self.cardId then return end
  UI.CardTooltip(self, self.cardId, self.unit, self.st, self.tipExtra and self.tipExtra(self), self.holo)
end

-- ---------------------------------------------------------------------------
-- Tooltip, with the creature's portrait on its far side when there is one
-- (the tooltip opens to the right of the card, so the portrait goes to the
-- right of the tooltip and never covers the card).
-- ---------------------------------------------------------------------------
local portrait

local function portraitFrame()
  if portrait then return portrait end
  portrait = CreateFrame("Frame", nil, GameTooltip, UI.TEMPLATE)
  portrait:SetSize(76, 76)
  portrait:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 2, 0)
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

function UI.CardTooltip(owner, id, unit, st, extra, holo)
  local c = Cards.byId[id]
  local tip = GameTooltip
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  local col = UI.RARITY_COLOR[c.rarity]
  tip:AddLine(c.name, col[1], col[2], col[3])
  if holo then tip:AddLine(UI.Rainbow("Holographic")) end
  local rarity = c.collectible and (c.rarity:gsub("^%l", string.upper)) or "Token"
  local kind = c.type == "unit" and (c.tribe and (Cards.TRIBES[c.tribe] .. " unit") or "Unit") or "Tactic"
  tip:AddDoubleLine(kind .. ", " .. rarity, c.cost .. " Supply",
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
  if c.collectible and not unit then
    local o = c.signature and ns.OpponentById[c.signature]
    local packs = c.rarity == "legendary" and "Very rarely found in packs." or "Not in packs."
    if o then
      tip:AddLine(("Signature card: earn %s's second star, or craft it. %s"):format(o.short, packs), 1, 0.82, 0, true)
    elseif c.signature then
      tip:AddLine("Earn every star on the circuit, or craft it. " .. packs, 1, 0.82, 0, true)
    elseif c.rarity == "legendary" then
      tip:AddLine(packs, 1, 0.82, 0, true)
    end
  end
  if extra then
    for _, line in ipairs(extra) do tip:AddLine(line, 0.85, 0.85, 0.85, true) end
  end
  tip:Show()
  showPortrait(c)
end
