-- The Play tab: the opponent list, the board, planning a round, the computer
-- opponent's turn, the round replay and the end-of-game screen.
--
-- You are always player 1 and the computer player 2. The running game lives
-- in DeckhandCharDB.match, so it survives /reload and logging out.
local _, ns = ...
local R, Cards, AI, C = ns.Rules, ns.Cards, ns.AI, ns.Collection
local UI = ns.UI

local G = {}
UI.Game = G

local ME, OPP = 1, 2
local PAGE_W = 544
local SW, SH = UI.CARD_W + 4, UI.CARD_H + 4
local LX, LGAP = 106, 6
local ROW_Y = { [OPP] = -2, [ME] = -138 }
local HAND_Y = -248
local RIGHT_X = 412
local BEAT = 0.5
local MID_Y = -118 -- middle of the band between the two rows

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

local function current() return ns.db.match and ns.db.match.st end
local function shown() return current() or (finished and finished.st) end
local function opponent()
  local id = (ns.db.match and ns.db.match.opp) or (finished and finished.opp)
  return id and ns.OpponentById[id]
end
local function who(p) return p == ME and "You" or (opponent() and opponent().short or "They") end
local function whose(p) return p == ME and "your" or ((opponent() and opponent().short or "their") .. "'s") end

-- ---------------------------------------------------------------------------
-- Log (a panel beside the window)
-- ---------------------------------------------------------------------------
local logFrame

