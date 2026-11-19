-- A small, strict WoW API mock for the UI smoke test. Widgets only have the
-- methods listed here (all real WoW methods); calling anything else raises an
-- error, so a misspelt method fails the test instead of passing silently.
MOCK = { now = 1000, timers = {}, frames = {}, chat = {}, errors = {}, onTaxi = false, speed = 0, events = {} }

local function noop() end

-- methods every region has
local REGION = {
  "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight", "SetAlpha", "GetAlpha",
  "Show", "Hide", "SetShown", "IsShown", "IsVisible", "GetWidth", "GetHeight", "GetLeft", "GetTop", "GetCenter",
  "GetParent", "SetParent", "GetEffectiveScale", "CreateAnimationGroup", "SetScale",
}
local FRAME = {
  "CreateTexture", "CreateFontString", "SetScript", "GetScript", "HookScript", "EnableMouse", "EnableMouseWheel",
  "SetFrameLevel", "GetFrameLevel", "SetFrameStrata", "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent",
  "SetMovable", "StartMoving", "StopMovingOrSizing", "RegisterForDrag", "SetClampedToScreen", "SetToplevel",
  "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
  -- Button
  "RegisterForClicks", "SetText", "GetText", "SetEnabled", "IsEnabled", "Enable", "Disable", "SetHighlightTexture",
  "SetNormalTexture", "SetPushedTexture", "SetNormalFontObject", "SetHighlightFontObject", "Click",
  -- StatusBar
  "SetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues", "SetValue", "GetValue",
  -- ScrollingMessageFrame
  "AddMessage", "Clear", "SetFading", "SetMaxLines", "ScrollUp", "ScrollDown", "SetFont", "SetJustifyH",
  -- GameTooltip
  "SetOwner", "AddLine", "AddDoubleLine", "NumLines",
  -- models
  "SetCreature", "GetDisplayInfo", "SetUnit", "ClearModel",
}
local TEXTURE = { "SetTexture", "GetTexture", "SetColorTexture", "SetTexCoord", "SetVertexColor", "SetDesaturated",
  "SetBlendMode", "SetDrawLayer" }
local FONTSTRING = { "SetFont", "SetText", "GetText", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap",
  "SetShadowOffset", "SetSpacing", "GetStringWidth", "SetFontObject" }
local ANIMGROUP = { "CreateAnimation", "Play", "Stop", "SetScript", "IsPlaying" }
local ANIM = { "SetFromAlpha", "SetToAlpha", "SetDuration", "SetStartDelay", "SetOffset", "SetOrder" }

local function strict(obj, kind, lists)
  local allowed = {}
  for _, l in ipairs(lists) do for _, m in ipairs(l) do allowed[m] = true end end
  return setmetatable(obj, { __index = function(_, k)
    if allowed[k] then return noop end
    -- unset fields read as nil, like in the game; unknown Methods are errors
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    error(("%s has no method %s"):format(kind, tostring(k)), 2)
  end })
end

local function region(kind, parent, lists)
  local o = { kind = kind, shown = true, parent = parent, alpha = 1, w = 10, h = 10, level = parent and (parent.level or 0) + 1 or 0 }
  function o:Show()
    local was = self.shown
    self.shown = true
    local sc = rawget(self, "scripts"); if not was and sc and sc.OnShow then self.scripts.OnShow(self) end
  end
  function o:Hide()
    local sc = rawget(self, "scripts"); if self.shown and sc and sc.OnHide then self.scripts.OnHide(self) end
    self.shown = false
  end
  function o:SetShown(v) if v then self:Show() else self:Hide() end end
  function o:IsShown() return self.shown end
  function o:IsVisible()
    local f = self
    while f do
      if not f.shown then return false end
      f = f.parent
    end
    return true
  end
  function o:SetAlpha(a) self.alpha = a end
  function o:GetAlpha() return self.alpha end
  function o:SetSize(w, h) self.w, self.h = w, h end
  function o:SetWidth(w) self.w = w end
  function o:SetHeight(h) self.h = h end
  function o:GetWidth() return self.w end
  function o:GetHeight() return self.h end
  function o:GetScale() return 1 end
  function o:GetLeft() return 100 end
  function o:GetTop() return 700 end
  function o:GetCenter() return 400, 300 end
  function o:GetEffectiveScale() return 1 end
  function o:GetParent() return self.parent end
  function o:CreateAnimationGroup()
    local ag = strict({ scripts = {} }, "AnimationGroup", { ANIMGROUP })
    function ag:CreateAnimation() return strict({}, "Animation", { ANIM }) end
    function ag:SetScript(k, fn) self.scripts[k] = fn end
    function ag:Play() if self.scripts.OnFinished then self.scripts.OnFinished(self) end end
    return ag
  end
  return strict(o, kind, lists)
end

