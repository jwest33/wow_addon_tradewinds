-- The tutorial's coach: Dorn's text in a box over the log, an arrow and a
-- glowing ring on what to click next, and the Next button between rounds.
-- The script and its checks are in Data/Tutorial.lua; UI/Game.lua asks this
-- file whether you may plan yet (Gate) and calls Refresh after every redraw.
local _, ns = ...
local UI, Cards = ns.UI, ns.Cards
local T = ns.Tutorial

local TU = {}
UI.Tutorial = TU

local ME, OPP = 1, 2
local coach, pointer, ring

-- What the coach is waiting on, if anything: the "after" text of the round
-- that just ended (kind "ack"), or the hand-over to free play ("free").
-- Returns text, kind.
function TU.Gate(m)
  if not (m and m.tutorial and m.st) or m.st.winner then return nil end
  local tut = m.tut or {}
  local done = m.st.round - 1
  if done >= 1 and done <= T.GUIDED and (tut.ack or 0) < done then return T.ROUNDS[done].after, "ack" end
  if m.st.round > T.GUIDED and not tut.free then return T.FREE, "free" end
  return nil
end

function TU.Next()
  local m = ns.db.match
  local _, kind = TU.Gate(m)
  if not kind then return end
  m.tut = m.tut or {}
  if kind == "ack" then m.tut.ack = m.st.round - 1 else m.tut.free = true end
  UI.Sound("pick")
  UI.Game.Refresh()
end

-- What Dorn says when you try something else.
function TU.Nudge(st, plan)
  local rest = T.Remaining(st, plan)
  local want = rest and rest[1]
  if not want then return "That's everything for this round. Press Lock In." end
  local c = Cards.byId[want.id]
  local where = (c.type == "tactic" and c.target == "enemy") and ("my lane " .. want.lane) or ("your lane " .. want.lane)
  return ("Not that one yet: play %s in %s."):format(c.name, where)
end

-- ---------------------------------------------------------------------------
local function point(target, below)
  if not target then
    pointer:Hide()
    ring:Hide()
    return
  end
  ring:ClearAllPoints()
  ring:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
  ring:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 4, -4)
  ring:Show()
  pointer:ClearAllPoints()
  if below then
    pointer.tex:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    pointer:SetPoint("TOP", target, "BOTTOM", 0, -2)
  else
    pointer.tex:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    pointer:SetPoint("BOTTOM", target, "TOP", 0, 2)
  end
  pointer:Show()
end

local function say(text, button)
  coach.text:SetText(text or "")
  if button then
    coach.next:SetText(button)
    coach.next:Show()
  else
    coach.next:Hide()
  end
  coach:Show()
end

-- m: the tutorial match (nil hides everything). s: what the board is doing:
-- { planning, view, finished, plan, sel, st, api }.
function TU.Refresh(m, s)
  if not coach then return end
  if not m or s.finished then
    coach:Hide()
    point(nil)
    return
  end
  local st = m.st
  if s.view then
    local r = T.ROUNDS[s.view.round]
    if r then say(r.watch .. "  |cff909090(Click the board to skip.)|r") else coach:Hide() end
    point(nil)
    return
  end
  local text, kind = TU.Gate(m)
  if kind then
    say(text, kind == "free" and "Let's play" or "Next")
    point(coach.next)
    return
  end
  local r = T.Round(st)
  if not r then
    coach:Hide()
    point(nil)
    return
  end
  say(r.say)
  if not s.planning then
    point(nil)
    return
  end
  local rest = T.Remaining(st, s.plan)
  local want = rest[1]
  if not want then
    point(s.api.lock())
    return
  end
  local selId = s.sel and st.players[ME].hand[s.sel]
  local target, below
  for _, w in ipairs(rest) do
    if selId and w.id == selId then
      local c = Cards.byId[w.id]
      local side = (c.type == "tactic" and c.target == "enemy") and OPP or ME
      target, below = s.api.slot(side, w.lane), side == OPP
      break
    end
  end
  if not target then target = s.api.handFrame(want.id) end
  point(target, below)
end

-- The coach box covers the log and the hint line above it (top: y, height h).
function TU.Build(board, y, width, h)
  coach = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  coach:SetPoint("TOPLEFT", board, "TOPLEFT", 0, y)
  coach:SetSize(width, h)
  coach:SetFrameLevel(board:GetFrameLevel() + 20)
  UI.Backdrop(coach, { 0.07, 0.06, 0.045, 1 }, { 1, 0.82, 0 }, true)
  coach:EnableMouse(true)
  local o = ns.OpponentById[T.OPP]
  local icon = coach:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 10, 4)
  icon:SetTexture(UI.Icon(o.icon))
  local name = UI.Text(coach, 9)
  name:SetPoint("TOP", icon, "BOTTOM", 0, -3)
  name:SetText(o.short)
  name:SetTextColor(1, 0.82, 0)
  coach.text = UI.Text(coach, 11)
  coach.text:SetPoint("TOPLEFT", coach, "TOPLEFT", 68, -9)
  coach.text:SetPoint("BOTTOMRIGHT", coach, "BOTTOMRIGHT", -110, 9)
  coach.text:SetJustifyH("LEFT")
  coach.text:SetJustifyV("MIDDLE")
  coach.text:SetSpacing(2)
  coach.text:SetTextColor(0.93, 0.9, 0.82)
  coach.next = UI.Button(coach, "Next", 90, 26, function() TU.Next() end)
  coach.next:SetPoint("RIGHT", -10, 0)
  coach:Hide()
  TU.coach = coach

  ring = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  ring:SetFrameLevel(board:GetFrameLevel() + 45)
  UI.Backdrop(ring, { 0, 0, 0, 0 }, { 1, 0.85, 0.2 }, true)
  ring:EnableMouse(false)
  local pulse = ring:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.25)
  fade:SetDuration(0.6)
  pulse:Play()
  ring:Hide()

  pointer = CreateFrame("Frame", nil, board)
  pointer:SetSize(36, 36)
  pointer:SetFrameLevel(board:GetFrameLevel() + 46)
  pointer:EnableMouse(false)
  pointer.tex = pointer:CreateTexture(nil, "OVERLAY")
  pointer.tex:SetAllPoints()
  pointer.tex:SetVertexColor(1, 0.85, 0.2)
  local bob = pointer:CreateAnimationGroup()
  bob:SetLooping("BOUNCE")
  local move = bob:CreateAnimation("Translation")
  move:SetOffset(0, 6)
  move:SetDuration(0.45)
  bob:Play()
  pointer:Hide()
  TU.pointer, TU.ring = pointer, ring
end
