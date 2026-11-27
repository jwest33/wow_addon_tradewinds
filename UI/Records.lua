-- The Records tab: achievements by group, with progress bars, and the guild
-- board (Guild.lua): guildmates who have Tradewinds, how far they've got,
-- and a Challenge and a Trade button for each one online on your version.
local _, ns = ...
local L, Plural = ns.L, ns.Plural
local C = ns.Collection
local UI = ns.UI

local Rec = {}
UI.Records = Rec

local PAGE_W = 784
local GROUP_W, GROUP_H = 176, 44
local LIST_X = GROUP_W + 8
local LIST_W = PAGE_W - LIST_X
local ROW_H, ROW_GAP = 42, 3
local MAX_ROWS = 11   -- the most achievements a group has (tests/ui.lua checks)
local BOARD_ROWS = 18
local BOARD_ROW_H = 22

local page
local ctl = {}
local view = "ach"         -- "ach" | "guild"
local group = "circuit"
local sortKey, sortDesc = "points", true
local boardTop = 0         -- first row shown on the guild board

local EARNED_BG, OPEN_BG = { 0.16, 0.12, 0.05, 0.95 }, { 0.07, 0.065, 0.055, 0.9 }

-- ---------------------------------------------------------------------------
-- Achievements
-- ---------------------------------------------------------------------------
local function inGroup(key)
  local list = {}
  for _, a in ipairs(ns.Achievements) do
    if a.group == key then list[#list + 1] = a end
  end
  return list
end

-- Earned and points in a group.
local function groupTally(key)
  local n, all, pts = 0, 0, 0
  for _, a in ipairs(inGroup(key)) do
    all = all + 1
    if ns.db.ach[a.id] then n, pts = n + 1, pts + a.points end
  end
  return n, all, pts
end

function Rec.ShowGroup(key)
  for _, g in ipairs(ns.ACH_GROUPS) do
    if g.key == key then group = key end
  end
  view = "ach"
  Rec.Refresh()
end

function Rec.Group() return group end
function Rec.View() return view end

-- What a row says, for the tests: name, earned date or "have/goal".
function Rec.RowText(i)
  local r = ctl.rows and ctl.rows[i]
  if not (r and r:IsShown()) then return nil end
  return r.name:GetText() .. " | " .. (r.right:GetText() or "")
end

local function fmtProgress(a, have, goal)
  local k = a.scale or 1
  return ("%d / %d"):format(math.floor(have / k), math.floor(goal / k))
end

local function refreshAch()
  local pts, all, n, total = C.AchPoints(ns.db)
  UI.FitText(ctl.summary, L["Achievement points: %d of %d"]:format(pts, all) .. "    |cffb0b0b0"
    .. L["%d of %d earned"]:format(n, total) .. "|r", 9)
  for i, g in ipairs(ns.ACH_GROUPS) do
    local b = ctl.groups[i]
    local got, cnt, gp = groupTally(g.key)
    b.count:SetText(("%d / %d    %s"):format(got, cnt, Plural(gp, "%d point", "%d points"):format(gp)))
    if g.key == group then
      b:SetBackdropBorderColor(1, 0.82, 0, 1)
      b.name:SetTextColor(1, 0.82, 0)
    else
      b:SetBackdropBorderColor(0.35, 0.29, 0.18, 1)
      b.name:SetTextColor(0.9, 0.9, 0.9)
    end
  end
  local list = inGroup(group)
  for i = 1, MAX_ROWS do
    local r, a = ctl.rows[i], list[i]
    if a then
      local date = ns.db.ach[a.id]
      local have, goal = C.AchProgress(ns.db, a)
      r.a = a
      r.icon:SetTexture(UI.Icon(a.icon))
      r.icon:SetDesaturated(not date)
      r.icon:SetAlpha(date and 1 or 0.6)
      r.name:SetText(a.name)
      r.text:SetText(a.text)
      r.pts:SetText(a.points)
      local bg = date and EARNED_BG or OPEN_BG
      r:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
      if date then
        r:SetBackdropBorderColor(0.75, 0.6, 0.25, 1)
        r.name:SetTextColor(1, 0.82, 0)
        r.pts:SetTextColor(1, 0.82, 0)
        r.right:SetText("|cffb0b0b0" .. L["Earned %s"]:format(tostring(date)) .. "|r")
        r.bar:Hide()
      else
        r:SetBackdropBorderColor(0.25, 0.22, 0.16, 1)
        r.name:SetTextColor(0.85, 0.85, 0.85)
        r.pts:SetTextColor(0.55, 0.55, 0.55)
        r.right:SetText(goal > 1 and fmtProgress(a, have, goal) or "")
        r.bar:SetShown(goal > 1)
        r.bar:SetValue(goal > 0 and have / goal or 0)
      end
      r.share:SetShown(date ~= nil)
      r:Show()
    else
      r.a = nil
      r:Hide()
    end
  end
end

local function achRow(i)
  local r = CreateFrame("Frame", nil, ctl.achView, UI.TEMPLATE)
  r:SetSize(LIST_W - 4, ROW_H)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", LIST_X, -32 - (i - 1) * (ROW_H + ROW_GAP))
  UI.Backdrop(r, OPEN_BG, { 0.25, 0.22, 0.16 })
  r:EnableMouse(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(32, 32)
  r.icon:SetPoint("LEFT", 6, 0)
  r.icon:SetTexCoord(unpack(UI.ICON_COORDS))
  r.name = UI.Text(r, 13)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
  r.name:SetWidth(300)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.text = UI.Text(r, 10)
  r.text:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
  r.text:SetWidth(330)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.text:SetTextColor(0.75, 0.75, 0.75)
  r.pts = UI.Text(r, 16, "OUTLINE")
  r.pts:SetPoint("RIGHT", -10, 0)
  r.pts:SetWidth(34)
  r.pts:SetJustifyH("CENTER")
  -- earned: the date and Share; not yet: a bar
  local bar = CreateFrame("StatusBar", nil, r, UI.TEMPLATE)
  bar:SetSize(140, 10)
  bar:SetPoint("RIGHT", -52, -7)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.85, 0.65, 0.2)
  bar:SetMinMaxValues(0, 1)
  UI.Backdrop(bar, { 0, 0, 0, 0.7 }, { 0.3, 0.26, 0.18 })
  r.bar = bar
  r.right = UI.Text(r, 10)
  r.right:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 2)
  r.right:SetJustifyH("RIGHT")
  r.share = UI.Button(r, L["Share"], 56, 18, function()
    if r.a then UI.Share(UI.AchievementShareText(r.a)) end
  end)
  r.share:SetPoint("RIGHT", -52, -7)
  r.share:Hide()
  r:SetScript("OnEnter", function(self)
    if not self.a then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.a.name, 1, 0.82, 0)
    GameTooltip:AddLine(self.a.text, 1, 1, 1, true)
    local have, goal = C.AchProgress(ns.db, self.a)
    if goal > 1 then GameTooltip:AddLine(fmtProgress(self.a, have, goal), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(Plural(self.a.points, "%d point", "%d points"):format(self.a.points), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:Hide()
  return r
end

-- ---------------------------------------------------------------------------
-- The guild board
-- ---------------------------------------------------------------------------
local COLUMNS = {
  { key = "name", label = L["Name"], x = 0, w = 140 },
  { key = "stars", label = L["Stars"], x = 144, w = 56, num = true },
  { key = "heroic", label = L["Heroic"], x = 204, w = 56, num = true },
  { key = "owned", label = L["Cards"], x = 264, w = 76, num = true },
  { key = "points", label = L["Points"], x = 344, w = 60, num = true },
  { key = "pvp", label = L["Wins vs players"], x = 408, w = 92, num = true },
  { key = "seen", label = L["Seen"], x = 504, w = 84, num = true },
}
local ACT_X = 592

function Rec.SortBy(key)
  if sortKey == key then
    sortDesc = not sortDesc
  else
    sortKey = key
    sortDesc = key ~= "name"
  end
  boardTop = 0
  Rec.Refresh()
end

function Rec.Sort() return sortKey, sortDesc end

local function ago(seen)
  local s = math.max(0, (time and time() or 0) - (seen or 0))
  if s < 3600 then
    local m = math.max(1, math.floor(s / 60))
    return Plural(m, "%d min ago", "%d min ago"):format(m)
  elseif s < 86400 then
    local h = math.floor(s / 3600)
    return Plural(h, "%d hour ago", "%d hours ago"):format(h)
  end
  local d = math.floor(s / 86400)
  return Plural(d, "%d day ago", "%d days ago"):format(d)
end

local function rows() return ns.Guild.Rows(sortKey, sortDesc) end
Rec.BoardRows = rows

local function refreshGuild()
  local G = ns.Guild
  local list = rows()
  local others = #list - 1
  UI.FitText(ctl.summary, G.InGuild() and Plural(others, "%d guildmate with Tradewinds", "%d guildmates with Tradewinds"):format(others)
    or L["Not in a guild"], 9)
  for _, h in ipairs(ctl.heads) do
    local on = h.key == sortKey
    h.text:SetText(h.label .. (on and (sortDesc and " v" or " ^") or ""))
    if on then h.text:SetTextColor(1, 0.82, 0) else h.text:SetTextColor(0.85, 0.85, 0.85) end
  end
  local last = math.max(0, #list - BOARD_ROWS)
  if boardTop > last then boardTop = last end
  for i = 1, BOARD_ROWS do
    local r, e = ctl.boardRows[i], list[boardTop + i]
    if e then
      r.e = e
      r.cells.name:SetText((e.you and "|cff40ff40" or "") .. e.short .. (e.you and "|r" or ""))
      r.cells.stars:SetText(e.stars)
      r.cells.heroic:SetText(e.heroic)
      r.cells.owned:SetText(("%d / %d"):format(e.owned, e.total))
      r.cells.points:SetText(e.points)
      r.cells.pvp:SetText(e.pvp)
      r.cells.seen:SetText(e.you and L["you"] or e.online and ("|cff40ff40" .. L["online"] .. "|r") or ("|cff909090" .. ago(e.seen) .. "|r"))
      local can = G.CanPlay(e)
      r.challenge:SetShown(not e.you)
      r.trade:SetShown(not e.you)
      r.challenge:SetEnabled(can)
      r.trade:SetEnabled(can)
      r.stripe:SetShown(i % 2 == 0)
      r:Show()
    else
      r.e = nil
      r:Hide()
    end
  end
  local pages = math.max(1, math.ceil(#list / BOARD_ROWS))
  ctl.boardPage:SetText(("%d / %d"):format(math.floor(boardTop / BOARD_ROWS) + 1, pages))
  ctl.boardPrev:SetEnabled(boardTop > 0)
  ctl.boardNext:SetEnabled(boardTop < last)
  local note
  if not G.InGuild() then
    note = L["You're not in a guild. Guildmates who have Tradewinds show up here, with their stars, cards and achievement points."]
  elseif not ns.db.settings.guildShare then
    note = L["You're not sharing your progress (Options), so Tradewinds doesn't ask your guild either. Guildmates who share still show up."]
  elseif others == 0 then
    note = L["No guildmates with Tradewinds seen yet. They show up when they log in, or when they open this tab."]
  else
    note = L["Guildmates share their progress when they log in and when it changes. Challenge and Trade need them online, on your version."]
  end
  ctl.boardNote:SetText("|cff909090" .. note .. "|r")
end

function Rec.ScrollBoard(d)
  boardTop = math.max(0, boardTop + d)
  Rec.Refresh()
end

local function boardRow(i)
  local r = CreateFrame("Frame", nil, ctl.guildView)
  r:SetSize(PAGE_W - 4, BOARD_ROW_H)
  r:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -58 - (i - 1) * BOARD_ROW_H)
  r:EnableMouse(true)
  r.stripe = r:CreateTexture(nil, "BACKGROUND")
  r.stripe:SetAllPoints()
  r.stripe:SetColorTexture(1, 1, 1, 0.04)
  r.cells = {}
  for _, col in ipairs(COLUMNS) do
    local fs = UI.Text(r, 11)
    fs:SetPoint("LEFT", r, "LEFT", col.x + 4, 0)
    fs:SetWidth(col.w - 6)
    fs:SetJustifyH(col.num and "RIGHT" or "LEFT")
    fs:SetWordWrap(false)
    r.cells[col.key] = fs
  end
  r.challenge = UI.Button(r, L["Challenge"], 92, 20, function()
    if r.e then
      UI.SelectTab("play")
      UI.Game.Challenge(r.e.name)
    end
  end)
  r.challenge:SetPoint("LEFT", r, "LEFT", ACT_X, 0)
  r.trade = UI.Button(r, L["Trade"], 80, 20, function()
    if r.e then UI.Trading.Ask(r.e.name) end
  end)
  r.trade:SetPoint("LEFT", r.challenge, "RIGHT", 4, 0)
  r:SetScript("OnEnter", function(self)
    local e = self.e
    if not e or e.you then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.short)
    GameTooltip:AddLine(L["Tradewinds %s"]:format(e.v), e.v == ns.VERSION and 0.4 or 1, e.v == ns.VERSION and 1 or 0.5, 0.4)
    if e.v ~= ns.VERSION then
      GameTooltip:AddLine(L["You need the same version as each other to play or trade (yours is %s)."]:format(ns.VERSION), 1, 0.6, 0.4, true)
    elseif not e.online then
      GameTooltip:AddLine(L["Not online right now."], 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(L["Last heard from %s."]:format(ago(e.seen)), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:Hide()
  return r
end

-- ---------------------------------------------------------------------------
function Rec.SetView(v)
  view = v == "guild" and "guild" or "ach"
  if view == "guild" then ns.Guild.Ask() end
  Rec.Refresh()
end

-- Something on the board changed (Guild.lua): redraw if it's on screen.
function Rec.Changed()
  if page and page:IsVisible() and view == "guild" then Rec.Refresh() end
end

function Rec.Refresh()
  if not page then return end
  ctl.achView:SetShown(view == "ach")
  ctl.guildView:SetShown(view == "guild")
  for k, b in pairs(ctl.views) do b:SetEnabled(k ~= view) end
  if view == "ach" then refreshAch() else refreshGuild() end
end

function Rec.Build(parent)
  page = parent
  ctl.views = {}
  ctl.views.ach = UI.Button(page, L["Achievements"], 130, 22, function() UI.Sound("tab"); Rec.SetView("ach") end)
  ctl.views.ach:SetPoint("TOPLEFT", 0, -1)
  ctl.views.guild = UI.Button(page, L["Guild board"], 130, 22, function() UI.Sound("tab"); Rec.SetView("guild") end)
  ctl.views.guild:SetPoint("LEFT", ctl.views.ach, "RIGHT", 4, 0)
  ctl.summary = UI.Text(page, 12)
  ctl.summary:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -6)
  ctl.summary:SetWidth(470)
  ctl.summary:SetJustifyH("RIGHT")
  ctl.summary:SetWordWrap(false)
  ctl.summary:SetTextColor(1, 0.82, 0)

  -- achievements: the groups on the left, the group's list on the right
  ctl.achView = CreateFrame("Frame", nil, page)
  ctl.achView:SetAllPoints()
  ctl.groups = {}
  for i, g in ipairs(ns.ACH_GROUPS) do
    local b = CreateFrame("Button", nil, ctl.achView, UI.TEMPLATE)
    b:SetSize(GROUP_W, GROUP_H)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -32 - (i - 1) * (GROUP_H + 4))
    UI.Backdrop(b, { 0.09, 0.08, 0.06, 0.95 }, { 0.35, 0.29, 0.18 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(unpack(UI.ICON_COORDS))
    b.icon:SetTexture(UI.Icon(g.icon))
    b.name = UI.Text(b, 13)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.name:SetWidth(GROUP_W - 50)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    UI.FitText(b.name, g.name, 9)
    b.count = UI.Text(b, 10)
    b.count:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.count:SetTextColor(0.7, 0.7, 0.7)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
    b:SetScript("OnClick", function()
      UI.Sound("pick")
      Rec.ShowGroup(g.key)
    end)
    ctl.groups[i] = b
  end
  ctl.rows = {}
  for i = 1, MAX_ROWS do ctl.rows[i] = achRow(i) end

  -- the guild board
  ctl.guildView = CreateFrame("Frame", nil, page)
  ctl.guildView:SetAllPoints()
  ctl.heads = {}
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Button", nil, ctl.guildView)
    h:SetSize(col.w, 20)
    h:SetPoint("TOPLEFT", page, "TOPLEFT", col.x + 2, -32)
    h.key, h.label = col.key, col.label
    h.text = UI.Text(h, 11)
    h.text:SetPoint(col.num and "RIGHT" or "LEFT", h, col.num and "RIGHT" or "LEFT", col.num and -2 or 4, 0)
    h:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
    h:SetScript("OnClick", function() UI.Sound("pick"); Rec.SortBy(col.key) end)
    UI.SimpleTooltip(h, col.label, L["Click to sort by this. Click again to turn the order round."])
    ctl.heads[#ctl.heads + 1] = h
  end
  local rule = ctl.guildView:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.55, 0.45, 0.25, 0.6)
  rule:SetSize(PAGE_W - 4, 1)
  rule:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -55)
  ctl.boardRows = {}
  for i = 1, BOARD_ROWS do ctl.boardRows[i] = boardRow(i) end
  local navY = -58 - BOARD_ROWS * BOARD_ROW_H - 8
  ctl.boardPrev = UI.Button(ctl.guildView, "<", 34, 22, function() UI.Sound("pick"); Rec.ScrollBoard(-BOARD_ROWS) end)
  ctl.boardPrev:SetPoint("TOPRIGHT", page, "TOPRIGHT", -84, navY)
  ctl.boardPage = UI.Text(ctl.guildView, 12)
  ctl.boardPage:SetPoint("LEFT", ctl.boardPrev, "RIGHT", 4, 0)
  ctl.boardPage:SetWidth(40)
  ctl.boardNext = UI.Button(ctl.guildView, ">", 34, 22, function() UI.Sound("pick"); Rec.ScrollBoard(BOARD_ROWS) end)
  ctl.boardNext:SetPoint("LEFT", ctl.boardPage, "RIGHT", 4, 0)
  ctl.boardNote = UI.Text(ctl.guildView, 11)
  ctl.boardNote:SetPoint("TOPLEFT", page, "TOPLEFT", 4, navY - 3)
  ctl.boardNote:SetWidth(PAGE_W - 140)
  ctl.boardNote:SetJustifyH("LEFT")
  ctl.guildView:Hide()

  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, d)
    if view == "guild" then Rec.ScrollBoard(-d * 3) end
  end)
  page:SetScript("OnShow", function()
    if view == "guild" then ns.Guild.Ask() end
    Rec.Refresh()
  end)
end
