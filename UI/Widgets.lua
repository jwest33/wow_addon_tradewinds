-- Shared UI pieces: fonts and colours, icon lookup, sounds, the card frame
-- used on the board, in the hand, in the binder and in packs, and the card
-- tooltip.
local _, ns = ...
local L = ns.L
local R, Cards = ns.Rules, ns.Cards

local UI = {}
ns.UI = UI

UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.CARD_W, UI.CARD_H = 112, 156
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
-- Letters, not bytes: translations have letters of two to four bytes (UTF-8).
function UI.Rainbow(s)
  local chars = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  local out, n = {}, #chars
  for i = 1, n do
    local h = ((i - 1) / math.max(1, n) * 0.85) * 6
    local r = math.min(1, math.max(0, math.abs(h - 3) - 1))
    local g = math.min(1, math.max(0, 2 - math.abs(h - 2)))
    local b = math.min(1, math.max(0, 2 - math.abs(h - 4)))
    out[i] = UI.Hex(0.45 + r * 0.55, 0.45 + g * 0.55, 0.45 + b * 0.55) .. chars[i]
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
  fs.fontSize, fs.fontFlags = size or 11, flags or ""
  fs:SetTextColor(1, 1, 1)
  fs:SetShadowOffset(1, -1)
  return fs
end

-- Sets the text of a font string with a fixed box (UI.Text) and, if it
-- doesn't fit, shrinks the font a step at a time, down to `min`. For labels
-- whose length depends on the language.
function UI.FitText(fs, text, min)
  local size = fs.fontSize or 11
  fs:SetFont(UI.FONT, size, fs.fontFlags or "")
  fs:SetText(text)
  min = min or math.max(6, size - 3)
  while size > min and fs:IsTruncated() do
    size = size - 1
    fs:SetFont(UI.FONT, size, fs.fontFlags or "")
  end
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

