-- The main window (tabs: Play, Cards, Packs), the flight / pack toast and the
-- minimap button.
local _, ns = ...
local UI = ns.UI

local W, H = 800, 600
local main, content
local tabs, pages = {}, {}
local TABS = {
  { key = "play", label = "Play", module = "Game" },
  { key = "cards", label = "Cards", module = "Binder" },
  { key = "packs", label = "Packs", module = "Packs" },
  { key = "options", label = "Options", module = "Options" },
}

-- The saved position is the window's top left corner in screen units, so it
-- stays put when the window's scale changes.
local function savePosition()
  local l, t = main:GetLeft(), main:GetTop()
  if l and t then
    local s = main:GetScale() or 1
    main:ClearAllPoints()
    main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    ns.db.settings.point = { l * s, t * s }
  end
end

local function placeWindow()
  main:ClearAllPoints()
  local p = ns.db.settings.point
  local s = main:GetScale() or 1
  if p then main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1] / s, p[2] / s)
  else main:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
end

local function tabButton(def, i)
  local b = CreateFrame("Button", nil, main, UI.TEMPLATE)
  b:SetSize(74, 22)
  b:SetPoint("TOPLEFT", main, "TOPLEFT", 130 + (i - 1) * 78, -6)
  UI.Backdrop(b, { 0.12, 0.10, 0.08, 1 }, { 0.4, 0.33, 0.2 })
  b.text = UI.Text(b, 12)
  b.text:SetPoint("CENTER")
  b.text:SetText(def.label)
  b.badge = UI.Text(b, 9, "OUTLINE")
  b.badge:SetPoint("RIGHT", b, "RIGHT", -5, 0)
  b.badge:SetTextColor(1, 0.82, 0)
  b:SetScript("OnClick", function()
    UI.Sound("tab")
    UI.SelectTab(def.key)
  end)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  return b
end

local function create()
  main = CreateFrame("Frame", "DeckhandFrame", UIParent, UI.TEMPLATE)
  main:SetSize(W, H)
  main:SetFrameStrata("HIGH")
  main:SetToplevel(true)
  main:SetClampedToScreen(true)
  main:EnableMouse(true)
  main:SetMovable(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", function(self) self:StartMoving() end)
  main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  UI.Backdrop(main, { 0.045, 0.04, 0.035, 1 }, { 0.55, 0.45, 0.25 }, true)
  main:SetScale(ns.db.settings.scale or 1)
  placeWindow()

  local icon = main:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 10, -7)
  icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  local title = UI.Text(main, 16)
  title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  title:SetText("Deckhand")
  title:SetTextColor(1, 0.82, 0)

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)

  local line = main:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.55, 0.45, 0.25, 0.6)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 6, -31)
  line:SetPoint("TOPRIGHT", -6, -31)

  content = CreateFrame("Frame", nil, main)
  content:SetPoint("TOPLEFT", 8, -36)
  content:SetPoint("BOTTOMRIGHT", -8, 8)

  for i, def in ipairs(TABS) do
    tabs[def.key] = tabButton(def, i)
    local m = UI[def.module]
    local page = CreateFrame("Frame", nil, content)
    page:SetAllPoints()
    page:Hide()
    m.Build(page)
    pages[def.key] = { frame = page, module = m }
  end

  main:SetScript("OnHide", function()
    GameTooltip:Hide()
    if UI.Game.OnHide then UI.Game.OnHide() end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "DeckhandFrame") end
  main:Hide()
end

function UI.SelectTab(key)
  if not main then create() end
  if not pages[key] then key = "play" end
  UI.tab = key
  for k, p in pairs(pages) do
    p.frame:SetShown(k == key)
    local t = tabs[k]
    if k == key then
      t:SetBackdropBorderColor(1, 0.82, 0, 1)
      t.text:SetTextColor(1, 0.82, 0)
    else
      t:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
      t.text:SetTextColor(0.85, 0.85, 0.85)
    end
  end
  UI.Refresh()
end

function UI.Refresh()
  if not main then return end
  local packs = ns.db.packs
  tabs.packs.badge:SetText(packs > 0 and tostring(packs) or "")
  if main:IsShown() and UI.tab then pages[UI.tab].module.Refresh() end
end

function UI.Show(key)
  if not main then create() end
  main:Show()
  UI.SelectTab(key or UI.tab or "play")
  UI.Toast(nil)
