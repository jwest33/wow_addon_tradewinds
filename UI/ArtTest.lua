-- /deckhand art: shows the generated textures (Art/, made by tools/gen_art.py)
-- on real cards, to check that this client loads them and how they look at
-- game size. Temporary: goes away once the card face is rebuilt on them.
local _, ns = ...
local UI = ns.UI

local ART = "Interface\\AddOns\\" .. ns.ADDON_FOLDER .. "\\Art\\"
local W, H = 90, 126
local K = W / 256            -- texture pixels to screen units
local V = 358 / 512          -- the card fills the top of its 256x512 texture
local SAMPLES = { "croc", "strider", "bruiser", "kazzak", "vancleef" }
local frame

local function layer(parent, file, level, sub)
  local t = parent:CreateTexture(nil, level, nil, sub or 0)
  t:SetTexture(ART .. file)
  return t
end

local function badge(card, file, point, x, y, r, g, b, value)
  local t = layer(card, file, "OVERLAY", 1)
  t:SetSize(24, 24)
  t:SetPoint("CENTER", card, point, x, y)
  t:SetVertexColor(r, g, b)
  local fs = UI.Text(card, 13, "OUTLINE")
  fs:SetPoint("CENTER", t, "CENTER", 0, 0)
  fs:SetText(value)
end

local function sampleCard(parent, id)
  local c = ns.Cards.byId[id]
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(W, H)
  local art = f:CreateTexture(nil, "BACKGROUND")
  art:SetPoint("TOPLEFT", 16 * K, -16 * K)
  art:SetSize(224 * K, 164 * K)
  art:SetTexture(UI.CardIcon(id))
  art:SetTexCoord(0.08, 0.92, 0.19, 0.81)
  local base = layer(f, "CardBase", "BORDER")
  base:SetAllPoints()
  base:SetTexCoord(0, 1, 0, V)
  local border = layer(f, "CardBorder", "ARTWORK")
  border:SetAllPoints()
  border:SetTexCoord(0, 1, 0, V)
  local col = UI.RARITY_COLOR[c.rarity]
  border:SetVertexColor(col[1], col[2], col[3])
  local name = UI.Text(f, 8, "OUTLINE")
  name:SetPoint("CENTER", f, "TOP", 0, -189 * K)
  name:SetWidth(232 * K)
  name:SetWordWrap(false)
  name:SetText(c.name)
  local text = UI.Text(f, 8)
  text:SetPoint("CENTER", f, "TOP", 0, -264 * K)
  text:SetWidth(216 * K)
  text:SetTextColor(0.18, 0.13, 0.08)
  text:SetShadowOffset(0, 0)
  local names = {}
  for _, k in ipairs(ns.Cards.KeywordList(c.kw)) do names[#names + 1] = k.name end
  text:SetText(#names > 0 and table.concat(names, ", ") or (c.text or ""))
  badge(f, "Gem", "TOPLEFT", 7, -7, 0.24, 0.47, 1, c.cost)
  badge(f, "BadgeAttack", "BOTTOMLEFT", 7, 7, 1, 0.59, 0.16, c.atk)
  badge(f, "BadgeHealth", "BOTTOMRIGHT", -7, 7, 0.88, 0.2, 0.2, c.hp)
  return f
end

function UI.ArtTest()
  if frame then
    frame:SetShown(not frame:IsShown())
    return
  end
  frame = CreateFrame("Frame", "DeckhandArtTest", UIParent)
  frame:SetSize(40 + (#SAMPLES + 1) * (W + 14), H + 70)
  frame:SetPoint("CENTER", 0, 120)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  local wood = frame:CreateTexture(nil, "BACKGROUND")
  wood:SetAllPoints()
  wood:SetTexture(ART .. "Board")
  wood:SetTexCoord(0, 1, 0, 0.4)
  local title = UI.Text(frame, 11)
  title:SetPoint("TOP", 0, -8)
  title:SetText("Deckhand art test: a wood background, five framed cards and a card back. /deckhand art closes it.")
  title:SetWidth(frame:GetWidth() - 20)
  for i, id in ipairs(SAMPLES) do
    local card = sampleCard(frame, id)
    card:SetPoint("TOPLEFT", 27 + (i - 1) * (W + 14), -44)
  end
  local back = layer(frame, "CardBack", "ARTWORK")
  back:SetSize(W, H)
  back:SetPoint("TOPLEFT", 27 + #SAMPLES * (W + 14), -44)
  back:SetTexCoord(0, 1, 0, V)
end