-- A label too long for its button (some languages run long) gets the
-- smaller button font.
local function fitButton(b)
  local fs = b:GetFontString()
  if not (fs and GameFontNormalSmall) then return end
  if b.small then
    b.small = false
    b:SetNormalFontObject(GameFontNormal)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetDisabledFontObject(GameFontDisable)
  end
  if (fs:GetStringWidth() or 0) > b:GetWidth() - 12 then
    b.small = true
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
  end
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, h or 22)
  local setText = b.SetText
  function b:SetText(t)
    setText(self, t)
    fitButton(self)
  end
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
  challenge = { "READY_CHECK", "IG_PLAYER_INVITE", "IG_QUEST_LIST_OPEN" },
  countTick = { "UI_BATTLEGROUND_COUNTDOWN_TIMER", "IG_MINIMAP_ZOOM_IN", "IG_ABILITY_PAGE_TURN" },
  countGo = { "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "IG_QUEST_LIST_OPEN", "IG_SPELLBOOK_OPEN" },
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

-- For /tradewinds icons: cards whose preferred icon isn't on this client.
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

-- A short side-to-side shake (a hit): owner:Shake(px).
function UI.AttachShake(owner)
  local ag = owner:CreateAnimationGroup()
  local steps = {}
  for i, k in ipairs({ 1, -2, 2, -2, 1 }) do
    local a = ag:CreateAnimation("Translation")
    a:SetDuration(0.035)
    a:SetOrder(i)
    steps[i] = { anim = a, k = k }
  end
  owner.Shake = function(_, px)
    ag:Stop()
    for _, st in ipairs(steps) do st.anim:SetOffset(st.k * (px or 4), 0) end
    ag:Play()
  end
end

-- ---------------------------------------------------------------------------
-- Card frame. Back to front: the icon (through a hole in the body), the body
-- (Art/CardUnit or Art/CardTactic: bronze and parchment for units, indigo
-- and vellum for tactics; the picture's glow and the icon's frame are part
-- of it), the rim (Art/CardRim, grey, tinted by
-- rarity), then the gems, the stats and the text. Positions are the
-- textures' layout in texture pixels (tools/gen_art.py), scaled by K.
--
-- The icon is shown whole and square, at about the size the game shows its
-- own: the game's icons are small pictures and look blocky stretched.
--
-- The card is UI.CARD_W x UI.CARD_H at scale 1. A page that wants it bigger
-- or smaller calls card:SetBaseScale(s) and makes its cell s times the size.
-- ---------------------------------------------------------------------------
local Card = {}
local K = UI.CARD_W / 256      -- texture pixels to screen units
local V = 357 / 512            -- the card fills the top of its 256x512 texture
local ART_BOX = { 14, 14, 242, 146 }   -- the picture
local ICON_BOX = { 78, 25, 178, 125 }  -- the icon in its frame, in the middle of the picture
local NAME_BOX = { 8, 136, 248, 170 }
local TYPE_BOX = { 20, 170, 236, 195 }
local TEXT_BOX = { unit = { 16, 199, 240, 310 }, tactic = { 16, 199, 240, 332 } }
local TEXT_INSET = { unit = { 7, 4, 7, 26 }, tactic = { 7, 4, 7, 6 } }   -- the text stays clear of the stats
local GEM_Y = { unit = 333, tactic = 342 }
local GLOW_PAD, GLOW_V = 22 * K, 342 / 512   -- Art/CardGlow: the card plus 22 texture pixels all round
local STAT = 30                -- stat badge size
local GEM = 13                 -- rarity gem size
UI.CARD_V = V
-- Where the icon sits on the card (x, y from the top left, width, height).
UI.CARD_ART = { ICON_BOX[1] * K, ICON_BOX[2] * K, (ICON_BOX[3] - ICON_BOX[1]) * K, (ICON_BOX[4] - ICON_BOX[2]) * K }
UI.ICON_COORDS = { 0.08, 0.92, 0.08, 0.92 }   -- an icon without its own border

-- Colours that depend on the kind of card: the body, the type line's text,
-- keywords, rules text and the flavour line on a card with no rules.
local KIND = {
  unit = { body = "CardUnit", type = { 1, 0.93, 0.77 }, kw = "|cff183a78", rules = { 0.16, 0.11, 0.06 },
    flavor = { 0.47, 0.38, 0.26 } },
  tactic = { body = "CardTactic", type = { 0.91, 0.92, 1 }, kw = "|cff3c2882", rules = { 0.12, 0.10, 0.2 },
    flavor = { 0.36, 0.34, 0.5 } },
}

local function place(fs, card, box, inset)
  inset = inset or { 0, 0, 0, 0 }
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", card, "TOPLEFT", (box[1] + inset[1]) * K, -(box[2] + inset[2]) * K)
  fs:SetSize((box[3] - box[1] - inset[1] - inset[3]) * K, (box[4] - box[2] - inset[2] - inset[4]) * K)
end

local function stat(b, file, point, x, y)
  local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
  t:SetTexture(UI.ART .. file)
  t:SetSize(STAT, STAT)
  t:SetPoint("CENTER", b, point, x, y)
  local fs = UI.Text(b, 16, "OUTLINE")
  fs:SetPoint("CENTER", t, "CENTER", 0, 0.5)
  return t, fs
end

-- The card's own glow, behind it (selected) or over it (under the mouse).
local function glow(b, layer, sub)
  local t = b:CreateTexture(nil, layer, nil, sub)
  t:SetPoint("TOPLEFT", -GLOW_PAD, GLOW_PAD)
  t:SetPoint("BOTTOMRIGHT", GLOW_PAD, -GLOW_PAD)
  t:SetTexture(UI.ART .. "CardGlow")
  t:SetTexCoord(0, 1, 0, GLOW_V)
  t:SetBlendMode("ADD")
  return t
end

function UI.CreateCard(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(UI.CARD_W, UI.CARD_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- selected: a gold glow round the card
  b.sel = glow(b, "BACKGROUND", -8)
  b.sel:SetVertexColor(1, 0.8, 0.2)
  b.sel:Hide()

  b.art = b:CreateTexture(nil, "BACKGROUND")
  b.art:SetPoint("TOPLEFT", UI.CARD_ART[1], -UI.CARD_ART[2])
  b.art:SetSize(UI.CARD_ART[3], UI.CARD_ART[4])
  b.art:SetTexCoord(unpack(UI.ICON_COORDS))

  -- holographic foil over the art, and a prismatic ring over the rim
  -- (shown on holographic cards only; UI.HoloTick animates them)
  b.foil = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.foil:SetAllPoints(b.art)
  b.foil:SetTexture(UI.ART .. "Holo")
  b.foil:SetBlendMode("ADD")
  b.foil:SetAlpha(0.42)
  b.foil:Hide()

  b.base = b:CreateTexture(nil, "BORDER")
  b.base:SetAllPoints()
  b.base:SetTexture(UI.ART .. "CardUnit")
  b.base:SetTexCoord(0, 1, 0, V)

  b.rim = b:CreateTexture(nil, "ARTWORK")
  b.rim:SetAllPoints()
  b.rim:SetTexture(UI.ART .. "CardRim")
  b.rim:SetTexCoord(0, 1, 0, V)

  b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.ring:SetAllPoints()
  b.ring:SetTexture(UI.ART .. "HoloRing")
  b.ring:SetTexCoord(0, 1, 0, V)
  b.ring:SetBlendMode("ADD")
  b.ring:Hide()

  b.name = UI.Text(b, 11)
  place(b.name, b, NAME_BOX, { 8, 1, 8, 1 })
  b.name:SetJustifyH("CENTER")
  b.name:SetJustifyV("MIDDLE")
  b.name:SetWordWrap(true)
  b.name:SetTextColor(0.99, 0.96, 0.87)

  -- "Beast unit", "Tactic: enemy lane"
  b.typeText = UI.Text(b, 9)
  place(b.typeText, b, TYPE_BOX, { 5, 0, 5, 1 })
  b.typeText:SetJustifyH("CENTER")
  b.typeText:SetJustifyV("MIDDLE")
  b.typeText:SetWordWrap(false)

  -- keywords and the card's short rules text, in the box
  b.text = UI.Text(b, 10)
  b.text:SetJustifyH("CENTER")
  b.text:SetJustifyV("MIDDLE")
  b.text:SetWordWrap(true)
  b.text:SetShadowOffset(0, 0)

  b.gem = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.gem:SetTexture(UI.ART .. "RarityGem")
  b.gem:SetSize(GEM, GEM)

  b.costBg, b.cost = stat(b, "StatCost", "TOPLEFT", 14, -14)
  b.atkBg, b.atk = stat(b, "StatAttack", "BOTTOMLEFT", 15, 16)
  b.hpBg, b.hp = stat(b, "StatHealth", "BOTTOMRIGHT", -15, 16)

  -- a word over the art ("Frozen", "dies"), on a dark bar so it reads
  b.tagBg = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.tagBg:SetTexture(UI.ART .. "Pill")
  b.tagBg:SetVertexColor(0, 0, 0, 0.75)
  b.tagBg:Hide()
  b.tag = UI.Text(b, 11, "OUTLINE")
  b.tag:SetPoint("CENTER", b, "TOPLEFT", UI.CARD_W / 2, -(ART_BOX[2] * K + 10))
  b.tagBg:SetPoint("CENTER", b.tag, "CENTER", 0, 0)

  -- frozen: ice over the card; stealthed: a dark veil over the art
  b.frost = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.frost:SetPoint("TOPLEFT", 1, -1)
  b.frost:SetPoint("BOTTOMRIGHT", -1, 1)
  b.frost:SetTexture(UI.ART .. "Frost")
  b.frost:SetVertexColor(0.75, 0.9, 1)
  b.frost:SetAlpha(0.75)
  b.frost:Hide()
  b.veil = b:CreateTexture(nil, "BACKGROUND", nil, 2)
  b.veil:SetAllPoints(b.art)
  b.veil:SetColorTexture(0.12, 0.05, 0.2, 0.55)
  b.veil:Hide()

  -- can't be played: a shade over everything, the text included
  b.shade = CreateFrame("Frame", nil, b)
  b.shade:SetPoint("TOPLEFT", 2, -2)
  b.shade:SetPoint("BOTTOMRIGHT", -2, 2)
  b.shade:SetFrameLevel(b:GetFrameLevel() + 2)
  b.shade:EnableMouse(false)
  b.dim = b.shade:CreateTexture(nil, "OVERLAY")
  b.dim:SetAllPoints()
  b.dim:SetColorTexture(0, 0, 0, 0.55)
  b.shade:Hide()

  -- card back (unopened pack cards)
  b.back = CreateFrame("Frame", nil, b)
  b.back:SetAllPoints()
  b.back:SetFrameLevel(b:GetFrameLevel() + 3)
  b.back.tex = b.back:CreateTexture(nil, "ARTWORK")
  b.back.tex:SetAllPoints()
  b.back.tex:SetTexture(UI.ART .. "CardBack")
  b.back.tex:SetTexCoord(0, 1, 0, V)
  b.back.text = UI.Text(b.back, 10)
  b.back.text:SetPoint("BOTTOM", 0, 14)
  b.back.text:SetText(L["click"])
  b.back.text:SetTextColor(0.85, 0.75, 0.5)
  b.back:EnableMouse(false)
  b.back:Hide()

  -- under the mouse: a gold glow round the card (textures in the HIGHLIGHT
  -- layer are only drawn while the mouse is over the frame)
  b.glow = glow(b, "HIGHLIGHT")
  b.glow:SetVertexColor(1, 0.85, 0.4, 0.75)
  UI.AttachFlash(b)
  UI.AttachFloat(b)
  UI.AttachLunge(b)
  UI.AttachShake(b)

  for k, v in pairs(Card) do b[k] = v end
  b.baseScale = 1
  b:SetScript("OnEnter", b.ShowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- What's printed in the box: its keywords, then its short rules text. A unit
-- with neither shows its flavour line instead.
local function faceText(c, kw)
  local look = KIND[c.type] or KIND.unit
  local names = {}
  for _, k in ipairs(Cards.KeywordList(kw)) do names[#names + 1] = k.name end
  local parts = {}
  if #names > 0 then parts[1] = look.kw .. table.concat(names, ", ") .. "|r" end
  if c.short then parts[#parts + 1] = c.short end
  return table.concat(parts, "\n")
end
UI.FaceText = faceText

local TACTIC_LABEL = { enemy = L["Tactic: enemy lane"], friend = L["Tactic: your unit"], none = L["Tactic"] }

-- The type line: "Beast unit", "Unit", "Tactic: enemy lane".
function UI.TypeLine(c)
  if c.type == "unit" then
    return c.tribe and L["%s unit"]:format(Cards.TRIBES[c.tribe]) or L["Unit"]
  end
  return TACTIC_LABEL[c.target] or L["Tactic"]
end

-- Body, box and colours for a unit or a tactic.
function Card:SetKind(kind)
  if self.kind == kind then return end
  self.kind = kind
  local look = KIND[kind]
  self.base:SetTexture(UI.ART .. look.body)
  self.typeText:SetTextColor(look.type[1], look.type[2], look.type[3])
  place(self.text, self, TEXT_BOX[kind], TEXT_INSET[kind])
  self.gem:ClearAllPoints()
  self.gem:SetPoint("CENTER", self, "TOPLEFT", UI.CARD_W / 2, -GEM_Y[kind] * K)
  local unit = kind == "unit"
  self.atk:SetShown(unit); self.atkBg:SetShown(unit); self.hp:SetShown(unit); self.hpBg:SetShown(unit)
end

-- id: card; unit: a unit on the board (current stats) or nil; st: the game or
-- replay view the unit is in (for attack bonuses); holo: draw it holographic.
function Card:SetCard(id, unit, st, holo)
  local c = Cards.byId[id]
  self.cardId, self.unit, self.st = id, unit, st
  self.back:Hide()
  self:SetHolo(holo)
  self:SetKind(c.type == "unit" and "unit" or "tactic")
  local look = KIND[self.kind]
  self.art:SetTexture(UI.CardIcon(id))
  self.art:SetVertexColor(1, 1, 1)
  self.art:SetDesaturated(false)
  self.cost:SetText(c.cost)
  UI.FitText(self.name, c.name, 7)
  UI.FitText(self.typeText, UI.TypeLine(c), 6)
  self.border = BORDER_COLOR[c.rarity]
  self.rim:SetVertexColor(self.border[1], self.border[2], self.border[3])
  local rc = UI.RARITY_COLOR[c.rarity]
  self.gem:SetVertexColor(rc[1], rc[2], rc[3])
  self:SetTag(nil)
  self.frost:Hide()
  self.veil:Hide()
  local kw = c.kw
  if c.type == "unit" then
    local atk, hp, maxHp = c.atk, c.hp, c.hp
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
    if unit and unit.frozen then
      self.art:SetVertexColor(0.55, 0.75, 1)
      self.frost:Show()
      self:SetTag(L["Frozen"], 0.6, 0.85, 1)
    elseif unit and kw.stealth then
      self.art:SetVertexColor(0.6, 0.6, 0.7)
      self.veil:Show()
      self:SetTag(L["Stealth"], 0.8, 0.7, 1)
    end
  end
  local text = faceText(c, kw)
  if text == "" and c.flavor then
    self.text:SetTextColor(look.flavor[1], look.flavor[2], look.flavor[3])
    UI.FitText(self.text, L["\"%s\""]:format(c.flavor), 7)
  else
    self.text:SetTextColor(look.rules[1], look.rules[2], look.rules[3])
    UI.FitText(self.text, text, 7)
  end
  self:SetDim(false)
  self:SetAlpha(1)
  self:Show()
end

function Card:SetBack(text)
  self.cardId, self.unit = nil, nil
  self:SetHolo(false)
  self:SetSelected(false)
  self.back.text:SetText(text or L["click"])
  self.back:Show()
  self:Show()
end

-- The card's size on its page (1 is UI.CARD_W x UI.CARD_H). Effects that
-- pop the card (FX.Arrive) scale it relative to this.
function Card:SetBaseScale(s)
  self.baseScale = s or 1
  self:SetScale(self.baseScale)
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
  self.shade:SetShown(on and true or false)
end

-- A gold glow round the card while it's selected.
function Card:SetSelected(on)
  self.sel:SetShown(on and true or false)
end

-- top: an optional { text, r, g, b } shown on a line above, in its own
-- colour: the unit's state when the forecast has a word too ("Frozen" over
-- "dies"), so neither hides the other.
function Card:SetTag(text, r, g, b, top)
  local fs = self.tag
  local shown = text and text ~= ""
  local w
  if shown and top then
    fs:SetText(top.text)
    w = fs:GetStringWidth() or 0
    fs:SetText(text)
    w = math.max(w, fs:GetStringWidth() or 0)
    fs:SetText(UI.Hex(top.r, top.g, top.b) .. top.text .. "|r\n" .. text)
  else
    fs:SetText(text or "")
    w = fs:GetStringWidth() or 0
  end
  fs:SetTextColor(r or 1, g or 1, b or 1)
  if shown then
    self.tagBg:SetSize(w + 14, top and 30 or 17)
    self.tagBg:Show()
  else
    self.tagBg:Hide()
  end
end

function Card:ShowTooltip()
  if not self.cardId then return end
  UI.CardTooltip(self, self.cardId, self.unit, self.st, self.tipExtra and self.tipExtra(self), self.holo)
end

-- ---------------------------------------------------------------------------
-- Card tooltip
-- ---------------------------------------------------------------------------
local TARGET_HINT = {
  enemy = L["Pick an enemy lane. It lands after the reveal, so it hits whatever is there by then."],
  friend = L["Pick one of your units, or a lane you're playing a unit into this round."],
}
local RARITY_NAME = { common = L["Common"], uncommon = L["Uncommon"], rare = L["Rare"], epic = L["Epic"], legendary = L["Legendary"] }
UI.RARITY_NAME = RARITY_NAME

function UI.CardTooltip(owner, id, unit, st, extra, holo)
  local c = Cards.byId[id]
  local tip = GameTooltip
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  local col = UI.RARITY_COLOR[c.rarity]
  tip:AddLine(c.name, col[1], col[2], col[3])
  if holo then tip:AddLine(UI.Rainbow(L["Holographic"])) end
  local rarity = c.collectible and RARITY_NAME[c.rarity] or L["Token"]
  local kind = c.type == "unit" and (c.tribe and L["%s unit"]:format(Cards.TRIBES[c.tribe]) or L["Unit"]) or L["Tactic"]
  tip:AddDoubleLine(L["%s, %s"]:format(kind, rarity), L["%d Supply"]:format(c.cost),
    0.65, 0.65, 0.65, 0.45, 0.65, 1)
  local kw = c.kw
  if c.type == "unit" then
    local atk, hp, maxHp = c.atk, c.hp, c.hp
    if unit then
      atk = st and R.Attack(st, unit) or unit.atk
      hp, maxHp, kw = unit.hp, unit.maxHp, unit.kw
    end
    tip:AddLine(L["Attack %d    Health %d/%d"]:format(atk, math.max(0, hp), maxHp), 1, 0.85, 0.4)
  end
  for _, k in ipairs(Cards.KeywordList(kw)) do
    tip:AddLine(L["%s: |cffffffff%s|r"]:format(k.name, k.text), 0.45, 0.85, 1, true)
  end
  if c.text then tip:AddLine(c.text, 1, 1, 1, true) end
  if c.type == "tactic" and TARGET_HINT[c.target] then tip:AddLine(TARGET_HINT[c.target], 0.6, 0.6, 0.6, true) end
  if unit then
    if unit.frozen then tip:AddLine(L["Frozen: won't strike this round."], 0.6, 0.85, 1, true) end
    if (unit.tmpAtk or 0) > 0 then tip:AddLine(L["+%d attack this round."]:format(unit.tmpAtk), 0.3, 1, 0.3) end
  end
  if c.flavor then tip:AddLine(L["\"%s\""]:format(c.flavor), 0.55, 0.55, 0.55, true) end
  if c.collectible and not unit then
    local o = c.signature and ns.OpponentById[c.signature]
    local packs = c.rarity == "legendary" and L["Very rarely found in packs."] or L["Not in packs."]
    if o then
      tip:AddLine(L["Signature card: earn %s's second star, or craft it. %s"]:format(o.short, packs), 1, 0.82, 0, true)
    elseif c.signature then
      tip:AddLine(L["Earn every star on the circuit, or craft it. %s"]:format(packs), 1, 0.82, 0, true)
    elseif c.rarity == "legendary" then
      tip:AddLine(packs, 1, 0.82, 0, true)
    end
  end
  if extra then
    for _, line in ipairs(extra) do tip:AddLine(line, 0.85, 0.85, 0.85, true) end
  end
  tip:Show()
end
