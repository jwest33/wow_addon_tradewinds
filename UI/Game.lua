-- The Play tab: the opponent list, the board, planning a round, the computer
-- opponent's turn, the round replay and the end-of-game screen. Also the
-- tutorial match (its script is Data/Tutorial.lua, its coach UI/Tutorial.lua),
-- the first-time tips and the opponent's lines.
--
-- You are always player 1 and the computer player 2. The running game lives
-- in DeckhandCharDB.match, so it survives /reload and logging out.
local _, ns = ...
local R, Cards, AI, C = ns.Rules, ns.Cards, ns.AI, ns.Collection
local UI = ns.UI

local G = {}
UI.Game = G

local ME, OPP = 1, 2
-- The page is 784 x 556: a panel per player on the left, four lanes, the
-- controls on the right, then your hand and the log underneath.
local PAGE_W = 784
local SW, SH = UI.CARD_W + 4, UI.CARD_H + 4
local PANEL_W = 120
local LX, LGAP = 132, 8
local ROW_Y = { [OPP] = -2, [ME] = -176 }
local HAND_Y = -320
local RIGHT_X = 556
local RIGHT_W = 224
local LOG_Y = -474
local BEAT = 0.5
local MID_Y = -155 -- middle of the band between the two rows

local function laneX(l) return LX + (l - 1) * (SW + LGAP) end

local page, lobby, board
local slots = { {}, {} }
local panels = {}
local handCards = {}
local ctl = {}
local plan, sel = {}, nil
local busy, thinking = false, false
local view          -- the board as it was, replayed event by event
local finished      -- the game that just ended, until "Continue"
local forecast      -- what the planned round does if the opponent adds nothing
local markers = {}  -- per lane, between the rows: what the lane does in combat
local replayMarks = {}
local token = 0     -- invalidates stale replay timers
local startReplay   -- defined with the replay code below
local renderTips    -- defined with the keyword tips below

local function current() return ns.db.match and ns.db.match.st end
local function shown() return current() or (finished and finished.st) end
local function opponent()
  local id = (ns.db.match and ns.db.match.opp) or (finished and finished.opp)
  return id and ns.OpponentById[id]
end
local function who(p) return p == ME and "You" or (opponent() and opponent().short or "They") end
local function whose(p) return p == ME and "your" or ((opponent() and opponent().short or "their") .. "'s") end

-- The match, if it's the tutorial.
local function tutorialMatch()
  local m = ns.db.match
  return (m and m.tutorial) and m or nil
end

-- Can you plan right now? Not while a round plays out or the opponent
-- thinks, nor while the tutorial's coach waits for you to click Next.
local function isPlanning()
  if not current() or view or busy then return false end
  local tm = tutorialMatch()
  if tm and UI.Tutorial and UI.Tutorial.Gate(tm) then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- Log (a panel beside the window)
-- ---------------------------------------------------------------------------
local logFrame
local LOG_KEEP = 80

