-- The Options tab: everything that used to be a slash command only.
local _, ns = ...
local UI = ns.UI

local O = {}
UI.Options = O

local page
local checks, ctl = {}, {}

local TOGGLES = {
  { "sound", "Sound", "Card, combat and pack sounds." },
  { "portraits", "Creature portraits", "Show a portrait of the creature beside a card's tooltip, when it has one. Off by default." },
  { "forecast", "Round forecast", "While planning: lane markers, the predicted Morale change and units marked \"dies\"." },
  { "toast", "Offer a game on take-off", "Show a small prompt when a flight starts." },
  { "hideOnLand", "Close on landing", "Close the window when your flight ends. Your game is saved." },
  { "hideInCombat", "Close in combat", "Close the window when combat starts." },
  { "minimap", "Minimap button", "Show the Deckhand button on the minimap." },
}

function O.Set(key, value)
  local S = ns.db.settings
  S[key] = value
  if key == "minimap" then UI.UpdateMinimapButton() end
  if key == "scale" then UI.ApplyScale() end
  UI.Refresh()
end

local function check(parent, def, y)
  local key, label, tip = def[1], def[2], def[3]
  local b = CreateFrame("Button", nil, parent, UI.TEMPLATE)
  b:SetSize(330, 22)
  b:SetPoint("TOPLEFT", 12, y)
  b.box = CreateFrame("Frame", nil, b, UI.TEMPLATE)
  b.box:SetSize(16, 16)
  b.box:SetPoint("LEFT", 0, 0)
  UI.Backdrop(b.box, { 0.03, 0.03, 0.03, 1 }, { 0.6, 0.5, 0.3 })
  b.mark = b.box:CreateTexture(nil, "ARTWORK")
  b.mark:SetPoint("TOPLEFT", 3, -3)
  b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  b.mark:SetColorTexture(1, 0.82, 0, 1)
  b.label = UI.Text(b, 12)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
  b.label:SetText(label)
  b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
  b:SetScript("OnClick", function()
    O.Set(key, not ns.db.settings[key])
    UI.Sound("lock")
  end)
  UI.SimpleTooltip(b, label, tip)
  checks[key] = b
  return b
end

function O.Refresh()
  if not page then return end
  local S = ns.db.settings
  for key, b in pairs(checks) do b.mark:SetShown(S[key] and true or false) end
  for i, b in ipairs(ctl.speed) do b:SetEnabled(S.speed ~= i) end
  ctl.scale:SetText(("%d%%"):format(math.floor((S.scale or 1) * 100 + 0.5)))
  ctl.smaller:SetEnabled((S.scale or 1) > 0.61)
  ctl.bigger:SetEnabled((S.scale or 1) < 1.49)
end

function O.Build(parent)
  page = parent
  local title = UI.Text(page, 14)
  title:SetPoint("TOPLEFT", 6, -4)
  title:SetText("Options")
  title:SetTextColor(1, 0.82, 0)

  for i, def in ipairs(TOGGLES) do check(page, def, -34 - (i - 1) * 28) end

  local x, y = 400, -34
  local sp = UI.Text(page, 12)
  sp:SetPoint("TOPLEFT", x, y - 3)
  sp:SetText("Round replay speed")
  ctl.speed = {}
  for i = 1, 3 do
    local b = UI.Button(page, i .. "x", 44, 22, function() O.Set("speed", i) end)
    b:SetPoint("TOPLEFT", x + 150 + (i - 1) * 48, y)
    ctl.speed[i] = b
  end

  y = y - 36
  local sc = UI.Text(page, 12)
  sc:SetPoint("TOPLEFT", x, y - 3)
  sc:SetText("Window size")
  ctl.smaller = UI.Button(page, "-", 30, 22, function()
    O.Set("scale", math.max(0.6, math.floor(((ns.db.settings.scale or 1) - 0.1) * 10 + 0.5) / 10))
  end)
  ctl.smaller:SetPoint("TOPLEFT", x + 150, y)
  ctl.scale = UI.Text(page, 12)
  ctl.scale:SetPoint("LEFT", ctl.smaller, "RIGHT", 10, 0)
  ctl.scale:SetWidth(44)
  ctl.bigger = UI.Button(page, "+", 30, 22, function()
    O.Set("scale", math.min(1.5, math.floor(((ns.db.settings.scale or 1) + 0.1) * 10 + 0.5) / 10))
  end)
  ctl.bigger:SetPoint("LEFT", ctl.scale, "RIGHT", 10, 0)

  y = y - 36
  local center = UI.Button(page, "Move window to the middle", 220, 22, function()
    UI.ResetPosition()
  end)
  center:SetPoint("TOPLEFT", x, y)

  y = y - 30
  local tips = UI.Button(page, "Show the first-time tips again", 220, 22, function()
    ns.db.settings.seenRules, ns.db.settings.seenLaneTip = nil, nil
    ns.Print("The tips will show again the next time you open the Play tab and start a match.")
  end)
  tips:SetPoint("TOPLEFT", x, y)

  local foot = UI.Text(page, 10)
  foot:SetPoint("BOTTOMLEFT", 6, 6)
  foot:SetTextColor(0.6, 0.6, 0.6)
  foot:SetText(("Deckhand %s.  /deckhand help lists the chat commands."):format(tostring(ns.VERSION)))

  page:SetScript("OnShow", function() O.Refresh() end)
end