function G.Log(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  if logFrame then logFrame.msgs:AddMessage(msg, 0.9, 0.9, 0.9) end
  if ctl.last then ctl.last:SetText(msg) end
end

local function buildLog(parent)
  logFrame = CreateFrame("Frame", nil, parent, UI.TEMPLATE)
  logFrame:SetSize(230, 300)
  logFrame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 14, 0)
  UI.Backdrop(logFrame, { 0.045, 0.04, 0.035, 0.95 }, { 0.55, 0.45, 0.25 }, true)
  local t = UI.Text(logFrame, 11)
  t:SetPoint("TOPLEFT", 8, -6)
  t:SetText("Game log")
  t:SetTextColor(1, 0.82, 0)
  local msgs = CreateFrame("ScrollingMessageFrame", nil, logFrame)
  msgs:SetPoint("TOPLEFT", 8, -22)
  msgs:SetPoint("BOTTOMRIGHT", -8, 8)
  msgs:SetFont(UI.FONT, 10, "")
  msgs:SetJustifyH("LEFT")
  msgs:SetFading(false)
  msgs:SetMaxLines(300)
  msgs:EnableMouseWheel(true)
  msgs:SetScript("OnMouseWheel", function(self, d)
    if d > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  logFrame.msgs = msgs
  logFrame:SetShown(ns.db.settings.showLog and true or false)
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
local function computeForecast(st)
  local c = R.Clone(st)
  c.rng = R.Seed(7) -- random effects: any outcome will do for a preview
  c.events = {}
  if not pcall(R.Resolve, c, { plan, {} }, { noAdvance = true }) then return nil end
  local f = { dies = { {}, {} }, loss = {}, winner = c.winner, strikes = { {}, {} } }
  for _, e in ipairs(c.events) do
    if e.t == "strike" and not f.strikes[e.p][e.lane] then f.strikes[e.p][e.lane] = e end
  end
  for p = 1, 2 do
    f.loss[p] = st.players[p].morale - c.players[p].morale
    for l = 1, R.LANES do
      local before, after = st.players[p].board[l], c.players[p].board[l]
      if before then
        if not after or after.uid ~= before.uid then f.dies[p][l] = true end
      elseif p == ME then
        local a = plannedUnitAt(l)
        if a and not (after and after.id == a.id) then f.dies[p][l] = true end
      end
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
  local planning = current() and not view and not busy
  local dies = planning and forecast and forecast.dies[p][l]
  if u then
    card:SetCard(u.id, u, S)
    if dies then card:SetTag("dies", 1, 0.3, 0.3) end
  elseif p == ME and planning and plannedUnitAt(l) then
    card:SetCard(plannedUnitAt(l).id)
    card:SetAlpha(0.8)
    if dies then card:SetTag("dies", 1, 0.3, 0.3) else card:SetTag("planned", 0.4, 1, 0.4) end
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
    pn.counts:SetText(("Hand %d   Deck %d"):format(#st.players[p].hand, #st.players[p].deck))
    if p == OPP and o then
      pn.name:SetText(o.name)
      pn.icon:SetTexture(UI.Icon(o.icon))
    else
      pn.name:SetText(UnitName and UnitName("player") or "You")
    end
  end
end

local function renderHand()
  local st = shown()
  local hand = st.players[ME].hand
  local planning = current() and not view and not busy
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
      b:SetCard(hand[h])
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", board, "TOPLEFT", x0 + (i - 1) * (UI.CARD_W + 5), HAND_Y + ((planning and sel == h) and 10 or 0))
      b:SetSelected(planning and sel == h)
      b:SetDim(not planning or (sel ~= h and Cards.byId[hand[h]].cost > left))
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
  if sel then
    local c = Cards.byId[st.players[ME].hand[sel]]
    if c.type == "unit" then return "Click one of your empty lanes (bottom row) for " .. c.name .. "." end
    if c.target == "enemy" then return "Click an enemy lane (top row) for " .. c.name .. "." end
    return "Click one of your units for " .. c.name .. "."
  end
  if forecast and forecast.winner == ME then
    return "This plan wins the game if " .. opponent().short .. " adds nothing new!"
  end
  if #plan == 0 then return "Pick cards from your hand, place them, then Lock In." end
  return "Lock In when ready. Right-click a planned card to take it back."
end

local function renderControls()
  local st = shown()
  local S = view or st
  ctl.round:SetText(("Round %d of %d"):format(S.round, R.MAX_ROUNDS))
  ctl.init:SetText(S.init == ME and "You have initiative" or (who(OPP) .. " has initiative"))
  local planning = current() and not view and not busy
  if planning then
    ctl.supply:SetText(("%d/%d"):format(supplyLeft(st), st.players[ME].supply))
  else
    ctl.supply:SetText(("-/%d"):format(st.players[ME].supply))
  end
  ctl.lock:SetEnabled(planning and true or false)
  ctl.lock:SetText(thinking and "Thinking..." or view and "Playing..." or "Lock In")
  ctl.clear:SetEnabled(planning and #plan > 0)
  ctl.endMatch:SetShown(current() ~= nil)
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
    ov.title:SetText("Victory!")
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
  for _, r in ipairs(f.rewards) do
    if r.star then
      lines[#lines + 1] = ("|cffffd100Star earned: %s|r"):format(r.why)
    elseif r.card then
      if r.kind == "shards" then
        lines[#lines + 1] = ("%s (you have it already: |cff9fdfff+%d shards|r)"):format(UI.CardName(r.card), r.dupe)
      else
        lines[#lines + 1] = ("New card: %s (%s)"):format(UI.CardName(r.card), r.why)
      end
    elseif r.unlocked then
      lines[#lines + 1] = ("|cff40ff40%s will play you now.|r"):format(ns.OpponentById[r.unlocked].name)
    elseif r.packs then
      lines[#lines + 1] = ("|cffffd100+%d card pack%s|r (%s)"):format(r.packs, r.packs == 1 and "" or "s", r.why)
    elseif r.shards then
      lines[#lines + 1] = ("|cff9fdfff+%d shard%s|r (%s)"):format(r.shards, r.shards == 1 and "" or "s", r.why)
    end
  end
  if f.conceded then lines[#lines + 1] = "|cff909090Ended early: no reward.|r" end
  ov.body:SetText(table.concat(lines, "\n"))
  ov:Show()
end

function G.Refresh()
  if not page then return end
  -- a game that ended while its last round was still playing out (/reload)
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
  if current() and not view and not busy and ns.db.settings.forecast then forecast = computeForecast(st) end
  for p = 1, 2 do
    for l = 1, R.LANES do renderSlot(p, l) end
  end
  renderMarkers()
  if ctl.laneTip and not ns.db.settings.seenLaneTip and current() and not view and not busy then
    ctl.laneTip:Show()
  end
  renderPanels()
  renderHand()
  renderControls()
  if finished then showGameOver() else ctl.over:Hide() end
end

-- ---------------------------------------------------------------------------
-- Clicks
-- ---------------------------------------------------------------------------
local function planning() return current() and not view and not busy end

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
    if removeAt(p, l) then G.Refresh() end
    return
  end
  local ok, why = validTarget(st, p, l)
  if not ok then
    if why then UI.Error(why) end
    return
  end
  plan[#plan + 1] = { h = sel, id = st.players[ME].hand[sel], lane = l }
  sel = nil
  G.Refresh()
end

function G.Selected() return sel end

function G.ClearPlan()
  if not planning() then return end
  plan, sel = {}, nil
  G.Refresh()
end

-- ---------------------------------------------------------------------------
-- Playing a round
-- ---------------------------------------------------------------------------
local function makeView(st)
  local v = { round = st.round, init = st.init, players = {} }
  for p = 1, 2 do
    v.players[p] = { board = R.DeepCopy(st.players[p].board), morale = st.players[p].morale }
  end
  return v
end

local SET_COLOR = {
  heal = { 0.3, 1, 0.3 }, buff = { 1, 0.85, 0.3 }, freeze = { 0.4, 0.7, 1 }, sturdy = { 1, 1, 1 },
  transform = { 0.8, 0.4, 1 }, reveal = { 0.6, 0.6, 0.8 }, endround = { 0.3, 1, 0.3 },
}

local bannerToken = 0
local function showTactic(e)
  local b = ctl.banner
  b.card:SetCard(e.id)
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
    if cd:IsShown() then cd:Flash(1, 0.85, 0.3) end
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
  ctl.banner:Hide()
  ctl.phase:SetText("")
  local st = current()
  if st and st.winner then G.EndGame() end
  G.Refresh()
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

function G.Skip()
  if view and not skipping then
    skipping = true
    token = token + 1
    pump(token)
  end
end

-- The computer's plan, worked out a little each frame so the game doesn't
-- stutter. It sees the board, its own hand and the counts of yours, never
-- your hand or your plan.
local function chooseAIPlan(st, level, done)
  thinking = true
  local co = coroutine.create(function()
    return AI.ChoosePlan(st, OPP, level, ns.Rand, { yield = coroutine.yield })
  end)
  local function step()
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
  busy, sel = true, nil
  G.Refresh()
  chooseAIPlan(st, opponent().level, function(aiPlan)
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
    view = makeView(st)
    ns.db.match.st = nxt
    plan = {}
    local task = C.TaskEvents(ns.db, ns.Today(), events, ME)
    if task then ns.Announce({ task }) end
    replayMarks = {}
    G.Refresh()
    queue, qi, skipping = events, 1, false
    token = token + 1
    pump(token)
  end)
end

-- ---------------------------------------------------------------------------
-- Starting and ending games
-- ---------------------------------------------------------------------------
function G.Start(oppId)
  local o = ns.OpponentById[oppId]
  local ok, why = C.CheckDeck(ns.db)
  if not ok then
    UI.Error(why .. " Fix it in the Cards tab.")
    return
  end
  if not C.Unlocked(ns.db, oppId) then
    UI.Error(("Beat %s first."):format(ns.Opponents[o.index - 1].short))
    return
  end
  local mine, theirs = {}, {}
  for i, id in ipairs(ns.db.deck) do mine[i] = id end
  for i, id in ipairs(o.deck) do theirs[i] = id end
  local st = R.NewGame({
    seed = math.random(1, 2147483646), decks = { mine, theirs },
    names = { UnitName and UnitName("player") or "You", o.name },
  })
  ns.db.match = { opp = oppId, st = st, started = time and time() or 0, version = ns.VERSION, rules = R.RULES_VERSION,
    plain = C.PlainDeck(mine) }
  plan, sel, finished, view = {}, nil, nil, nil
  if logFrame then logFrame.msgs:Clear() end
  G.Log("%s: \"%s\"", o.short, o.hello)
  G.Log("|cffffd100Round 1|r")
  G.Refresh()
end

function G.EndGame(conceded)
  local m = ns.db.match
  if not m then return end
  local st = m.st
  local result = (st.winner == ME) and "win" or (st.winner == OPP) and "loss" or "draw"
  local mine, theirs = math.max(0, st.players[ME].morale), math.max(0, st.players[OPP].morale)
  local rewards = C.RecordResult(ns.db, m.opp, result, ns.Today(), {
    conceded = conceded, round = st.round, morale = mine, margin = mine - theirs, plain = m.plain,
  })
  finished = { st = st, opp = m.opp, result = result, rewards = rewards, conceded = conceded }
  ns.db.match = nil
  plan, sel = {}, nil
  local o = ns.OpponentById[m.opp]
  ns.Print("%s against %s (Morale %d to %d).", result == "win" and "|cff40ff40Victory|r" or result == "loss"
    and "|cffff4040Defeat|r" or "Draw", o.name, math.max(0, st.players[ME].morale), math.max(0, st.players[OPP].morale))
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
end

function G.AskEndMatch()
  if not current() then return end
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.DECKHAND_END_MATCH then
    StaticPopup_Show("DECKHAND_END_MATCH", opponent().name)
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
local LEVEL_COLOR = { easy = "|cff40ff40Easy|r", normal = "|cffffd100Normal|r", hard = "|cffff6040Hard|r" }
local rows = {}

local STAR_ON, STAR_OFF = { 1, 0.82, 0 }, { 0.28, 0.26, 0.22 }

function G.RefreshLobby()
  local ok, why = C.CheckDeck(ns.db)
  if ok then
    lobby.deck:SetText("|cff40ff40Your deck: 20 cards, ready|r")
  else
    lobby.deck:SetText("|cffff6040" .. why .. "|r Fix it in the Cards tab.")
  end
  for _, r in ipairs(rows) do
    local o = r.opp
    local open = C.Unlocked(ns.db, o.id)
    local stars = C.Stars(ns.db, o.id)
    for i, tex in ipairs(r.stars) do
      local col = stars[i] and STAR_ON or STAR_OFF
      tex:SetVertexColor(col[1], col[2], col[3])
    end
    local rec = ns.db.record[o.id]
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
  local d, task = C.Daily(ns.db, ns.Today())
  if d.done then
    lobby.daily:SetText(("|cff40ff40Daily task done:|r %s."):format(task.text))
  else
    lobby.daily:SetText(("|cffffd100Daily task:|r %s  (%d/%d)  |cff9fdfff+%d shards|r"):format(task.text, d.n, task.goal, C.REWARD.daily))
  end
end

local RULES_TEXT = table.concat({
  "|cffffd100How to play|r",
  "",
  "You and your opponent each start with |cffffffff12 Morale|r. The game lasts up to 8 rounds.",
  "",
  "Each round you draw a card and get |cffffffffSupply|r to spend: 1 in round 1, 2 in round 2, and so on up to 6. Your draws in rounds 1-3 never cost more than that round's Supply (round 1's is always a unit), so you always have something to play.",
  "",
  "Plan your round: click a card in your hand, then click where it goes. Units go into your four lanes (the bottom row). Tactics target a lane. Right-click a planned card to take it back. Then press |cffffffffLock In|r.",
  "",
  "Both sides are revealed at once. New units arrive, then tactics resolve (whoever has initiative goes first; it alternates), then combat.",
  "",
  "|cffffd100Lanes:|r each column on the board is a lane. In combat every unit strikes the enemy unit straight across from it in its lane. If that enemy slot is empty, it hits the enemy's Morale instead. So put units where nothing faces them to hit Morale, and across from their attackers to block them. The markers between the rows show what each lane will do.",
  "",
  "Damage on units stays until they die. The game ends when someone's Morale reaches 0, or after round 8, and the higher Morale wins.",
  "",
  "Hover any card to see what its keywords do. Beating an opponent unlocks the next one; each has three stars to earn. The Packs tab lists the ways to earn cards.",
}, "\n")

local function buildLobby()
  lobby = CreateFrame("Frame", nil, page)
  lobby:SetAllPoints()
  local title = UI.Text(lobby, 14)
  title:SetPoint("TOPLEFT", 4, -2)
  title:SetText("The Tavern Circuit")
  title:SetTextColor(1, 0.82, 0)
  local sub = UI.Text(lobby, 10)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText("Pick an opponent. Games are saved, so you can stop any time.")
  sub:SetTextColor(0.7, 0.7, 0.7)
  lobby.deck = UI.Text(lobby, 10)
  lobby.deck:SetPoint("TOPRIGHT", -4, -2)

  for i, o in ipairs(ns.Opponents) do
    local r = CreateFrame("Frame", nil, lobby, UI.TEMPLATE)
    r:SetSize(PAGE_W - 8, 38)
    r:SetPoint("TOPLEFT", 4, -38 - (i - 1) * 41)
    UI.Backdrop(r, { 0.09, 0.08, 0.06, 0.9 }, { 0.3, 0.26, 0.18 })
    r.opp = o
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", 5, 0)
    icon:SetTexture(UI.Icon(o.icon))
    local name = UI.Text(r, 12)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetText(o.name)
    name:SetTextColor(1, 0.82, 0)
    local lvl = UI.Text(r, 10)
    lvl:SetPoint("LEFT", name, "RIGHT", 8, 0)
    lvl:SetText(LEVEL_COLOR[o.level] or o.level)
    local ttl = UI.Text(r, 9)
    ttl:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    ttl:SetText(o.title)
    ttl:SetTextColor(0.7, 0.7, 0.7)
    r.stars = {}
    for k = 1, #C.STARS do
      local tex = r:CreateTexture(nil, "ARTWORK")
      tex:SetSize(15, 15)
      tex:SetPoint("LEFT", r, "LEFT", 290 + (k - 1) * 17, 0)
      tex:SetTexture(UI.ART .. "Star")
      r.stars[k] = tex
    end
    r.record = UI.Text(r, 9)
    r.record:SetPoint("RIGHT", r, "RIGHT", -94, 0)
    r.record:SetTextColor(0.75, 0.75, 0.75)
    r.play = UI.Button(r, "Play", 80, 24, function() G.Start(o.id) end)
    r.play:SetPoint("RIGHT", -8, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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

  lobby.daily = UI.Text(lobby, 10)
  lobby.daily:SetPoint("BOTTOMLEFT", 6, 19)
  lobby.daily:SetTextColor(0.85, 0.85, 0.85)
  lobby.stats = UI.Text(lobby, 10)
  lobby.stats:SetPoint("BOTTOMLEFT", 6, 4)
  lobby.stats:SetTextColor(0.75, 0.75, 0.75)

  local rules = CreateFrame("Frame", nil, lobby, UI.TEMPLATE)
  rules:SetPoint("TOPLEFT", 30, -30)
  rules:SetPoint("BOTTOMRIGHT", -30, 30)
  rules:SetFrameLevel(lobby:GetFrameLevel() + 10)
  UI.Backdrop(rules, { 0.04, 0.035, 0.03, 0.98 }, { 0.75, 0.6, 0.25 }, true)
  rules:EnableMouse(true)
  local rt = UI.Text(rules, 11)
  rt:SetPoint("TOPLEFT", 14, -12)
  rt:SetPoint("TOPRIGHT", -14, -12)
  rt:SetJustifyH("LEFT")
  rt:SetJustifyV("TOP")
  rt:SetText(RULES_TEXT)
  local closeRules = UI.Button(rules, "Got it", 80, 22, function() rules:Hide() end)
  closeRules:SetPoint("BOTTOM", 0, 10)
  rules:Hide()
  local howTo = UI.Button(lobby, "How to play", 100, 20, function() rules:SetShown(not rules:IsShown()) end)
  howTo:SetPoint("TOPRIGHT", -4, -17)
  if not ns.db.settings.seenRules then
    rules:Show()
    ns.db.settings.seenRules = true
  end
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
  UI.Backdrop(s, { 0.11, 0.10, 0.08, 0.6 }, { 0.32, 0.28, 0.22, 0.9 }, true)
  s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  s:SetScript("OnClick", function(_, button) G.ClickSlot(p, l, button) end)
  local lane = UI.Text(s, 20)
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
    local b = badge(s, 22)
    b:SetPoint("TOPRIGHT", s, "TOPRIGHT", 3 - (i - 1) * 20, 3)
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
  f:SetSize(98, SH)
  f:SetPoint("TOPLEFT", board, "TOPLEFT", 0, ROW_Y[p])
  UI.Backdrop(f, { 0.08, 0.07, 0.05, 0.85 }, p == ME and { 0.25, 0.45, 0.7 } or { 0.65, 0.25, 0.2 })
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(28, 28)
  f.icon:SetPoint("TOPLEFT", 5, -5)
  f.icon:SetTexture(UI.Icon(p == ME and { "Interface\\Icons\\INV_BannerPVP_02" } or { "Interface\\Icons\\INV_BannerPVP_01" }))
  f.name = UI.Text(f, 9)
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 4, 0)
  f.name:SetPoint("RIGHT", f, "RIGHT", -3, 0)
  f.name:SetHeight(28)
  f.name:SetJustifyH("LEFT")
  f.name:SetJustifyV("MIDDLE")
  f.name:SetWordWrap(true)
  local label = UI.Text(f, 9)
  label:SetPoint("TOPLEFT", 6, -38)
  label:SetText("Morale")
  label:SetTextColor(0.7, 0.7, 0.7)
  f.morale = UI.Text(f, 26, "OUTLINE")
  f.morale:SetPoint("TOPLEFT", 6, -50)
  f.predict = UI.Text(f, 14, "OUTLINE")
  f.predict:SetPoint("BOTTOMLEFT", f.morale, "BOTTOMRIGHT", 5, 2)
  f.counts = UI.Text(f, 9)
  f.counts:SetPoint("BOTTOMLEFT", 6, 6)
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

  -- each lane is a column joining the enemy slot and yours, with a marker
  -- between them showing what the lane does in combat
  for l = 1, R.LANES do
    local col = CreateFrame("Frame", nil, board, UI.TEMPLATE)
    col:SetPoint("TOPLEFT", board, "TOPLEFT", laneX(l) - 2, ROW_Y[OPP] + 2)
    col:SetSize(SW + 4, (ROW_Y[OPP] - ROW_Y[ME]) + SH + 4)
    col:SetFrameLevel(board:GetFrameLevel())
    UI.Backdrop(col, { 0.17, 0.15, 0.11, 0.55 }, { 0.42, 0.36, 0.24, 0.6 })

    local m = CreateFrame("Frame", nil, board)
    m:SetSize(SW, 32)
    m:SetPoint("CENTER", board, "TOPLEFT", laneX(l) + SW / 2, MID_Y - 4)
    m.line = m:CreateTexture(nil, "BACKGROUND")
    m.line:SetWidth(3)
    m.line:SetPoint("TOP", board, "TOPLEFT", laneX(l) + SW / 2, ROW_Y[OPP] - SH)
    m.line:SetPoint("BOTTOM", board, "TOPLEFT", laneX(l) + SW / 2, ROW_Y[ME])
    m.arrow = m:CreateTexture(nil, "ARTWORK")
    m.arrow:SetSize(18, 18)
    m.arrow:SetPoint("CENTER", m, "CENTER", -9, 5)
    m.swords = m:CreateTexture(nil, "ARTWORK")
    m.swords:SetSize(20, 20)
    m.swords:SetPoint("CENTER", m, "CENTER", 0, 5)
    m.swords:SetTexture(UI.Icon({ "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\INV_Sword_04" }))
    m.swords:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    m.num = UI.Text(m, 15, "OUTLINE")
    m.num:SetPoint("LEFT", m.arrow, "RIGHT", 1, 0)
    m.label = UI.Text(m, 8)
    m.label:SetPoint("BOTTOM", m, "BOTTOM", 0, 1)
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
  ctl.round = UI.Text(board, 11)
  ctl.round:SetPoint("TOPLEFT", board, "TOPLEFT", 2, -104)
  ctl.round:SetTextColor(1, 0.82, 0)
  ctl.init = UI.Text(board, 9)
  ctl.init:SetPoint("TOPLEFT", ctl.round, "BOTTOMLEFT", 0, -3)
  ctl.init:SetTextColor(0.7, 0.7, 0.7)
  local initHelp = CreateFrame("Frame", nil, board)
  initHelp:SetPoint("TOPLEFT", ctl.round, "TOPLEFT")
  initHelp:SetSize(100, 28)
  initHelp:EnableMouse(true)
  UI.SimpleTooltip(initHelp, "Initiative", "The player with initiative has their Arrive effects and tactics resolve first. It alternates every round.")
  ctl.phase = UI.Text(board, 16, "OUTLINE")
  ctl.phase:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -168)
  ctl.phase:SetTextColor(1, 0.82, 0)

  -- the first time: what the columns and markers mean
  local tip = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  tip:SetSize(300, 132)
  tip:SetPoint("CENTER", board, "TOPLEFT", laneX(1) + (4 * SW + 3 * LGAP) / 2, MID_Y)
  tip:SetFrameLevel(board:GetFrameLevel() + 35)
  UI.Backdrop(tip, { 0.05, 0.045, 0.04, 0.97 }, { 1, 0.82, 0 }, true)
  tip:EnableMouse(true)
  local tt = UI.Text(tip, 11)
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
  end)
  ok:SetPoint("BOTTOM", 0, 8)
  tip:Hide()
  ctl.laneTip = tip

  -- right column
  local sl = UI.Text(board, 10)
  sl:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -4)
  sl:SetText("Supply left")
  sl:SetTextColor(0.7, 0.7, 0.7)
  ctl.supply = UI.Text(board, 24, "OUTLINE")
  ctl.supply:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -3)
  ctl.supply:SetTextColor(0.45, 0.7, 1)
  local supplyHelp = CreateFrame("Frame", nil, board)
  supplyHelp:SetPoint("TOPLEFT", sl, "TOPLEFT")
  supplyHelp:SetSize(120, 40)
  supplyHelp:EnableMouse(true)
  UI.SimpleTooltip(supplyHelp, "Supply", "What you can spend this round: 1 in round 1, 2 in round 2 and so on, up to 6. Unspent supply is lost.")

  ctl.freeLabel = UI.Text(board, 9)
  ctl.freeLabel:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -56)
  ctl.freeLabel:SetText("Also casting:")
  ctl.freeLabel:SetTextColor(0.7, 0.7, 0.7)
  ctl.free = {}
  for i = 1, 4 do
    local b = badge(board, 26)
    b:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X + (i - 1) * 30, -70)
    b:SetScript("OnClick", function(self)
      if not planning() then return end
      for k = #plan, 1, -1 do
        if plan[k].h == self.h then table.remove(plan, k) end
      end
      G.Refresh()
    end)
    ctl.free[i] = b
  end

  ctl.lock = UI.Button(board, "Lock In", 128, 28, function() G.LockIn() end)
  ctl.lock:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -104)
  ctl.clear = UI.Button(board, "Clear", 62, 20, function() G.ClearPlan() end)
  ctl.clear:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -140)
  local logBtn = UI.Button(board, "Log", 62, 20, function()
    ns.db.settings.showLog = not ns.db.settings.showLog
    logFrame:SetShown(ns.db.settings.showLog)
  end)
  logBtn:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X + 66, -140)

  ctl.endMatch = UI.Button(board, "End match", 128, 22, function() G.AskEndMatch() end)
  ctl.endMatch:SetPoint("TOPLEFT", board, "TOPLEFT", RIGHT_X, -212)
  UI.SimpleTooltip(ctl.endMatch, "End match",
    "Ends this match now. It counts as a loss and earns nothing.",
    "You don't need to end a match to stop playing: it's saved after every round, so you can just close the window.")

  -- hand cards
  for i = 1, R.HAND_MAX do
    local b = UI.CreateCard(board)
    b:SetScript("OnClick", function(self, button) G.ClickHand(self.h, button) end)
    b:Hide()
    handCards[i] = b
  end

  ctl.hint = UI.Text(board, 10)
  ctl.hint:SetPoint("TOP", board, "TOPLEFT", PAGE_W / 2, HAND_Y - UI.CARD_H - 8)
  ctl.hint:SetTextColor(0.8, 0.8, 0.8)
  ctl.last = UI.Text(board, 9)
  ctl.last:SetPoint("TOP", ctl.hint, "BOTTOM", 0, -4)
  ctl.last:SetTextColor(0.6, 0.6, 0.6)

  -- the tactic being cast, over the lanes
  local bn = CreateFrame("Frame", nil, board, UI.TEMPLATE)
  bn:SetSize(250, 104)
  bn:SetPoint("CENTER", board, "TOPLEFT", LX + (4 * SW + 3 * LGAP) / 2, -118)
  bn:SetFrameLevel(board:GetFrameLevel() + 30)
  UI.Backdrop(bn, { 0.05, 0.04, 0.08, 0.96 }, { 0.75, 0.5, 1 }, true)
  bn.card = UI.CreateCard(bn)
  bn.card:SetPoint("LEFT", 6, 0)
  bn.card:EnableMouse(false)
  bn.who = UI.Text(bn, 11)
  bn.who:SetPoint("TOPLEFT", bn.card, "TOPRIGHT", 10, -14)
  bn.who:SetTextColor(0.8, 0.8, 0.8)
  bn.what = UI.Text(bn, 14)
  bn.what:SetPoint("TOPLEFT", bn.who, "BOTTOMLEFT", 0, -6)
  bn.where = UI.Text(bn, 10)
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
  box:SetSize(360, 250)
  box:SetPoint("CENTER", 0, 10)
  UI.Backdrop(box, { 0.05, 0.045, 0.04, 0.98 }, { 0.75, 0.6, 0.25 }, true)
  ov.title = UI.Text(box, 26, "OUTLINE")
  ov.title:SetPoint("TOP", 0, -14)
  ov.quote = UI.Text(box, 11)
  ov.quote:SetPoint("TOP", ov.title, "BOTTOM", 0, -8)
  ov.quote:SetWidth(330)
  ov.quote:SetTextColor(0.8, 0.8, 0.8)
  ov.body = UI.Text(box, 11)
  ov.body:SetPoint("TOP", ov.quote, "BOTTOM", 0, -10)
  ov.body:SetWidth(330)
  ov.body:SetSpacing(2)
  local cont = UI.Button(box, "Continue", 100, 24, function() G.Continue() end)
  cont:SetPoint("BOTTOM", 0, 12)
  ov:Hide()
  ctl.over = ov
end

function G.Build(parent)
  page = parent
  buildLobby()
  buildBoard()
  buildLog(page)
  page:SetScript("OnShow", function() G.Refresh() end)
end