end

function UI.Hide()
  if main then main:Hide() end
end

function UI.IsShown()
  return main and main:IsShown() or false
end

function UI.Toggle()
  if UI.IsShown() then UI.Hide() else UI.Show() end
end

function UI.ApplyScale()
  if not main then return end
  main:SetScale(ns.db.settings.scale or 1)
  placeWindow()
end

function UI.ResetPosition()
  ns.db.settings.point = nil
  if main then placeWindow() end
end

function UI.Init()
  UI.UpdateMinimapButton()
end

-- ---------------------------------------------------------------------------
-- Toast: "Deal a hand while you fly?" / "+1 card pack"
-- ---------------------------------------------------------------------------
local toast, toastToken = nil, 0

local function makeToast()
  toast = CreateFrame("Frame", "DeckhandToast", UIParent, UI.TEMPLATE)
  toast:SetSize(300, 46)
  toast:SetPoint("TOP", UIParent, "TOP", 0, -110)
  toast:SetFrameStrata("DIALOG")
  UI.Backdrop(toast, { 0.05, 0.04, 0.03, 0.95 }, { 0.75, 0.6, 0.25 }, true)
  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(32, 32)
  toast.icon:SetPoint("LEFT", 8, 0)
  toast.icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  toast.title = UI.Text(toast, 12)
  toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 8, 0)
  toast.title:SetTextColor(1, 0.82, 0)
  toast.text = UI.Text(toast, 10)
  toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
  toast.text:SetWidth(170)
  toast.text:SetJustifyH("LEFT")
  toast.go = UI.Button(toast, "Play", 56, 20)
  toast.go:SetPoint("RIGHT", -28, 0)
  toast.x = CreateFrame("Button", nil, toast, "UIPanelCloseButton")
  toast.x:SetSize(22, 22)
  toast.x:SetPoint("RIGHT", -3, 0)
  toast.x:SetScript("OnClick", function() toast:Hide() end)
  toast:Hide()
end

-- kind: "flight" | "pack" | nil (hide); n: how many packs
function UI.Toast(kind, why, n)
  if not kind then
    if toast then toast:Hide() end
    return
  end
  if UI.IsShown() then return end
  if not toast then makeToast() end
  if kind == "flight" then
    toast.title:SetText("Deckhand")
    toast.text:SetText(ns.db.match and "Your game is waiting. Play while you fly?" or "Deal a hand while you fly?")
    toast.go:SetText("Play")
    toast.go:SetScript("OnClick", function() UI.Show("play") end)
  else
    n = n or 1
    toast.title:SetText(("+%d card pack%s"):format(n, n == 1 and "" or "s"))
    toast.text:SetText(why and ("For " .. why .. ".") or "")
    toast.go:SetText("Open")
    toast.go:SetScript("OnClick", function() UI.Show("packs") end)
  end
  toast:Show()
  toastToken = toastToken + 1
  local mine = toastToken
  C_Timer.After(20, function() if toastToken == mine and toast then toast:Hide() end end)
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
local mm

local function placeMinimap()
  local a = math.rad(ns.db.settings.minimapAngle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 10
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function makeMinimap()
  mm = CreateFrame("Button", "DeckhandMinimapButton", Minimap)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  local bg = mm:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = mm:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER")
  icon:SetTexture(UI.Icon({ "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01", "Interface\\Icons\\INV_Misc_Bag_10" }))
  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  mm:SetScript("OnClick", function(_, button)
    if button == "RightButton" then UI.Show("packs") else UI.Toggle() end
  end)
  mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      ns.db.settings.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
      placeMinimap()
    end)
  end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Deckhand")
    if ns.db.match then GameTooltip:AddLine("A game is in progress.", 0.4, 1, 0.4) end
    if ns.db.packs > 0 then GameTooltip:AddLine(("%d unopened pack%s"):format(ns.db.packs, ns.db.packs == 1 and "" or "s"), 1, 0.82, 0) end
    GameTooltip:AddLine("Click: play.  Right-click: packs.  Drag: move.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.UpdateMinimapButton()
  if not Minimap then return end
  if not ns.db.settings.minimap then
    if mm then mm:Hide() end
    return
  end
  if not mm then makeMinimap() end
  placeMinimap()
  mm:Show()
end