function CreateFrame(kind, name, parent, template)
  local f = region(kind, parent, { REGION, FRAME })
  f.scripts, f.events, f.text = {}, {}, ""
  f.enabled = true
  f.template = template
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = function(...)
      if old then old(...) end
      fn(...)
    end
  end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetFrameLevel(n) self.level = n end
  function f:GetFrameLevel() return self.level end
  function f:SetText(t) self.text = t end
  function f:GetText() return self.text end
  function f:SetEnabled(v) self.enabled = v and true or false end
  function f:IsEnabled() return self.enabled end
  function f:SetValue(v) self.value = v end
  function f:CreateTexture()
    local t = region("Texture", self, { REGION, TEXTURE })
    function t:SetTexture(x) self.tex = x end
    function t:GetTexture() return self.tex end
    return t
  end
  function f:CreateFontString()
    local fs = region("FontString", self, { REGION, FONTSTRING })
    fs.text, fs.hasFont = "", false
    function fs:SetFont() self.hasFont = true end
    function fs:SetFontObject() self.hasFont = true end
    function fs:SetText(t)
      if not self.hasFont then error("SetText on a FontString without a font", 2) end
      self.text = t
    end
    function fs:GetText() return self.text end
    return fs
  end
  function f:AddMessage(msg) self.lines = self.lines or {}; table.insert(self.lines, msg) end
  function f:Clear() self.lines = {} end
  function f:Click(button)
    if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
  end
  -- models: answer the creature id + 10000 after the third read
  function f:SetCreature(id) self.creature, self.reads = id, 0 end
  function f:GetDisplayInfo()
    if not self.creature then return 0 end
    self.reads = self.reads + 1
    return self.reads >= 3 and (self.creature + 10000) or 0
  end
  if template == "UIPanelButtonTemplate" or template == "UIPanelCloseButton" then
    f.Text = f:CreateFontString()
  end
  if name then _G[name] = f end
  table.insert(MOCK.frames, f)
  return f
end

function MOCK.Fire(event, ...)
  for _, f in ipairs(MOCK.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- timers ---------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(d, fn) table.insert(MOCK.timers, { at = MOCK.now + d, fn = fn }) end
function C_Timer.NewTicker(d, fn)
  local t = { cancelled = false }
  function t:Cancel() self.cancelled = true end
  local function again()
    if t.cancelled then return end
    fn()
    if not t.cancelled then C_Timer.After(d, again) end
  end
  C_Timer.After(d, again)
  return t
end
function MOCK.Advance(sec)
  local stop = MOCK.now + sec
  while true do
    table.sort(MOCK.timers, function(a, b) return a.at < b.at end)
    local t = MOCK.timers[1]
    if not t or t.at > stop then break end
    table.remove(MOCK.timers, 1)
    MOCK.now = math.max(MOCK.now, t.at)
    t.fn()
  end
  MOCK.now = stop
end
function GetTime() return MOCK.now end

-- globals --------------------------------------------------------------------
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip:Hide()
function GameTooltip:SetOwner(o) self.owner = o; self.lines = {} end
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
function GameTooltip:AddDoubleLine(a, b) table.insert(self.lines, a .. " | " .. b) end
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame", UIParent)
function UIErrorsFrame:AddMessage(m) table.insert(MOCK.errors, m) end
DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(m) table.insert(MOCK.chat, m) end
GameFontDisableSmall, GameFontHighlightSmall = {}, {}
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BackdropTemplateMixin = {}
SOUNDKIT = { IG_SPELLBOOK_OPEN = 1, IG_QUEST_LIST_COMPLETE = 2, IG_BACKPACK_OPEN = 3 }
function PlaySound() end
ERR_NEWTAXIPATH = "New flight path discovered!"
SlashCmdList = {}
-- the .toc's metadata, read from the real file
C_AddOns = {}
function C_AddOns.GetAddOnMetadata(addon, field)
  for line in io.lines(ROOT .. "/" .. addon .. ".toc") do
    local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if k == field then return v end
  end
end
StaticPopupDialogs = {}
function StaticPopup_Show(name, arg) MOCK.popup = { name = name, arg = arg } end

function date(fmt) return "2026-11-19" end
function time() return 1790000000 end
function UnitName() return "Tester" end
function UnitOnTaxi() return MOCK.onTaxi end
function GetUnitSpeed() return MOCK.speed end
function issecretvalue() return false end
function GetCursorPosition() return 500, 400 end

-- a few icons are "missing" so the fallbacks get exercised
MOCK.missingIcons = { ["Interface\\Icons\\INV_Misc_Head_Kobold_01"] = true, ["Interface\\Icons\\INV_Misc_Head_Gnoll_01"] = true }
function GetFileIDFromPath(path)
  if MOCK.missingIcons[path] then return nil end
  return 100000 + #path
end
function SetPortraitTextureFromCreatureDisplayID(tex, id) tex:SetTexture("portrait:" .. id) end