-- Lines go to the log under the hand and are saved with the match, so the
-- log is still there after a /reload.
function G.Log(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  if logFrame then logFrame.msgs:AddMessage(msg, 0.9, 0.9, 0.9) end
  local m = ns.db and ns.db.match
  if m then
    m.log = m.log or {}
    m.log[#m.log + 1] = msg
    if #m.log > LOG_KEEP then table.remove(m.log, 1) end
  end
end

local function buildLog(parent)
  logFrame = CreateFrame("Frame", nil, parent, UI.TEMPLATE)
  logFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, LOG_Y)
  logFrame:SetSize(PAGE_W, 80)
  UI.Backdrop(logFrame, { 0.03, 0.025, 0.02, 0.8 }, { 0.4, 0.33, 0.2, 0.8 })
  local msgs = CreateFrame("ScrollingMessageFrame", nil, logFrame)
  msgs:SetPoint("TOPLEFT", 8, -5)
  msgs:SetPoint("BOTTOMRIGHT", -8, 5)
  msgs:SetFont(UI.FONT, 10, "")
  msgs:SetJustifyH("LEFT")
  msgs:SetFading(false)
  msgs:SetMaxLines(300)
  msgs:EnableMouseWheel(true)
  msgs:SetScript("OnMouseWheel", function(self, d)
    if d > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  logFrame.msgs = msgs
  local m = ns.db.match
  if m and m.log then
    for _, line in ipairs(m.log) do msgs:AddMessage(line, 0.9, 0.9, 0.9) end
  end
end

-- ---------------------------------------------------------------------------
-- Planning helpers
-- ---------------------------------------------------------------------------
local function supplyLeft(st) return st.players[ME].supply - R.PlanCost(st, ME, plan) end

local function plannedHand()
  local t = {}
  for _, a in ipairs(plan) do t[a.h] = true end
  return t
end

local function plannedUnitAt(l)
  for i, a in ipairs(plan) do
    if Cards.byId[a.id].type == "unit" and a.lane == l then return a, i end
  end
end

-- Which side a planned card sits on: units and friend tactics on yours,
-- enemy tactics on theirs, untargeted tactics nowhere.
local function sideOf(a)
  local c = Cards.byId[a.id]
  if c.type == "unit" or c.target == "friend" then return ME end
  if c.target == "enemy" then return OPP end
end

local function validTarget(st, side, l)
  if not sel then return false end
  local c = Cards.byId[st.players[ME].hand[sel]]
  if c.type == "unit" then
    if side ~= ME then return false, "Units go in your own lanes (the bottom row)." end
    if st.players[ME].board[l] or plannedUnitAt(l) then return false, "That lane is taken." end
    return true
  elseif c.target == "enemy" then
    if side ~= OPP then return false, c.name .. " targets an enemy lane (the top row)." end
    return true
  elseif c.target == "friend" then
    if side ~= ME then return false, c.name .. " targets one of your units (the bottom row)." end
    if not (st.players[ME].board[l] or plannedUnitAt(l)) then return false, "You have no unit there." end
    return true
  end
  return false
end

-- Friend tactics whose unit was taken back go back to the hand too.
local function prune(st)
  local units = {}
  for _, a in ipairs(plan) do
    if Cards.byId[a.id].type == "unit" then units[a.lane] = true end
  end
  for i = #plan, 1, -1 do
    local a = plan[i]
    local c = Cards.byId[a.id]
    if c.type == "tactic" and c.target == "friend" and not (st.players[ME].board[a.lane] or units[a.lane]) then
      table.remove(plan, i)
    end
  end
end

local function removeAt(side, l, id)
  local removed = false
  for i = #plan, 1, -1 do
    local a = plan[i]
    if sideOf(a) == side and a.lane == l and (not id or a.id == id) then
      table.remove(plan, i)
      removed = true
    end
  end
  if removed then prune(current()) end
  return removed
end

-- ---------------------------------------------------------------------------
-- Forecast: plays the round out on a copy of the game with your plan and the
-- opponent adding nothing (the same what-if the computer runs for itself),
-- and reports the Morale change and which units would die.
-- ---------------------------------------------------------------------------
local function simulateRound(st, seed)
  local c = R.Clone(st)
  c.rng = R.Seed(seed)
  c.events = {}
  if not pcall(R.Resolve, c, { plan, {} }, { noAdvance = true }) then return nil end
  local dies = { {}, {} }
  for p = 1, 2 do
    for l = 1, R.LANES do
      local before, after = st.players[p].board[l], c.players[p].board[l]
      if before then
        if not after or after.uid ~= before.uid then dies[p][l] = true end
      elseif p == ME then
        local a = plannedUnitAt(l)
        if a and not (after and after.id == a.id) then dies[p][l] = true end
      end
    end
  end
  return c, dies
end

-- Random effects (a random target, say) are played out twice with different
-- luck. A unit that dies both times is marked "dies", one that dies only
-- once "may die".
local function computeForecast(st)
  local c, dies = simulateRound(st, 7)
  local _, dies2 = simulateRound(st, 7919)
  if not (c and dies2) then return nil end
  local f = { dies = { {}, {} }, maybe = { {}, {} }, loss = {}, winner = c.winner, strikes = { {}, {} } }
  for _, e in ipairs(c.events) do
    if e.t == "strike" and not f.strikes[e.p][e.lane] then f.strikes[e.p][e.lane] = e end
  end
  for p = 1, 2 do
    f.loss[p] = st.players[p].morale - c.players[p].morale
    for l = 1, R.LANES do
      if dies[p][l] and dies2[p][l] then f.dies[p][l] = true
      elseif dies[p][l] or dies2[p][l] then f.maybe[p][l] = true end
    end
  end
  return f
end

function G.Forecast() return forecast end

-- The unit in a lane while planning (a planned one counts): card id, keywords.
local function laneUnit(st, p, l)
  local u = st.players[p].board[l]
  if u then return u.id, u.kw end
  if p == ME then
    local a = plannedUnitAt(l)
    if a then return a.id, Cards.byId[a.id].kw end
  end
end

-- What a lane does in combat this round, from the forecast:
--   "out"    your unit has nothing across and hits their Morale
--   "in"     their unit has nothing across and hits your Morale
--   "fight"  the two units strike each other
--   "guard"  an attack goes into a Guard from the next lane
--   "ranged" a Ranged unit shoots somewhere else
--   "idle"   a unit that won't strike (frozen, no attack)
--   "open"   nobody in the lane
-- Returns state, amount, tooltip lines.
local function analyzeLane(st, l)
  local f = forecast
  local o = opponent()
  local mine, myKw = laneUnit(st, ME, l)
  local theirs, theirKw = laneUnit(st, OPP, l)
  local ms, ts = f.strikes[ME][l], f.strikes[OPP][l]
  local mName = mine and ("your " .. UI.CardName(mine))
  local tName = theirs and ("their " .. UI.CardName(theirs))
  local function cap(s) return (s:gsub("^%l", string.upper)) end
  local function targetName(e)
    local id = laneUnit(st, e.tp, e.tl)
    return id and UI.CardName(id) or "a unit"
  end
  local lines = {}
  local state, amt
  if ts and not ts.tl then
    state, amt = "in", ts.amt
    lines[1] = ("Nothing of yours is across from %s, so it hits your Morale for %d."):format(tName, ts.amt)
    lines[2] = ("Play a unit in lane %d to block it."):format(l)
  elseif ms and not ms.tl then
    state, amt = "out", ms.amt
    lines[1] = ("Nothing is across from %s, so it hits %s's Morale for %d."):format(mName, o.short, ms.amt)
    lines[2] = "It keeps doing that every round until they block this lane."
  elseif ms or ts then
    state = "fight"
    if mine and theirs then
      lines[1] = ("%s and %s face each other, so they fight."):format(cap(mName), tName)
    end
    for _, pair in ipairs({ { ms, mName, myKw }, { ts, tName, theirKw } }) do
      local e, name, kw = pair[1], pair[2], pair[3]
      if e then
        if e.tl == l then
          lines[#lines + 1] = ("%s strikes %s for %d."):format(cap(name), targetName(e), e.amt)
        elseif kw and kw.ranged then
          state = (state == "fight" and mine and theirs) and "fight" or "ranged"
          lines[#lines + 1] = ("%s is Ranged: it shoots the weakest enemy unit, %s in lane %d, for %d."):format(
            cap(name), targetName(e), e.tl, e.amt)
        else
          state = (state == "fight" and mine and theirs) and "fight" or "guard"
          lines[#lines + 1] = ("%s has nothing across, but the Guard %s in lane %d steps in and takes the %d damage."):format(
            cap(name), targetName(e), e.tl, e.amt)
        end
      elseif name then
        lines[#lines + 1] = ("%s doesn't strike this round (it dies first, is frozen, or has no attack)."):format(cap(name))
      end
    end
  elseif mine or theirs then
    state = "idle"
    lines[1] = ("%s won't strike this round (frozen, or no attack)."):format(cap(mName or tName))
  else
    state = "open"
    lines[1] = ("Lane %d is empty on both sides."):format(l)
    lines[2] = ("A unit you play here strikes whatever is across from it, or %s's Morale if nothing is."):format(o.short)
  end
  return state, amt, lines
end

local MARK = {
  out = { arrow = "Interface\\Buttons\\Arrow-Up-Up", r = 0.35, g = 1, b = 0.35, label = "hits them" },
  ["in"] = { arrow = "Interface\\Buttons\\Arrow-Down-Up", r = 1, g = 0.35, b = 0.35, label = "hits you" },
  fight = { swords = true, r = 1, g = 0.82, b = 0.3, label = "fight" },
  guard = { swords = true, r = 0.6, g = 0.8, b = 1, label = "Guard" },
  ranged = { swords = true, r = 0.6, g = 0.8, b = 1, label = "Ranged" },
  idle = { r = 0.6, g = 0.6, b = 0.6, label = "no attack" },
  open = { r = 0.45, g = 0.42, b = 0.36, label = "open lane" },
}

local function paintMarker(l, state, amt, lines)
  local m = markers[l]
  m.state, m.amt, m.lines = state, amt, lines
  local def = state and MARK[state]
  m.arrow:Hide()
  m.swords:Hide()
  m.num:SetText("")
  m.label:SetText("")
  m.line:SetShown(state ~= nil and state ~= "open")
  if not def then return end
  m.label:SetText(def.label)
  m.label:SetTextColor(def.r, def.g, def.b)
  m.line:SetColorTexture(def.r, def.g, def.b, 0.35)
  if def.arrow then
    m.arrow:SetTexture(def.arrow)
    m.arrow:SetVertexColor(def.r, def.g, def.b)
    m.arrow:Show()
    m.num:SetText(amt or "")
    m.num:SetTextColor(def.r, def.g, def.b)
  elseif def.swords then
    m.swords:Show()
  end
end

local function renderMarkers()
  local st = current()
  for l = 1, R.LANES do
    if view then
      local rm = replayMarks[l]
      if rm then paintMarker(l, rm.state, rm.amt, nil) else paintMarker(l, nil) end
    elseif st and forecast and not busy then
      paintMarker(l, analyzeLane(st, l))
    else
      paintMarker(l, nil)
    end
  end
end

function G.LaneState(l) return markers[l].state, markers[l].amt end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------
local function renderSlot(p, l)
  local st = shown()
  local S = view or st
  local slot = slots[p][l]
  local card = slot.card
  local u = S and S.players[p].board[l]
  local planning = isPlanning()
  local dies = planning and forecast and forecast.dies[p][l]
  local maybe = planning and forecast and forecast.maybe[p][l]
  if u then
    card:SetCard(u.id, u, S, p == ME and C.IsHolo(ns.db, u.id))
    if dies then card:SetTag("dies", 1, 0.3, 0.3) elseif maybe then card:SetTag("may die", 1, 0.65, 0.2) end
  elseif p == ME and planning and plannedUnitAt(l) then
    card:SetCard(plannedUnitAt(l).id, nil, nil, C.IsHolo(ns.db, plannedUnitAt(l).id))
    card:SetAlpha(0.85)
    if dies then card:SetTag("dies", 1, 0.3, 0.3)
    elseif maybe then card:SetTag("may die", 1, 0.65, 0.2)
    else card:SetTag("planned", 0.4, 1, 0.4) end
  else
    card:Hide()
  end
  local n = 0
  if planning then
    for _, a in ipairs(plan) do
      if a.lane == l and sideOf(a) == p and Cards.byId[a.id].type == "tactic" then
        n = n + 1
        local bdg = slot.badges[n]
        if bdg then
          bdg.cardId = a.id
          bdg.tex:SetTexture(UI.CardIcon(a.id))
          bdg:Show()
        end
      end
    end
  end
  for i = n + 1, #slot.badges do slot.badges[i]:Hide() end
  if planning and sel and validTarget(st, p, l) then
    slot:SetBackdropBorderColor(0.3, 1, 0.3, 1)
  else
    slot:SetBackdropBorderColor(0.32, 0.28, 0.22, 0.9)
  end
end

local function moraleColor(m)
  if m >= 8 then return 0.4, 1, 0.4 elseif m >= 4 then return 1, 0.82, 0.2 end
  return 1, 0.3, 0.3
end

local function renderPanels()
  local st = shown()
  local S = view or st
  local o = opponent()
  for p = 1, 2 do
    local pn = panels[p]
    local m = math.max(0, S.players[p].morale)
    pn.morale:SetText(m)
    pn.morale:SetTextColor(moraleColor(m))
    local d = (not view and forecast) and forecast.loss[p] or 0
    if d > 0 then
      pn.predict:SetText("-" .. d)
      pn.predict:SetTextColor(1, 0.35, 0.35)
    elseif d < 0 then
      pn.predict:SetText("+" .. -d)
      pn.predict:SetTextColor(0.35, 1, 0.35)
    else
      pn.predict:SetText("")
    end
    if view then
      pn.counts:SetText(("Hand %d   Deck %d"):format(view.players[p].handCount, view.players[p].deckCount))
    else
      pn.counts:SetText(("Hand %d   Deck %d"):format(#st.players[p].hand, #st.players[p].deck))
    end
    if p == OPP and o then
      local heroic = (ns.db.match and ns.db.match.heroic) or (not ns.db.match and finished and finished.heroic)
      pn.name:SetText(heroic and (o.name .. " |cffc080ff(Heroic)|r") or o.name)
      pn.icon:SetTexture(UI.Icon(o.icon))
    else
      pn.name:SetText(UnitName and UnitName("player") or "You")
    end
  end
end

local function renderHand()
  local st = shown()
  local hand = view and view.hand or st.players[ME].hand
  local planning = isPlanning()
  local tm = planning and tutorialMatch()
  local list = {}
  local planned = planning and plannedHand() or {}
  for h = 1, #hand do
    if not planned[h] then list[#list + 1] = h end
  end
  local n = #list
  local w = n * UI.CARD_W + math.max(0, n - 1) * 5
  local x0 = (PAGE_W - w) / 2
  local left = planning and supplyLeft(st) or 0
  for i = 1, R.HAND_MAX do
    local b = handCards[i]
    local h = list[i]
    if h then
      b.h = h
      b:SetCard(hand[h], nil, nil, C.IsHolo(ns.db, hand[h]))
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", board, "TOPLEFT", x0 + (i - 1) * (UI.CARD_W + 5), HAND_Y + ((planning and sel == h) and 10 or 0))
      b:SetSelected(planning and sel == h)
      b:SetDim(not planning or (sel ~= h and Cards.byId[hand[h]].cost > left)
        or (tm and sel ~= h and not ns.Tutorial.Allowed(st, plan, hand[h])) and true or false)
    else
      b.h = nil
      b:Hide()
    end
  end
end

local function hintText(st)
  if thinking then return (opponent().short or "They") .. " is choosing..." end
  if view then return "Playing out the round. Click the board to skip." end
  if not current() then return "" end
  local tm = tutorialMatch()
  if tm and UI.Tutorial.Gate(tm) then return "Click " .. (tm.st.round > ns.Tutorial.GUIDED and "Let's play" or "Next") .. " to carry on." end
  if sel then
    local c = Cards.byId[st.players[ME].hand[sel]]
    if c.type == "unit" then return "Click one of your empty lanes (bottom row) for " .. c.name .. "." end
    if c.target == "enemy" then return "Click an enemy lane (top row) for " .. c.name .. "." end
    return "Click one of your units for " .. c.name .. "."
  end
  if forecast and forecast.winner == ME then
    return "This plan wins the game if " .. opponent().short .. " adds nothing new!"
  end
  if #plan == 0 then return "Pick cards from your hand (click or drag), place them, then Lock In." end
  local left, used = supplyLeft(st), plannedHand()
  for h, id in ipairs(st.players[ME].hand) do
    if not used[h] and Cards.byId[id].cost <= left then
      return ("You still have %d Supply and a card you could play. Lock In when ready."):format(left)
    end
  end
  return "Lock In when ready. Right-click a planned card to take it back."
end

local function renderControls()
  local st = shown()
  local S = view or st
  ctl.round:SetText(("Round %d of %d"):format(S.round, R.MAX_ROUNDS))
  ctl.init:SetText(S.init == ME and "You have initiative" or (who(OPP) .. " has initiative"))
  local planning = isPlanning()
  if planning then
    ctl.supply:SetText(("%d/%d"):format(supplyLeft(st), st.players[ME].supply))
  else
    ctl.supply:SetText(("-/%d"):format(view and view.supply or st.players[ME].supply))
  end
  ctl.lock:SetEnabled(planning and true or false)
  ctl.lock:SetText(thinking and "Thinking..." or view and "Playing..." or "Lock In")
  ctl.clear:SetEnabled(planning and #plan > 0)
  ctl.replay:SetEnabled((planning and ns.db.match.last) and true or false)
  ctl.endMatch:SetShown(current() ~= nil)
  ctl.endMatch:SetText(tutorialMatch() and "Leave tutorial" or "End match")
  -- untargeted tactics in the plan
  local n = 0
  if planning then
    for _, a in ipairs(plan) do
      if not sideOf(a) then
        n = n + 1
        local bdg = ctl.free[n]
        if bdg then
          bdg.cardId = a.id
          bdg.h = a.h
          bdg.tex:SetTexture(UI.CardIcon(a.id))
          bdg:Show()
        end
      end
    end
  end
  for i = n + 1, #ctl.free do ctl.free[i]:Hide() end
  ctl.freeLabel:SetShown(n > 0)
  ctl.hint:SetText(hintText(st))
end

local function showGameOver()
  local f = finished
  local o = ns.OpponentById[f.opp]
  local ov = ctl.over
  local st = f.st
  if f.result == "win" then
    ov.title:SetText(f.heroic and "Heroic victory!" or "Victory!")
    ov.title:SetTextColor(1, 0.82, 0)
    ov.quote:SetText(o.short .. ": \"" .. o.lose .. "\"")
  elseif f.result == "loss" then
    ov.title:SetText(f.conceded and "Conceded" or "Defeat")
    ov.title:SetTextColor(1, 0.3, 0.3)
    ov.quote:SetText(o.short .. ": \"" .. o.win .. "\"")
  else
    ov.title:SetText("Draw")
    ov.title:SetTextColor(0.8, 0.8, 0.8)
    ov.quote:SetText("Honours even.")
  end
  local lines = {}
  lines[1] = ("Morale %d to %d after round %d%s"):format(math.max(0, st.players[ME].morale),
    math.max(0, st.players[OPP].morale), st.round,
    st.tiebreak and " (tie broken by units on the board)" or "")
  if f.stats and not f.conceded then
    lines[#lines + 1] = ("|cffb0b0b0You dealt %d Morale damage and destroyed %d units; you took %d and lost %d.|r"):format(
      f.stats.dealt, f.stats.kills, f.stats.taken, f.stats.lost)
  end
  for _, r in ipairs(f.rewards) do
    if r.star then
      lines[#lines + 1] = ("|cffffd100Star earned: %s|r"):format(r.why)
    elseif r.card then
      if r.kind == "shards" then
        lines[#lines + 1] = ("%s (you have it already: |cff9fdfff+%d shards|r)"):format(UI.CardName(r.card), r.dupe)
      elseif r.holo then
        lines[#lines + 1] = ("%s %s (%s)"):format(UI.Rainbow(r.kind == "holo" and "Now holographic:" or "Holographic card:"),
          UI.CardName(r.card), r.why)
      else
        lines[#lines + 1] = ("New card: %s (%s)"):format(UI.CardName(r.card), r.why)
      end
    elseif r.unlocked then
      lines[#lines + 1] = ("|cff40ff40%s will play you now.|r"):format(ns.OpponentById[r.unlocked].name)
    elseif r.heroic then
      lines[#lines + 1] = "|cffc080ffHeroic rematches are open: the Heroic rematches button on the opponent list.|r"
    elseif r.packs then
      lines[#lines + 1] = ("|cffffd100+%d card pack%s|r (%s)"):format(r.packs, r.packs == 1 and "" or "s", r.why)
    elseif r.shards then
      lines[#lines + 1] = ("|cff9fdfff+%d shard%s|r (%s)"):format(r.shards, r.shards == 1 and "" or "s", r.why)
    end
  end
  if f.tutorial then
    if f.conceded then
      lines = { "|cff909090You left the tutorial. Start it again any time from the Play tab or the Guide.|r" }
    else
      table.insert(lines, 2, "|cffffd100Tutorial complete!|r")
      lines[#lines + 1] = "Next: the tavern circuit. Dorn is first on the list, and this time he's not holding back."
      lines[#lines + 1] = "|cffb0b0b0The Guide tab has every rule and keyword.|r"
    end
  elseif f.conceded then
    lines[#lines + 1] = "|cff909090Ended early: no reward.|r"
  end
  ov.body:SetText(table.concat(lines, "\n"))
  ov:Show()
end

-- ---------------------------------------------------------------------------
-- First-time keyword tips: the first time a keyword is in your hand or on
-- the board, while you plan, a box explains it (one at a time).
-- ---------------------------------------------------------------------------
local function nextKeyword(st)
  local seen = ns.db.settings.seenKw or {}
  local function first(kw)
    if not kw then return nil end
    for _, k in ipairs(R.KEYWORDS) do
      if kw[k.key] and not seen[k.key] then return k end
    end
  end
  for _, id in ipairs(st.players[ME].hand) do
    local k = first(Cards.byId[id].kw)
    if k then return k end
  end
  for p = 1, 2 do
    for l = 1, R.LANES do
      local u = st.players[p].board[l]
      local k = u and first(u.kw)
      if k then return k end
    end
  end
end

renderTips = function(st, tm)
  local tip = ctl.kwTip
  if not tip then return end
  local k = isPlanning() and not tm and ns.db.settings.seenLaneTip and not ctl.laneTip:IsShown() and nextKeyword(st)
  if not k then
    tip:Hide()
    return
  end
  tip.key = k.key
  tip.title:SetText("New keyword: " .. k.name)
  tip.diagram.tex:SetTexture(UI.ART .. "Diagram_" .. k.key)
  tip.text:SetText(k.text)
  tip:Show()
end

function G.DismissKeyword()
  local tip = ctl.kwTip
  if not (tip and tip:IsShown() and tip.key) then return end
  ns.db.settings.seenKw = ns.db.settings.seenKw or {}
  ns.db.settings.seenKw[tip.key] = true
  tip:Hide()
  G.Refresh()
end

function G.KeywordTip() return ctl.kwTip and ctl.kwTip:IsShown() and ctl.kwTip.key or nil end

-- ---------------------------------------------------------------------------
-- The opponent's lines: a speech bubble by their panel for a few seconds
-- (click it to dismiss), and the log. Off with the "chatter" setting.
-- ---------------------------------------------------------------------------
local bubbleToken = 0

function G.Say(kind, noLog)
  local o = opponent()
  local line = o and o[kind]
  if not line or not ns.db.settings.chatter or tutorialMatch() or not ctl.bubble then return end
  if not noLog then G.Log("%s: \"%s\"", o.short, line) end
  local b = ctl.bubble
  b.kind = kind
  b.text:SetText(line)
  b:Show()
  bubbleToken = bubbleToken + 1
  local mine = bubbleToken
  C_Timer.After(5, function() if mine == bubbleToken then b:Hide() end end)
end

function G.Bubble() return ctl.bubble and ctl.bubble:IsShown() and ctl.bubble.kind or nil end

-- After a round has played out for the first time: a big hit either way, or
-- the opponent close to losing, may get a line. At most one a round, each
-- kind at most twice a match ("low" once).
local function chatterAfterRound(m)
  if not (m and m.last) or m.tutorial or m.st.winner then return end
  local toMe, toThem = 0, 0
  for _, e in ipairs(m.last.events) do
    if e.t == "morale" and e.delta < 0 then
      if e.p == ME then toMe = toMe - e.delta else toThem = toThem - e.delta end
    end
  end
  m.said = m.said or {}
  local kind
  if m.st.players[OPP].morale <= 4 and not m.said.low then kind = "low"
  elseif toMe >= 4 and toMe >= toThem and (m.said.hit or 0) < 2 then kind = "hit"
  elseif toThem >= 4 and (m.said.hurt or 0) < 2 then kind = "hurt" end
  if not kind then return end
  m.said[kind] = kind == "low" and true or ((m.said[kind] or 0) + 1)
  G.Say(kind)
end

function G.Refresh()
  if not page then return end
  local m = ns.db.match
  if m and m.last and m.shown == false and not busy and not view then
    startReplay(m.last)
    return
  end
  -- a game that ended with no replay to show
  local live = current()
  if live and live.winner and not busy and not view then G.EndGame() end
  local st = shown()
  if not st then
    board:Hide()
    lobby:Show()
    G.RefreshLobby()
    return
  end
  lobby:Hide()
  board:Show()
  forecast = nil
  if isPlanning() and ns.db.settings.forecast then forecast = computeForecast(st) end
  for p = 1, 2 do
    for l = 1, R.LANES do renderSlot(p, l) end
  end
  renderMarkers()
  local tm = tutorialMatch()
  if ctl.laneTip then
    ctl.laneTip:SetShown((not ns.db.settings.seenLaneTip and isPlanning() and not tm) and true or false)
  end
  renderTips(st, tm)
  renderPanels()
  renderHand()
  renderControls()
  if finished then showGameOver() else ctl.over:Hide() end
  if UI.Tutorial then
    UI.Tutorial.Refresh(tm, { planning = isPlanning(), view = view, finished = finished, plan = plan, sel = sel, api = G.api })
  end
end

-- ---------------------------------------------------------------------------
-- Clicks
-- ---------------------------------------------------------------------------
local function planning() return isPlanning() end

function G.ClickHand(h, button)
  if view then G.Skip() return end
  if not planning() or not h then return end
  local st = current()
  if button == "RightButton" or sel == h then
    sel = nil
    G.Refresh()
    return
  end
  local c = Cards.byId[st.players[ME].hand[h]]
  local tm = tutorialMatch()
  if tm and not ns.Tutorial.Allowed(st, plan, st.players[ME].hand[h]) then
    UI.Error(opponent().short .. ": " .. UI.Tutorial.Nudge(st, plan))
    return
  end
  if c.cost > supplyLeft(st) then
    UI.Error(("Not enough supply for %s (%d)."):format(c.name, c.cost))
    return
  end
  if c.type == "tactic" and c.target == "none" then
    plan[#plan + 1] = { h = h, id = st.players[ME].hand[h] }
    sel = nil
  elseif c.type == "tactic" and c.target == "friend" then
    local any = false
    for l = 1, R.LANES do if st.players[ME].board[l] or plannedUnitAt(l) then any = true end end
    if not any then UI.Error(c.name .. " needs one of your units. Place a unit first.") return end
    sel = h
  else
    sel = h
  end
  UI.Sound("pick")
  G.Refresh()
end

function G.ClickSlot(p, l, button)
  if view then G.Skip() return end
  if not planning() then return end
  local st = current()
  if button == "RightButton" and sel then
    sel = nil
    G.Refresh()
    return
  end
  if button == "RightButton" or not sel then
    if removeAt(p, l) then
      UI.Sound("back")
      G.Refresh()
    end
    return
  end
  local ok, why = validTarget(st, p, l)
  if not ok then
    if why then UI.Error(why) end
    return
  end
  if tutorialMatch() and not ns.Tutorial.Allowed(st, plan, st.players[ME].hand[sel], l) then
    UI.Error(opponent().short .. ": " .. UI.Tutorial.Nudge(st, plan))
    return
  end
  plan[#plan + 1] = { h = sel, id = st.players[ME].hand[sel], lane = l }
  sel = nil
  UI.Sound("place")
  G.Refresh()
end

function G.Selected() return sel end

-- The end of a drag from the hand: the lane under the mouse, if any.
function G.Drop()
  if not (planning() and sel) then return end
  for p = 1, 2 do
    for l = 1, R.LANES do
      if slots[p][l]:IsMouseOver() then
        G.ClickSlot(p, l, "LeftButton")
        return
      end
    end
  end
end

function G.ClearPlan()
  if not planning() then return end
  plan, sel = {}, nil
  G.Refresh()
end

-- ---------------------------------------------------------------------------
-- Playing a round
-- ---------------------------------------------------------------------------
-- The round as it stood when both plans were locked in: the boards, and what
-- the panels and your hand showed (your hand without the cards you played).
-- theirPlayed: how many cards the opponent played.
local function makeView(st, theirPlayed)
  local v = { round = st.round, init = st.init, players = {}, supply = st.players[ME].supply, hand = {} }
  for p = 1, 2 do
    v.players[p] = { board = R.DeepCopy(st.players[p].board), morale = st.players[p].morale,
      handCount = #st.players[p].hand, deckCount = #st.players[p].deck }
  end
  local used = plannedHand()
  for h, id in ipairs(st.players[ME].hand) do
    if not used[h] then v.hand[#v.hand + 1] = id end
  end
  v.players[ME].handCount = #v.hand
  v.players[OPP].handCount = v.players[OPP].handCount - (theirPlayed or 0)
  return v
end

local SET_COLOR = {
  heal = { 0.3, 1, 0.3 }, buff = { 1, 0.85, 0.3 }, freeze = { 0.4, 0.7, 1 }, sturdy = { 1, 1, 1 },
  transform = { 0.8, 0.4, 1 }, reveal = { 0.6, 0.6, 0.8 }, endround = { 0.3, 1, 0.3 },
}

local bannerToken = 0
local function showTactic(e)
  local b = ctl.banner
  b.card:SetCard(e.id, nil, nil, e.p == ME and C.IsHolo(ns.db, e.id))
  b.who:SetText(e.p == ME and "You cast" or (who(OPP) .. " casts"))
  b.what:SetText(UI.CardName(e.id))
  local c = Cards.byId[e.id]
  if e.lane then
    local side = c.target == "friend" and e.p or (3 - e.p)
    b.where:SetText(("on %s lane %d"):format(side == ME and "your" or whose(OPP), e.lane))
    slots[side][e.lane]:Flash(0.7, 0.4, 1)
  else
    b.where:SetText("")
  end
  b:Show()
  bannerToken = bannerToken + 1
  local mine = bannerToken
  C_Timer.After(1.1 / (ns.db.settings.speed or 1), function() if mine == bannerToken then b:Hide() end end)
  G.Log("%s cast %s%s.", who(e.p), UI.CardName(e.id), e.lane and (" at lane " .. e.lane) or "")
end

local function apply(e)
  local t = e.t
  if t == "phase" then
    ctl.phase:SetText(e.name == "combat" and "Combat!" or "Reveal!")
    if e.name == "reveal" then
      replayMarks = {}
      renderMarkers()
    end
    return 0.35
  elseif t == "place" then
    view.players[e.p].board[e.lane] = R.DeepCopy(e.unit)
    renderSlot(e.p, e.lane)
    slots[e.p][e.lane].card:Flash(1, 1, 1)
    if e.summon then
      G.Log("%s joined %s side.", UI.CardName(e.unit.id), whose(e.p))
      return 0.25
    end
    G.Log("%s played %s.", who(e.p), UI.CardName(e.unit.id))
    return 0.12
  elseif t == "set" then
    view.players[e.p].board[e.lane] = R.DeepCopy(e.unit)
    renderSlot(e.p, e.lane)
    local col = SET_COLOR[e.why] or { 1, 1, 1 }
    local cd = slots[e.p][e.lane].card
    cd:Flash(col[1], col[2], col[3])
    if e.why == "sturdy" then cd:Float("Sturdy!", 1, 1, 1)
    elseif e.why == "freeze" then cd:Float("Frozen", 0.5, 0.8, 1)
    elseif e.why == "transform" then G.Log("Baa! A unit became a %s.", UI.CardName(e.unit.id)) end
    return 0
  elseif t == "dmg" then
    local u = view.players[e.p].board[e.lane]
    if u then u.hp = e.hp end
    renderSlot(e.p, e.lane)
    local cd = slots[e.p][e.lane].card
    cd:Float("-" .. e.amt, 1, 0.3, 0.3)
    cd:Flash(1, 0.15, 0.15)
    return 0
  elseif t == "morale" then
    view.players[e.p].morale = e.value
    renderPanels()
    local pn = panels[e.p]
    if e.delta < 0 then
      pn:Float(tostring(e.delta), 1, 0.3, 0.3)
      pn:Flash(1, 0.1, 0.1)
      G.Log("%s lost %d Morale (%d left).", who(e.p), -e.delta, math.max(0, e.value))
    else
      pn:Float("+" .. e.delta, 0.3, 1, 0.3)
      pn:Flash(0.2, 1, 0.2)
      G.Log("%s restored %d Morale.", who(e.p), e.delta)
    end
    return 0
  elseif t == "die" then
    view.players[e.p].board[e.lane] = nil
    renderSlot(e.p, e.lane)
    slots[e.p][e.lane]:Flash(0.7, 0.1, 0.1)
    G.Log("%s %s died.", e.p == ME and "Your" or (who(OPP) .. "'s"), UI.CardName(e.id))
    return 0
  elseif t == "strike" then
    local cd = slots[e.p][e.lane].card
    if cd:IsShown() then
      cd:Flash(1, 0.85, 0.3)
      if not skipping then cd:Lunge(e.p == ME and 12 or -12) end
    end
    local rm = replayMarks[e.lane] or {}
    if not e.tl then
      rm.state, rm.amt = (e.p == ME) and "out" or "in", e.amt
    elseif rm.state ~= "out" and rm.state ~= "in" then
      rm.state = "fight"
    end
    replayMarks[e.lane] = rm
    paintMarker(e.lane, rm.state, rm.amt, nil)
    local def = MARK[rm.state]
    markers[e.lane]:Flash(def.r, def.g, def.b)
    return 0
  elseif t == "trigger" then
    local cd = slots[e.p][e.lane].card
    if cd:IsShown() then cd:Flash(0.7, 0.4, 1) end
    return 0
  elseif t == "tactic" then
    showTactic(e)
    if not skipping then UI.Sound("tactic") end
    return 0.9
  elseif t == "beat" then
    return BEAT
  elseif t == "round" then
    view.round, view.init = e.n, e.init
    ctl.phase:SetText("")
    renderControls()
    G.Log("|cffffd100Round %d|r", e.n)
    return 0
  elseif t == "burn" then
    G.Log("%s hand was full: %s burned.", e.p == ME and "Your" or (who(OPP) .. "'s"), UI.CardName(e.id))
    return 0
  elseif t == "empty" then
    if e.p == ME then G.Log("Your deck is empty.") end
    return 0
  end
  return 0
end

local queue, qi, skipping = {}, 1, false

local function finishReplay()
  view = nil
  busy = false
  skipping = false
  local m = ns.db.match
  local first = m and m.shown == false
  if m then m.shown = true end
  ctl.banner:Hide()
  ctl.phase:SetText("")
  local st = current()
  if st and st.winner then G.EndGame() end
  G.Refresh()
  if first then chatterAfterRound(ns.db.match) end
end

local function pump(mine)
  if mine ~= token then return end
  while qi <= #queue do
    local e = queue[qi]
    qi = qi + 1
    local wait = apply(e)
    if wait > 0 and not skipping then
      C_Timer.After(wait / (ns.db.settings.speed or 1), function() pump(mine) end)
      return
    end
  end
  finishReplay()
end

-- Plays a saved round: { view = the board before it, events = what happened }.
startReplay = function(last)
  busy, sel = true, nil
  view = R.DeepCopy(last.view)
  replayMarks = {}
  queue, qi, skipping = last.events, 1, false
  token = token + 1
  G.Refresh()
  pump(token)
end

-- The Replay button: the last round again.
function G.Replay()
  local m = ns.db.match
  if not (m and m.last) or view or busy then return end
  G.Log("|cff909090(the last round again)|r")
  startReplay(m.last)
end

function G.Skip()
  if view and not skipping then
    skipping = true
    token = token + 1
    pump(token)
  end
end

-- The computer's plan, worked out a few milliseconds each frame so the game
-- doesn't stutter. It sees the board, its own hand and the counts of yours,
-- never your hand or your plan.
local FRAME_MS = 8
local function chooseAIPlan(st, level, done)
  thinking = true
  local clock = debugprofilestop
  local t0, n = 0, 0
  local function yield()
    n = n + 1
    if clock then
      if clock() - t0 >= FRAME_MS then coroutine.yield() end
    elseif n % 10 == 0 then
      coroutine.yield()
    end
  end
  local o = opponent()
  local co = coroutine.create(function()
    return AI.ChoosePlan(st, OPP, level, ns.Rand, { yield = yield, style = o and o.style })
  end)
  local function step()
    if clock then t0 = clock() end
    local ok, res = coroutine.resume(co)
    if not ok then
      thinking, busy = false, false
      G.Refresh()
      error(res)
    end
    if coroutine.status(co) == "dead" then
      thinking = false
      done(res)
    else
      C_Timer.After(0, step)
    end
  end
  step()
end

function G.LockIn()
  local st = current()
  if not planning() then return end
  local ok, err = R.CheckPlan(st, ME, plan)
  if not ok then UI.Error(err) return end
  local tm = tutorialMatch()
  local scripted = tm and ns.Tutorial.Round(st)
  if scripted and #ns.Tutorial.Remaining(st, plan) > 0 then
    UI.Error(opponent().short .. ": " .. UI.Tutorial.Nudge(st, plan))
    return
  end
  busy, sel = true, nil
  UI.Sound("lock")
  G.Refresh()
  local choose = chooseAIPlan
  if scripted then
    -- the tutorial's scripted rounds: Dorn plays his set hand
    choose = function(s, _, done)
      thinking = true
      C_Timer.After(0.6, function()
        thinking = false
        done(ns.Tutorial.PlanFor(s, OPP, scripted.dorn) or {})
      end)
    end
  end
  local m0 = ns.db.match
  local level = tm and ns.Tutorial.LEVEL or (m0.heroic and "heroic") or opponent().level
  choose(st, level, function(aiPlan)
    if current() ~= st then busy = false; G.Refresh(); return end
    -- The round is played on a copy, which replaces the saved game only if
    -- it went through. If a card errors, the match stays as it was.
    local nxt = R.Clone(st)
    nxt.events = {}
    local ok, err = pcall(R.Resolve, nxt, { plan, aiPlan })
    if not ok then
      busy = false
      G.Refresh()
      UI.Error("Deckhand hit an error playing that round. Your match is unchanged.")
      ns.Print("Error playing the round (please report it): %s", tostring(err))
      return
    end
    local events = nxt.events
    nxt.events = nil
    local m = ns.db.match
    -- saved with the match, so the round can be shown again (the Replay
    -- button, or after a /reload that cut the replay short)
    m.last = { view = makeView(st, #aiPlan), events = events }
    m.shown = false
    m.st = nxt
    plan = {}
    local n = m.stats or { dealt = 0, taken = 0, kills = 0, lost = 0 }
    m.stats = n
    for _, e in ipairs(events) do
      if e.t == "morale" and e.delta < 0 then
        if e.p == OPP then n.dealt = n.dealt - e.delta else n.taken = n.taken - e.delta end
      elseif e.t == "die" then
        if e.p == OPP then n.kills = n.kills + 1 else n.lost = n.lost + 1 end
      end
    end
    if not m.tutorial then
      local task = C.TaskEvents(ns.db, ns.Today(), events, ME)
      if task then ns.Announce({ task }) end
    end
    startReplay(m.last)
  end)
end

-- ---------------------------------------------------------------------------
-- Starting and ending games
-- ---------------------------------------------------------------------------
-- heroic: a heroic rematch (their heroic deck and AI).
function G.Start(oppId, heroic)
  local o = ns.OpponentById[oppId]
  local ok, why = C.CheckDeck(ns.db)
  if not ok then
    UI.Error(why .. " Fix it in the Cards tab.")
    return
  end
  if heroic and not C.HeroicUnlocked(ns.db) then
    UI.Error(("Heroic rematches open once you've beaten %s."):format(ns.Opponents[#ns.Opponents].short))
    return
  end
  if not C.Unlocked(ns.db, oppId) then
    UI.Error(("Beat %s first."):format(ns.Opponents[o.index - 1].short))
    return
  end
  local mine, theirs = {}, {}
  for i, id in ipairs(ns.db.deck) do mine[i] = id end
  for i, id in ipairs(heroic and o.heroic or o.deck) do theirs[i] = id end
  local st = R.NewGame({
    seed = math.random(1, 2147483646), decks = { mine, theirs },
    names = { UnitName and UnitName("player") or "You", o.name },
  })
  ns.db.match = { opp = oppId, st = st, started = time and time() or 0, version = ns.VERSION, rules = R.RULES_VERSION,
    plain = C.PlainDeck(mine), heroic = heroic and true or nil }
  plan, sel, finished, view = {}, nil, nil, nil
  if logFrame then logFrame.msgs:Clear() end
  local hello = heroic and "rematch" or "hello"
  G.Log("%s%s: \"%s\"", heroic and "|cffc080ffHeroic|r " or "", o.short, o[hello])
  G.Log("|cffffd100Round 1|r")
  G.Refresh()
  G.Say(hello, true)
end

-- The tutorial: a guided match against Dorn (Data/Tutorial.lua). It doesn't
-- use your deck and doesn't count on the circuit; finishing it the first
-- time pays a pack.
function G.StartTutorial()
  if current() then
    UI.Error("Finish or end the match you're in first.")
    return
  end
  local T = ns.Tutorial
  local o = ns.OpponentById[T.OPP]
  local st = T.NewGame({ UnitName and UnitName("player") or "You", o.name })
  ns.db.match = { opp = o.id, st = st, tutorial = true, tut = { ack = 0 }, started = time and time() or 0,
    version = ns.VERSION, rules = R.RULES_VERSION }
  ns.db.settings.seenWelcome = true
  ns.db.settings.seenLaneTip = true   -- the coach covers lanes
  plan, sel, finished, view = {}, nil, nil, nil
  if logFrame then logFrame.msgs:Clear() end
  G.Log("%s: \"Pull up a stool. I'll show you how it's done.\"", o.short)
  G.Log("|cffffd100Round 1|r")
  if UI.tab ~= "play" then UI.SelectTab("play") else G.Refresh() end
end

function G.EndGame(conceded)
  local m = ns.db.match
  if not m then return end
  local st = m.st
  local result = (st.winner == ME) and "win" or (st.winner == OPP) and "loss" or "draw"
  local mine, theirs = math.max(0, st.players[ME].morale), math.max(0, st.players[OPP].morale)
  local rewards
  if m.tutorial then
    rewards = conceded and {} or C.FinishTutorial(ns.db)
    if not conceded then
      -- the coach taught Guard
      ns.db.settings.seenKw = ns.db.settings.seenKw or {}
      ns.db.settings.seenKw.guard = true
    end
  else
    rewards = C.RecordResult(ns.db, m.opp, result, ns.Today(), {
      conceded = conceded, round = st.round, morale = mine, margin = mine - theirs, plain = m.plain, heroic = m.heroic,
    })
  end
  finished = { st = st, opp = m.opp, result = result, rewards = rewards, conceded = conceded, stats = m.stats,
    tutorial = m.tutorial, heroic = m.heroic }
  UI.Sound(result == "win" and "win" or "lose")
  ns.db.match = nil
  plan, sel = {}, nil
  local o = ns.OpponentById[m.opp]
  ns.Print("%s%s against %s (Morale %d to %d).", m.tutorial and "Tutorial: " or m.heroic and "Heroic: " or "",
    result == "win" and "|cff40ff40Victory|r"
    or result == "loss" and "|cffff4040Defeat|r" or "Draw", o.name, math.max(0, st.players[ME].morale),
    math.max(0, st.players[OPP].morale))
  if m.tutorial then ns.Announce(rewards) end
  UI.Refresh()
end

-- Ending a match early. It asks first and counts as a loss. It works at any
-- moment, even while a round is playing out or the opponent is thinking.
if StaticPopupDialogs then
  StaticPopupDialogs.DECKHAND_END_MATCH = {
    text = "End your match against %s?\nIt counts as a loss and earns nothing.",
    button1 = "End match",
    button2 = "Keep playing",
    OnAccept = function() G.EndMatch() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopupDialogs.DECKHAND_END_TUTORIAL = {
    text = "Leave the tutorial?\nYou can start it again from the Play tab.",
    button1 = "Leave",
    button2 = "Keep going",
    OnAccept = function() G.EndMatch() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

function G.AskEndMatch()
  if not current() then return end
  local which = tutorialMatch() and "DECKHAND_END_TUTORIAL" or "DECKHAND_END_MATCH"
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[which] then
    StaticPopup_Show(which, opponent().name)
  else
    G.EndMatch()
  end
end

function G.EndMatch()
  local st = current()
  if not st then return end
  token = token + 1 -- drops the rest of a replay in progress
  view, busy, skipping = nil, false, false
  if ctl.banner then
    ctl.banner:Hide()
    ctl.phase:SetText("")
  end
  local conceded = false
  if not st.winner then -- a game that had just ended keeps its real result
    st.winner = OPP
    conceded = true
  end
  G.EndGame(conceded)
  G.Refresh()
end

function G.Continue()
  finished = nil
  G.Refresh()
end

function G.OnHide()
  sel = nil
end

-- ---------------------------------------------------------------------------
-- Lobby
-- ---------------------------------------------------------------------------
local LEVEL_COLOR = { easy = "|cff40ff40Easy|r", normal = "|cffffd100Normal|r", hard = "|cffff6040Hard|r",
  heroic = "|cffc080ffHeroic|r" }
local rows = {}

local STAR_ON, STAR_OFF = { 1, 0.82, 0 }, { 0.28, 0.26, 0.22 }
local CREST_ON = { 0.75, 0.5, 1 }

-- The lobby shows the circuit, or the heroic rematches once they're open.
local heroicView = false
function G.HeroicView() return heroicView end
function G.SetHeroicView(on)
  heroicView = (on and C.HeroicUnlocked(ns.db)) and true or false
  G.RefreshLobby()
end

function G.RefreshLobby()
  local ok, why = C.CheckDeck(ns.db)
  if ok then
    lobby.deck:SetText("|cff40ff40Your deck: 20 cards, ready|r")
  else
    lobby.deck:SetText("|cffff6040" .. why .. "|r Fix it in the Cards tab.")
  end
  local heroicOpen = C.HeroicUnlocked(ns.db)
  if not heroicOpen then heroicView = false end
  lobby.heroicBtn:SetShown(heroicOpen)
  lobby.heroicBtn:SetText(heroicView and "Back to the circuit" or "Heroic rematches")
  lobby.title:SetText(heroicView and "The Tavern Circuit: |cffc080ffHeroic|r" or "The Tavern Circuit")
  lobby.sub:SetText(heroicView
    and "Their best decks, their sharpest play."
    or "Pick an opponent. Games are saved, so you can stop any time.")
  for _, r in ipairs(rows) do
    local o = r.opp
    local open = C.Unlocked(ns.db, o.id)
    local rec
    if heroicView then
      rec = ns.db.heroic[o.id]
      for i, tex in ipairs(r.stars) do
        tex:SetShown(i == 1)
        local col = (rec and rec.beaten) and CREST_ON or STAR_OFF
        tex:SetVertexColor(col[1], col[2], col[3])
      end
      r.lvl:SetText(LEVEL_COLOR.heroic)
    else
      rec = ns.db.record[o.id]
      local stars = C.Stars(ns.db, o.id)
      for i, tex in ipairs(r.stars) do
        tex:Show()
        local col = stars[i] and STAR_ON or STAR_OFF
        tex:SetVertexColor(col[1], col[2], col[3])
      end
      r.lvl:SetText(LEVEL_COLOR[o.level] or o.level)
    end
    if not open then
      r.record:SetText("Beat " .. ns.Opponents[o.index - 1].short .. " first")
    elseif rec and (rec.w + rec.l + rec.d) > 0 then
      r.record:SetText(("Won %d  Lost %d%s"):format(rec.w, rec.l, rec.d > 0 and ("  Drawn " .. rec.d) or ""))
    else
      r.record:SetText("Not played yet")
    end
    r.play:SetText(open and "Play" or "Locked")
    r.play:SetEnabled((ok and open) and true or false)
    r:SetAlpha(open and 1 or 0.55)
  end
  local s = ns.db.stats
  lobby.stats:SetText(("Overall: %d won, %d lost, %d drawn"):format(s.wins, s.losses, s.draws))
  local done = ns.db.tutorial and ns.db.tutorial.done
  lobby.tutorial:SetText(done and "Tutorial" or ("Tutorial (+%d pack)"):format(C.TUTORIAL_PACKS))
  lobby.welcome:SetShown(not ns.db.settings.seenWelcome)
  local d, task = C.Daily(ns.db, ns.Today())
  if d.done then
    lobby.daily:SetText(("|cff40ff40Daily task done:|r %s."):format(task.text))
  else
    lobby.daily:SetText(("|cffffd100Daily task:|r %s  (%d/%d)  |cff9fdfff+%d shards|r"):format(task.text, d.n, task.goal, C.REWARD.daily))
  end
end

local function buildLobby()
  lobby = CreateFrame("Frame", nil, page)
  lobby:SetAllPoints()
  local title = UI.Text(lobby, 14)
  title:SetPoint("TOPLEFT", 4, -2)
  title:SetText("The Tavern Circuit")
  title:SetTextColor(1, 0.82, 0)
  lobby.title = title
  local sub = UI.Text(lobby, 10)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText("Pick an opponent. Games are saved, so you can stop any time.")
  sub:SetTextColor(0.7, 0.7, 0.7)
  lobby.sub = sub
  lobby.deck = UI.Text(lobby, 10)
  lobby.deck:SetPoint("TOPRIGHT", -4, -2)

  for i, o in ipairs(ns.Opponents) do
    local r = CreateFrame("Frame", nil, lobby, UI.TEMPLATE)
    r:SetSize(PAGE_W - 8, 46)
    r:SetPoint("TOPLEFT", 4, -42 - (i - 1) * 50)
    UI.Backdrop(r, { 0.09, 0.08, 0.06, 0.9 }, { 0.3, 0.26, 0.18 })
    r.opp = o
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture(UI.Icon(o.icon))
    local name = UI.Text(r, 13)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    name:SetText(o.name)
    name:SetTextColor(1, 0.82, 0)
    local lvl = UI.Text(r, 10)
    lvl:SetPoint("LEFT", name, "RIGHT", 8, 0)
    lvl:SetText(LEVEL_COLOR[o.level] or o.level)
    r.lvl = lvl
    local ttl = UI.Text(r, 10)
    ttl:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    ttl:SetText(o.title)
    ttl:SetTextColor(0.7, 0.7, 0.7)
    r.stars = {}
    for k = 1, #C.STARS do
      local tex = r:CreateTexture(nil, "ARTWORK")
      tex:SetSize(20, 20)
      tex:SetPoint("LEFT", r, "LEFT", 440 + (k - 1) * 23, 0)
      tex:SetTexture(UI.ART .. "Star")
      r.stars[k] = tex
    end
    r.record = UI.Text(r, 10)
    r.record:SetPoint("RIGHT", r, "RIGHT", -106, 0)
    r.record:SetTextColor(0.75, 0.75, 0.75)
    r.play = UI.Button(r, "Play", 90, 26, function() G.Start(o.id, heroicView) end)
    r.play:SetPoint("RIGHT", -8, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if heroicView then
        GameTooltip:AddLine(o.name .. " |cffc080ff(Heroic)|r")
        GameTooltip:AddLine("\"" .. o.rematch .. "\"", 0.85, 0.85, 0.85, true)
        local rec = ns.db.heroic[o.id]
        if rec and rec.beaten then
          GameTooltip:AddLine("Beaten on heroic.", 0.75, 0.5, 1)
        else
          GameTooltip:AddLine(("First heroic win: a card pack and a %s %s."):format(UI.Rainbow("holographic"),
            UI.CardName(o.signature)), 1, 0.82, 0, true)
        end
        GameTooltip:AddLine(("Wins pay %d shards."):format(C.REWARD.win.heroic), 0.62, 0.87, 1)
        GameTooltip:Show()
        return
      end
      GameTooltip:AddLine(o.name)
      GameTooltip:AddLine("\"" .. o.hello .. "\"", 0.85, 0.85, 0.85, true)
      local stars = C.Stars(ns.db, o.id)
      for k, s in ipairs(C.STARS) do
        if stars[k] then
          GameTooltip:AddLine(s.name .. ": earned", 0.4, 1, 0.4)
        else
          GameTooltip:AddLine(("%s: %s Reward: %s."):format(s.name, s.text, k == 2 and UI.CardName(o.signature) or s.reward),
            1, 0.82, 0, true)
        end
      end
      if not C.Unlocked(ns.db, o.id) then
        GameTooltip:AddLine(("Locked: beat %s first."):format(ns.Opponents[o.index - 1].short), 1, 0.4, 0.4)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
  end

  lobby.daily = UI.Text(lobby, 11)
  lobby.daily:SetPoint("BOTTOMLEFT", 6, 24)
  lobby.daily:SetTextColor(0.85, 0.85, 0.85)
  lobby.stats = UI.Text(lobby, 10)
  lobby.stats:SetPoint("BOTTOMLEFT", 6, 6)
  lobby.stats:SetTextColor(0.75, 0.75, 0.75)

  lobby.tutorial = UI.Button(lobby, "Tutorial", 130, 20, function() G.StartTutorial() end)
  lobby.tutorial:SetPoint("TOPRIGHT", -108, -17)
  UI.SimpleTooltip(lobby.tutorial, "Tutorial", "A short guided match against Flightmaster Dorn: four rounds with his help, then you finish it.",
    "It doesn't use your deck or count on the circuit. Finishing it the first time earns a card pack.")
  local guide = UI.Button(lobby, "Guide", 100, 20, function() UI.SelectTab("guide") end)
  guide:SetPoint("TOPRIGHT", -4, -17)
  UI.SimpleTooltip(guide, "Guide", "Every rule and keyword, with diagrams.")
  lobby.heroicBtn = UI.Button(lobby, "Heroic rematches", 150, 20, function() G.SetHeroicView(not heroicView) end)
  lobby.heroicBtn:SetPoint("TOPRIGHT", -242, -17)
  UI.SimpleTooltip(lobby.heroicBtn, "Heroic rematches", "Every opponent again, with their best deck and the sharpest computer play.",
    "The first win against each pays a card pack and a holographic copy of their signature card.")
  lobby.heroicBtn:Hide()

  -- the first time: offer the tutorial
  local w = CreateFrame("Frame", nil, lobby, UI.TEMPLATE)
  w:SetSize(470, 250)
  w:SetPoint("TOP", 0, -90)
  w:SetFrameLevel(lobby:GetFrameLevel() + 10)
  UI.Backdrop(w, { 0.04, 0.035, 0.03, 0.98 }, { 0.75, 0.6, 0.25 }, true)
  w:EnableMouse(true)
  local icon = w:CreateTexture(nil, "ARTWORK")
  icon:SetSize(48, 48)
  icon:SetPoint("TOPLEFT", 18, -18)
  icon:SetTexture(UI.Icon(ns.OpponentById[ns.Tutorial.OPP].icon))
  local wt = UI.Text(w, 16)
  wt:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)
  wt:SetText("Welcome to Deckhand")
  wt:SetTextColor(1, 0.82, 0)
  local wb = UI.Text(w, 12)
  wb:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
  wb:SetWidth(434)
  wb:SetJustifyH("LEFT")
  wb:SetSpacing(3)
  wb:SetText("A card game for flights and boat rides. Flightmaster Dorn will show you how it works in a short " ..
    "guided match: four rounds with his help, then you finish it yourself. Finishing it earns a card pack.\n\n" ..
    "|cffb0b0b0Know how to play already? Skip it. The tutorial stays on this page, and the Guide tab has every rule.|r")
  local go = UI.Button(w, "Play the tutorial", 150, 26, function() G.StartTutorial() end)
  go:SetPoint("BOTTOMLEFT", 18, 16)
  local read = UI.Button(w, "Open the Guide", 130, 26, function()
    ns.db.settings.seenWelcome = true
    UI.SelectTab("guide")
  end)
  read:SetPoint("LEFT", go, "RIGHT", 8, 0)
  local skip = UI.Button(w, "Skip", 80, 26, function()
    ns.db.settings.seenWelcome = true
    w:Hide()
  end)
  skip:SetPoint("BOTTOMRIGHT", -18, 16)
  w:Hide()
  lobby.welcome = w
end

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------
local function badge(parent, size)
  local b = CreateFrame("Button", nil, parent, UI.TEMPLATE)
  b:SetSize(size, size)
  UI.Backdrop(b, { 0, 0, 0, 1 }, { 0.75, 0.5, 1 })
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 1, -1)
  b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", function(self)
    if self.cardId then UI.CardTooltip(self, self.cardId, nil, nil, { "|cff40ff40Planned. Click to take it back.|r" }) end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function buildSlot(p, l)
  local s = CreateFrame("Button", nil, board, UI.TEMPLATE)
  s:SetSize(SW, SH)
  s:SetPoint("TOPLEFT", board, "TOPLEFT", LX + (l - 1) * (SW + LGAP), ROW_Y[p])
  UI.Backdrop(s, { 0.06, 0.05, 0.04, 0.55 }, { 0.32, 0.28, 0.22, 0.9 }, true)
  s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  s:SetScript("OnClick", function(_, button) G.ClickSlot(p, l, button) end)
  local lane = UI.Text(s, 28)
  lane:SetPoint("CENTER")
  lane:SetText(l)
  lane:SetTextColor(0.25, 0.22, 0.18)
  UI.AttachFlash(s)
  s.card = UI.CreateCard(s)
  s.card:SetPoint("CENTER")
  s.card:SetScript("OnClick", function(_, button) G.ClickSlot(p, l, button) end)
  s.card:Hide()
  s.badges = {}
  for i = 1, 3 do
    local b = badge(s, 26)
    b:SetPoint("TOPRIGHT", s, "TOPRIGHT", 4 - (i - 1) * 24, 4)
    b:SetFrameLevel(s.card:GetFrameLevel() + 8)
    b:SetScript("OnClick", function(self)
      if planning() and self.cardId then
        removeAt(p, l, self.cardId)
        G.Refresh()
      end
    end)
    s.badges[i] = b
  end
  slots[p][l] = s
end

local function buildPanel(p)
  local f = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  f:SetSize(PANEL_W, SH)
  f:SetPoint("TOPLEFT", board, "TOPLEFT", 0, ROW_Y[p])
  UI.Backdrop(f, { 0.08, 0.07, 0.05, 0.85 }, p == ME and { 0.25, 0.45, 0.7 } or { 0.65, 0.25, 0.2 })
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(34, 34)
  f.icon:SetPoint("TOPLEFT", 6, -6)
  f.icon:SetTexture(UI.Icon(p == ME and { "Interface\\Icons\\INV_BannerPVP_02" } or { "Interface\\Icons\\INV_BannerPVP_01" }))
  f.name = UI.Text(f, 10)
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 5, 0)
  f.name:SetPoint("RIGHT", f, "RIGHT", -4, 0)
  f.name:SetHeight(34)
  f.name:SetJustifyH("LEFT")
  f.name:SetJustifyV("MIDDLE")
  f.name:SetWordWrap(true)
  local label = UI.Text(f, 10)
  label:SetPoint("TOPLEFT", 8, -48)
  label:SetText("Morale")
  label:SetTextColor(0.7, 0.7, 0.7)
  f.morale = UI.Text(f, 34, "OUTLINE")
  f.morale:SetPoint("TOPLEFT", 8, -62)
  f.predict = UI.Text(f, 17, "OUTLINE")
  f.predict:SetPoint("BOTTOMLEFT", f.morale, "BOTTOMRIGHT", 6, 3)
  f.counts = UI.Text(f, 10)
  f.counts:SetPoint("BOTTOMLEFT", 8, 8)
  f.counts:SetTextColor(0.7, 0.7, 0.7)
  UI.AttachFlash(f)
  UI.AttachFloat(f)
  f:EnableMouse(true)
  UI.SimpleTooltip(f, "Morale", "When it reaches 0 at the end of a round, that player loses. After round 8 the higher Morale wins.",
    "Units with nothing across from them in their lane hit Morale. The small number beside it is what your plan does this round if your opponent plays nothing new.")
  panels[p] = f
end

local function buildBoard()
  board = CreateFrame("Frame", nil, page)
  board:SetAllPoints()
  board:EnableMouse(true)
  board:SetScript("OnMouseDown", function() if view then G.Skip() end end)
  local wood = board:CreateTexture(nil, "BACKGROUND")
  wood:SetPoint("TOPLEFT", -6, 4)
  wood:SetPoint("BOTTOMRIGHT", 6, -6)
  wood:SetTexture(UI.ART .. "Board")
  wood:SetTexCoord(0, 1, 0, 0.72)
  wood:SetVertexColor(0.72, 0.72, 0.72)

  -- each lane is a column joining the enemy slot and yours, with a marker
  -- between them showing what the lane does in combat
  for l = 1, R.LANES do
    local col = CreateFrame("Frame", nil, board, UI.TEMPLATE)
    col:SetPoint("TOPLEFT", board, "TOPLEFT", laneX(l) - 2, ROW_Y[OPP] + 2)
    col:SetSize(SW + 4, (ROW_Y[OPP] - ROW_Y[ME]) + SH + 4)
    col:SetFrameLevel(board:GetFrameLevel())
    UI.Backdrop(col, { 0.02, 0.02, 0.02, 0.35 }, { 0.62, 0.52, 0.32, 0.55 })

    local m = CreateFrame("Frame", nil, board)
    m:SetSize(SW, 38)
    m:SetPoint("CENTER", board, "TOPLEFT", laneX(l) + SW / 2, MID_Y)
    m.line = m:CreateTexture(nil, "BACKGROUND")
    m.line:SetWidth(3)
    m.line:SetPoint("TOP", board, "TOPLEFT", laneX(l) + SW / 2, ROW_Y[OPP] - SH)
    m.line:SetPoint("BOTTOM", board, "TOPLEFT", laneX(l) + SW / 2, ROW_Y[ME])
    m.arrow = m:CreateTexture(nil, "ARTWORK")
    m.arrow:SetSize(22, 22)
    m.arrow:SetPoint("CENTER", m, "CENTER", -11, 5)
    m.swords = m:CreateTexture(nil, "ARTWORK")
    m.swords:SetSize(22, 22)
    m.swords:SetPoint("CENTER", m, "CENTER", 0, 5)
    m.swords:SetTexture(UI.Icon({ "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Sword_04" }))
    m.swords:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    m.num = UI.Text(m, 18, "OUTLINE")
    m.num:SetPoint("LEFT", m.arrow, "RIGHT", 1, 0)
    m.label = UI.Text(m, 9)
    m.label:SetPoint("BOTTOM", m, "BOTTOM", 0, 0)
    UI.AttachFlash(m)
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Lane " .. l)
      if self.lines then
        for _, line in ipairs(self.lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:AddLine("This assumes " .. (opponent() and opponent().short or "they") ..
          " plays nothing new. They're planning too.", 0.6, 0.6, 0.6, true)
      else
        GameTooltip:AddLine("Every unit strikes the enemy unit straight across from it in its lane, or the enemy's Morale if that slot is empty.", 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    markers[l] = m
  end

  for p = 1, 2 do
    buildPanel(p)
    for l = 1, R.LANES do buildSlot(p, l) end
  end

  -- middle band
  ctl.round = UI.Text(board, 12)
  ctl.round:SetPoint("TOPLEFT", board, "TOPLEFT", 6, ROW_Y[OPP] - SH - 6)
  ctl.round:SetTextColor(1, 0.82, 0)
  ctl.init = UI.Text(board, 10)
  ctl.init:SetPoint("TOPLEFT", ctl.round, "BOTTOMLEFT", 0, -3)
  ctl.init:SetTextColor(0.7, 0.7, 0.7)
  local initHelp = CreateFrame("Frame", nil, board)
  initHelp:SetPoint("TOPLEFT", ctl.round, "TOPLEFT")
  initHelp:SetSize(PANEL_W, 32)
  initHelp:EnableMouse(true)
  UI.SimpleTooltip(initHelp, "Initiative", "The player with initiative has their Arrive effects and tactics resolve first. It alternates every round.")
  ctl.phase = UI.Text(board, 20, "OUTLINE")
  ctl.phase:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, MID_Y + 10)
  ctl.phase:SetTextColor(1, 0.82, 0)

  -- the first time: what the columns and markers mean
  local tip = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  tip:SetSize(340, 140)
  tip:SetPoint("CENTER", board, "TOPLEFT", laneX(1) + (4 * SW + 3 * LGAP) / 2, MID_Y)
  tip:SetFrameLevel(board:GetFrameLevel() + 35)
  UI.Backdrop(tip, { 0.05, 0.045, 0.04, 0.97 }, { 1, 0.82, 0 }, true)
  tip:EnableMouse(true)
  local tt = UI.Text(tip, 12)
  tt:SetPoint("TOPLEFT", 12, -10)
  tt:SetPoint("TOPRIGHT", -12, -10)
  tt:SetJustifyH("LEFT")
  tt:SetSpacing(2)
  tt:SetText("|cffffd100How lanes work|r\n" ..
    "Each column is a lane. Every unit strikes the enemy unit straight across from it. " ..
    "If that enemy slot is empty, it hits their Morale instead.\n" ..
    "The markers between the rows show what each lane will do this round. Hover one for details.")
  local ok = UI.Button(tip, "Got it", 80, 22, function()
    ns.db.settings.seenLaneTip = true
    tip:Hide()
    G.Refresh()
  end)
  ok:SetPoint("BOTTOM", 0, 8)
  tip:Hide()
  ctl.laneTip = tip

  -- the first time a keyword turns up
  local kt = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  kt:SetSize(300, 246)
  kt:SetPoint("CENTER", board, "TOPLEFT", laneX(1) + (4 * SW + 3 * LGAP) / 2, MID_Y)
  kt:SetFrameLevel(board:GetFrameLevel() + 36)
  UI.Backdrop(kt, { 0.05, 0.045, 0.04, 0.98 }, { 0.5, 0.75, 1 }, true)
  kt:EnableMouse(true)
  kt.title = UI.Text(kt, 14)
  kt.title:SetPoint("TOP", 0, -10)
  kt.title:SetTextColor(0.5, 0.75, 1)
  kt.diagram = UI.Guide.Diagram(kt, "lanes", 256, 128)
  kt.diagram:SetPoint("TOP", 0, -30)
  kt.text = UI.Text(kt, 12)
  kt.text:SetPoint("TOP", kt.diagram, "BOTTOM", 0, -6)
  kt.text:SetWidth(272)
  kt.text:SetJustifyH("CENTER")
  local gotIt = UI.Button(kt, "Got it", 80, 22, function() G.DismissKeyword() end)
  gotIt:SetPoint("BOTTOM", 0, 8)
  kt:Hide()
  ctl.kwTip = kt

  -- right column
  local sl = UI.Text(board, 11)
  sl:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -4)
  sl:SetText("Supply left")
  sl:SetTextColor(0.8, 0.8, 0.8)
  ctl.supply = UI.Text(board, 30, "OUTLINE")
  ctl.supply:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -3)
  ctl.supply:SetTextColor(0.45, 0.7, 1)
  local supplyHelp = CreateFrame("Frame", nil, board)
  supplyHelp:SetPoint("TOPLEFT", sl, "TOPLEFT")
  supplyHelp:SetSize(100, 50)
  supplyHelp:EnableMouse(true)
  UI.SimpleTooltip(supplyHelp, "Supply", "What you can spend this round: 1 in round 1, 2 in round 2 and so on, up to 6. Unspent supply is lost.")

  ctl.freeLabel = UI.Text(board, 10)
  ctl.freeLabel:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X + 106, -4)
  ctl.freeLabel:SetText("Also casting:")
  ctl.freeLabel:SetTextColor(0.8, 0.8, 0.8)
  ctl.free = {}
  for i = 1, 4 do
    local b = badge(board, 26)
    b:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X + 106 + (i - 1) * 29, -20)
    b:SetScript("OnClick", function(self)
      if not planning() then return end
      for k = #plan, 1, -1 do
        if plan[k].h == self.h then table.remove(plan, k) end
      end
      UI.Sound("back")
      G.Refresh()
    end)
    ctl.free[i] = b
  end

  ctl.lock = UI.Button(board, "Lock In", RIGHT_W, 34, function() G.LockIn() end)
  ctl.lock:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -62)
  ctl.clear = UI.Button(board, "Clear", RIGHT_W / 2 - 3, 22, function() G.ClearPlan() end)
  ctl.clear:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -102)
  ctl.replay = UI.Button(board, "Replay", RIGHT_W / 2 - 3, 22, function() G.Replay() end)
  ctl.replay:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X + RIGHT_W / 2 + 3, -102)
  UI.SimpleTooltip(ctl.replay, "Replay", "Shows the last round again.")

  ctl.endMatch = UI.Button(board, "End match", RIGHT_W, 22, function() G.AskEndMatch() end)
  ctl.endMatch:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, ROW_Y[ME] - SH + 24)
  UI.SimpleTooltip(ctl.endMatch, "End match",
    "Ends this match now. It counts as a loss and earns nothing.",
    "You don't need to end a match to stop playing: it's saved after every round, so you can just close the window.")

  -- hand cards: click one and then a lane, or drag it onto the lane
  for i = 1, R.HAND_MAX do
    local b = UI.CreateCard(board)
    b:SetScript("OnClick", function(self, button) G.ClickHand(self.h, button) end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
      if planning() and self.h and sel ~= self.h then G.ClickHand(self.h, "LeftButton") end
    end)
    b:SetScript("OnDragStop", function() G.Drop() end)
    b:Hide()
    handCards[i] = b
  end

  ctl.hint = UI.Text(board, 11)
  ctl.hint:SetPoint("TOP", board, "TOPLEFT", PAGE_W / 2, HAND_Y - UI.CARD_H - 6)
  ctl.hint:SetTextColor(0.9, 0.9, 0.9)

  -- the opponent's lines, under their panel
  local bub = CreateFrame("Button", nil, board, UI.TEMPLATE)
  bub:SetSize(236, 44)
  bub:SetPoint("TOPLEFT", panels[OPP], "BOTTOMLEFT", 0, -4)
  bub:SetFrameLevel(board:GetFrameLevel() + 28)
  UI.Backdrop(bub, { 0.93, 0.89, 0.78, 0.97 }, { 0.35, 0.27, 0.15 }, true)
  bub.text = UI.Text(bub, 11)
  bub.text:SetPoint("TOPLEFT", 8, -4)
  bub.text:SetPoint("BOTTOMRIGHT", -8, 4)
  bub.text:SetJustifyH("LEFT")
  bub.text:SetJustifyV("MIDDLE")
  bub.text:SetTextColor(0.2, 0.13, 0.06)
  bub.text:SetShadowOffset(0, 0)
  bub:SetScript("OnClick", function(self) self:Hide() end)
  bub:Hide()
  ctl.bubble = bub

  -- the tactic being cast, over the lanes
  local bn = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  bn:SetSize(320, 142)
  bn:SetPoint("CENTER", board, "TOPLEFT", LX + (4 * SW + 3 * LGAP) / 2, MID_Y)
  bn:SetFrameLevel(board:GetFrameLevel() + 30)
  UI.Backdrop(bn, { 0.05, 0.04, 0.08, 0.96 }, { 0.75, 0.5, 1 }, true)
  bn.card = UI.CreateCard(bn)
  bn.card:SetPoint("LEFT", 8, 0)
  bn.card:EnableMouse(false)
  bn.who = UI.Text(bn, 12)
  bn.who:SetPoint("TOPLEFT", bn.card, "TOPRIGHT", 12, -24)
  bn.who:SetTextColor(0.8, 0.8, 0.8)
  bn.what = UI.Text(bn, 16)
  bn.what:SetPoint("TOPLEFT", bn.who, "BOTTOMLEFT", 0, -6)
  bn.where = UI.Text(bn, 11)
  bn.where:SetPoint("TOPLEFT", bn.what, "BOTTOMLEFT", 0, -6)
  bn.where:SetTextColor(0.7, 0.7, 0.7)
  bn:Hide()
  ctl.banner = bn

  -- end of game
  local ov = CreateFrame("Frame", nil, board)
  ov:SetAllPoints()
  ov:SetFrameLevel(board:GetFrameLevel() + 40)
  ov:EnableMouse(true)
  local shade = ov:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.55)
  local box = CreateFrame("Frame", nil, ov, UI.TEMPLATE)
  box:SetSize(440, 290)
  box:SetPoint("CENTER", 0, 40)
  UI.Backdrop(box, { 0.05, 0.045, 0.04, 0.98 }, { 0.75, 0.6, 0.25 }, true)
  ov.title = UI.Text(box, 30, "OUTLINE")
  ov.title:SetPoint("TOP", 0, -14)
  ov.quote = UI.Text(box, 12)
  ov.quote:SetPoint("TOP", ov.title, "BOTTOM", 0, -8)
  ov.quote:SetWidth(410)
  ov.quote:SetTextColor(0.8, 0.8, 0.8)
  ov.body = UI.Text(box, 12)
  ov.body:SetPoint("TOP", ov.quote, "BOTTOM", 0, -10)
  ov.body:SetWidth(410)
  ov.body:SetSpacing(2)
  local cont = UI.Button(box, "Continue", 100, 24, function() G.Continue() end)
  cont:SetPoint("BOTTOM", 0, 12)
  ov:Hide()
  ctl.over = ov
end

-- What the tutorial's coach needs to point at things.
G.api = {
  handFrame = function(id)
    for i = 1, R.HAND_MAX do
      local b = handCards[i]
      if b:IsShown() and b.h and b.cardId == id then return b end
    end
  end,
  slot = function(p, l) return slots[p][l] end,
  lock = function() return ctl.lock end,
}

function G.Build(parent)
  page = parent
  buildLobby()
  buildBoard()
  buildLog(board)
  if UI.Tutorial then UI.Tutorial.Build(board, LOG_Y + 22, PAGE_W, 102) end
  page:SetScript("OnShow", function() G.Refresh() end)
end
