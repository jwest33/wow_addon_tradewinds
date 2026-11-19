-- Deckhand rules engine.
--
-- Pure Lua 5.1 with no WoW API calls, so the same code runs in the client, in
-- the tests (tests/run_tests.py) and, later, on both ends of a PvP match: give
-- two clients the same seed and the same plans and they reach the same state.
--
-- The game: two players, 12 Morale each, 4 lanes. Every round both players
-- secretly plan which cards to play (units into their empty lanes, tactics at
-- a lane), then everything is revealed at once and resolved:
--   1. new units appear, then their Arrive effects run
--   2. tactics resolve (the player with initiative first)
--   3. combat: every unit strikes the enemy unit across from it, or the
--      enemy's Morale when that lane is empty (Swift units strike first)
--   4. end of round
-- The game ends at the end of a round in which someone's Morale reaches 0, or
-- after round 8; the higher Morale wins (tied: more units on the board wins).
local _, ns = ...

local R = {}
ns.Rules = R

-- Bump this whenever the rules or a card's behaviour change. A match saved
-- under another number is ended on load without counting (Collection.Init).
R.RULES_VERSION = 1

R.LANES = 4
R.MAX_ROUNDS = 8
R.START_MORALE = 12
R.MAX_MORALE = 12
R.OPENING_HAND = 4
R.HAND_MAX = 7
R.SUPPLY_CAP = 6
R.DECK_SIZE = 20

local LANES = R.LANES
local floor, max, min = math.floor, math.max, math.min

-- Shown on cards and in tooltips, in this order.
R.KEYWORDS = {
  { key = "swift", name = "Swift", text = "Strikes before other units. A unit it kills doesn't strike back." },
  { key = "guard", name = "Guard", text = "An unblocked enemy in a neighbouring lane strikes this unit instead of your Morale." },
  { key = "ranged", name = "Ranged", text = "Strikes the weakest enemy unit, wherever it is. With no enemy units it strikes Morale." },
  { key = "pierce", name = "Pierce", text = "Damage beyond what kills the unit it strikes carries on to the enemy's Morale." },
  { key = "cleave", name = "Cleave", text = "Also strikes the enemy units in the neighbouring lanes." },
  { key = "venom", name = "Venom", text = "Destroys any unit it damages." },
  { key = "drain", name = "Drain", text = "Damage it deals restores that much of your Morale." },
  { key = "sturdy", name = "Sturdy", text = "The first time it would die, it survives with 1 health instead." },
  { key = "regen", name = "Regenerate", text = "Heals to full at the end of each round." },
  { key = "rally", name = "Rally", text = "Your units in the neighbouring lanes have +1 attack." },
  { key = "stealth", name = "Stealth", text = "Enemy tactics can't target it until it has struck." },
}
R.KEYWORD = {}
for i, k in ipairs(R.KEYWORDS) do k.order = i; R.KEYWORD[k.key] = k end

local function card(id)
  local c = ns.Cards and ns.Cards.byId[id]
  if not c then error("Deckhand: unknown card " .. tostring(id), 2) end
  return c
end
R.Card = card

-- ---------------------------------------------------------------------------
-- Random numbers: Park-Miller "minimal standard". Every step is exact in a
-- double, so all clients produce the same sequence from the same seed.
-- ---------------------------------------------------------------------------
local MOD = 2147483647

function R.Seed(n)
  n = floor(math.abs(tonumber(n) or 1)) % MOD
  if n == 0 then n = 1 end
  return n
end

-- 1..n
function R.Random(st, n)
  st.rng = (st.rng * 16807) % MOD
  return (st.rng % n) + 1
end

local function shuffle(st, t)
  for i = #t, 2, -1 do
    local j = R.Random(st, i)
    t[i], t[j] = t[j], t[i]
  end
end

-- ---------------------------------------------------------------------------
-- Events: while st.events is a table, everything that happens is appended to
-- it so the UI can replay the round. Simulations (the AI) leave it nil.
-- ---------------------------------------------------------------------------
local function emit(st, e)
  local ev = st.events
  if ev then ev[#ev + 1] = e end
end
R.Emit = emit

local function copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  return o
end

function R.DeepCopy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = R.DeepCopy(v) end
  return o
end

-- A copy of the game for simulating; the event list is left out.
function R.Clone(st)
  local ev = st.events
  st.events = nil
  local c = R.DeepCopy(st)
  st.events = ev
  return c
end

function R.Snapshot(u)
  local s = copy(u)
  s.kw = copy(u.kw)
  return s
end

local function setEvent(st, u, why)
  emit(st, { t = "set", p = u.owner, lane = u.lane, unit = R.Snapshot(u), why = why })
end

-- ---------------------------------------------------------------------------
-- Units
-- ---------------------------------------------------------------------------
local function newUnit(st, p, id, lane)
  local c = card(id)
  st.uid = st.uid + 1
  local kw = {}
  if c.kw then for k, v in pairs(c.kw) do kw[k] = v end end
  return {
    uid = st.uid, id = id, owner = p, lane = lane,
    atk = c.atk or 0, hp = c.hp or 1, maxHp = c.hp or 1, tmpAtk = 0,
    kw = kw, new = true,
  }
end

-- Attack right now: base + this round's bonus + Rally from neighbours. Works on
-- any table shaped like a game (the UI passes its replay view).
function R.Attack(st, u)
  local a = u.atk + (u.tmpAtk or 0)
  local board = st.players[u.owner].board
  local n = board[u.lane - 1]
  if n and n.kw.rally then a = a + 1 end
  n = board[u.lane + 1]
  if n and n.kw.rally then a = a + 1 end
  return max(0, a)
end

function R.Units(st, p)
  local out, board = {}, st.players[p].board
  for l = 1, LANES do
    if board[l] then out[#out + 1] = board[l] end
  end
  return out
end

-- The two players, the one with initiative first.
local function order(st)
  return st.init, 3 - st.init
end

-- Can `p`'s tactics target unit u?
function R.Targetable(u, p)
  return u ~= nil and not (u.kw.stealth and u.owner ~= p)
end

-- The enemy unit a tactic aimed at `lane` hits, or nil.
function R.EnemyTarget(st, p, lane)
  local u = lane and st.players[3 - p].board[lane]
  if R.Targetable(u, p) then return u end
end

function R.FriendTarget(st, p, lane)
  return lane and st.players[p].board[lane] or nil
end

-- ---------------------------------------------------------------------------
-- Effects (used by the cards)
-- ---------------------------------------------------------------------------
function R.Damage(st, u, amt)
  if not u or amt <= 0 then return end
  u.hp = u.hp - amt
  emit(st, { t = "dmg", p = u.owner, lane = u.lane, amt = amt, hp = u.hp })
end

function R.HitMorale(st, p, amt)
  if amt <= 0 then return end
  local P = st.players[p]
  P.morale = P.morale - amt
  emit(st, { t = "morale", p = p, delta = -amt, value = P.morale })
end

function R.RestoreMorale(st, p, amt)
  local P = st.players[p]
  local new = min(R.MAX_MORALE, P.morale + amt)
  if new <= P.morale then return end
  local d = new - P.morale
  P.morale = new
  emit(st, { t = "morale", p = p, delta = d, value = new })
end

function R.Heal(st, u, amt)
  if not u or u.hp >= u.maxHp then return end
  u.hp = min(u.maxHp, u.hp + (amt or u.maxHp))
  setEvent(st, u, "heal")
end

-- Permanent stat change and/or a keyword.
function R.Buff(st, u, atk, hp, kw)
  if not u then return end
  u.atk = u.atk + (atk or 0)
  if hp and hp ~= 0 then
    u.maxHp = u.maxHp + hp
    u.hp = u.hp + hp
  end
  if kw then u.kw[kw] = true end
  setEvent(st, u, "buff")
end

-- Bonus attack until the end of the round.
function R.TempAttack(st, u, n)
  if not u then return end
  u.tmpAtk = (u.tmpAtk or 0) + n
  setEvent(st, u, "buff")
end

-- Doesn't strike this round.
function R.Freeze(st, u)
  if not u then return end
  u.frozen = true
  setEvent(st, u, "freeze")
end

function R.Destroy(st, u)
  if u then u.doomed = true end
end

-- Replace u with a fresh `id` (no Fallen effect for the old one).
function R.Transform(st, u, id)
  if not u then return end
  local nu = newUnit(st, u.owner, id, u.lane)
  nu.new = u.new
  st.players[u.owner].board[u.lane] = nu
  setEvent(st, nu, "transform")
  return nu
end

function R.Summon(st, p, lane, id)
  if not lane or lane < 1 or lane > LANES then return end
  local board = st.players[p].board
  if board[lane] then return end
  local u = newUnit(st, p, id, lane)
  board[lane] = u
  emit(st, { t = "place", p = p, lane = lane, unit = R.Snapshot(u), summon = true })
  return u
end

-- The first draws are guided so there's always something to play: round 1's
-- draw is a unit costing 1, round 2's costs 2 or less, round 3's 3 or less,
-- each picked at random among the cards left that qualify. Every other draw
-- (the opening hand included) comes off the top of the shuffled deck. Decks
-- must contain those cards (Collection's curve rule).
R.GUIDED_DRAWS = {
  [1] = { cost = 1, unit = true },
  [2] = { cost = 2 },
  [3] = { cost = 3 },
}

-- rule: optional { cost = max cost, unit = units only }; falls back to the top
-- card when nothing left in the deck qualifies.
function R.Draw(st, p, n, rule)
  local P = st.players[p]
  for _ = 1, n or 1 do
    local id
    if rule then
      local ok = {}
      for i, x in ipairs(P.deck) do
        local c = card(x)
        if c.cost <= rule.cost and (not rule.unit or c.type == "unit") then ok[#ok + 1] = i end
      end
      if #ok > 0 then id = table.remove(P.deck, ok[R.Random(st, #ok)]) end
    end
    id = id or table.remove(P.deck)
    if not id then
      emit(st, { t = "empty", p = p })
      return
    end
    if #P.hand >= R.HAND_MAX then
      P.grave[#P.grave + 1] = id
      emit(st, { t = "burn", p = p, id = id })
    else
      P.hand[#P.hand + 1] = id
      emit(st, { t = "draw", p = p })
    end
  end
end

-- ---------------------------------------------------------------------------
-- Deaths. Runs until nothing more dies: Fallen effects can kill in turn.
-- ---------------------------------------------------------------------------
function R.Cleanup(st)
  local a, b = order(st)
  for _ = 1, 30 do
    local dying = {}
    for _, p in ipairs({ a, b }) do
      local board = st.players[p].board
      for l = 1, LANES do
        local u = board[l]
        if u and (u.hp <= 0 or u.doomed) then
          if u.kw.sturdy then
            u.kw.sturdy = nil
            u.hp = 1
            u.doomed = nil
            setEvent(st, u, "sturdy")
          else
            dying[#dying + 1] = u
          end
        end
      end
    end
    if #dying == 0 then return end
    for _, u in ipairs(dying) do
      local P = st.players[u.owner]
      P.board[u.lane] = nil
      P.grave[#P.grave + 1] = u.id
      emit(st, { t = "die", p = u.owner, lane = u.lane, id = u.id })
    end
    for _, u in ipairs(dying) do
      local c = card(u.id)
      if c.fallen then
        emit(st, { t = "trigger", p = u.owner, lane = u.lane, id = u.id, kind = "fallen" })
        c.fallen(st, u)
      end
      for _, p in ipairs({ a, b }) do
        local board = st.players[p].board
        for l = 1, LANES do
          local w = board[l]
          if w and w.hp > 0 and not w.doomed then
            local wc = card(w.id)
            if wc.onDeath then wc.onDeath(st, w, u) end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Plans: a list of actions { h = hand index, id = card id, lane = lane }.
-- Units need one of your empty lanes; "enemy" and "friend" tactics need a lane
-- (a friend tactic may target a unit you're playing this round).
-- ---------------------------------------------------------------------------
function R.PlanCost(st, p, plan)
  local hand, cost = st.players[p].hand, 0
  for _, a in ipairs(plan) do
    local id = hand[a.h]
    if id then cost = cost + card(id).cost end
  end
  return cost
end

function R.CheckPlan(st, p, plan)
  local P = st.players[p]
  if type(plan) ~= "table" then return false, "No plan." end
  local cost, usedH, newLane = 0, {}, {}
  for _, a in ipairs(plan) do
    local id = P.hand[a.h]
    if not id or usedH[a.h] or (a.id and a.id ~= id) then return false, "That card isn't in your hand." end
    usedH[a.h] = true
    local c = card(id)
    cost = cost + c.cost
    if c.type == "unit" then
      local l = a.lane
      if type(l) ~= "number" or l < 1 or l > LANES then return false, "Pick a lane for " .. c.name .. "." end
      if P.board[l] or newLane[l] then return false, "That lane is taken." end
      newLane[l] = true
    end
  end
  for _, a in ipairs(plan) do
    local c = card(P.hand[a.h])
    if c.type == "tactic" and c.target ~= "none" then
      local l = a.lane
      if type(l) ~= "number" or l < 1 or l > LANES then return false, c.name .. " needs a target lane." end
      if c.target == "friend" and not (P.board[l] or newLane[l]) then
        return false, c.name .. " needs one of your units."
      end
    end
  end
  if cost > P.supply then return false, "Not enough supply." end
  return true, cost
end

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------
local function pickGuard(eb, l)
  local best
  for _, k in ipairs({ l - 1, l + 1 }) do
    local x = eb[k]
    if x and x.kw.guard and (not best or x.hp > best.hp) then best = x end
  end
  return best
end

local function strikesFor(st, u, hits)
  local atk = R.Attack(st, u)
  if atk <= 0 then return end
  local e = 3 - u.owner
  local eb = st.players[e].board
  local l = u.lane
  local target
  if u.kw.ranged then
    for k = 1, LANES do
      local x = eb[k]
      if x and (not target or x.hp < target.hp) then target = x end
    end
  else
    target = eb[l] or pickGuard(eb, l)
  end
  if target then
    hits[#hits + 1] = { src = u, dst = target, amt = atk }
    if u.kw.pierce and atk > target.hp then
      hits[#hits + 1] = { src = u, mp = e, amt = atk - max(0, target.hp) }
    end
  else
    hits[#hits + 1] = { src = u, mp = e, amt = atk }
  end
  if u.kw.cleave then
    for _, k in ipairs({ l - 1, l + 1 }) do
      local x = eb[k]
      if x and x ~= target then hits[#hits + 1] = { src = u, dst = x, amt = atk } end
    end
  end
end

function R.Combat(st)
  emit(st, { t = "phase", name = "combat" })
  local a, b = order(st)
  for step = 1, 2 do
    local swiftStep = step == 1
    local hits = {}
    for _, p in ipairs({ a, b }) do
      local board = st.players[p].board
      for l = 1, LANES do
        local u = board[l]
        if u and (u.kw.swift and true or false) == swiftStep and not u.frozen then
          strikesFor(st, u, hits)
        end
      end
    end
    if #hits > 0 then
      for _, h in ipairs(hits) do
        emit(st, { t = "strike", p = h.src.owner, lane = h.src.lane,
          tp = h.dst and h.dst.owner or h.mp, tl = h.dst and h.dst.lane or nil, amt = h.amt })
      end
      local drained, unstealthed = { 0, 0 }, {}
      for _, h in ipairs(hits) do
        local src = h.src
        if h.dst then
          R.Damage(st, h.dst, h.amt)
          if src.kw.venom then h.dst.doomed = true end
        else
          R.HitMorale(st, h.mp, h.amt)
        end
        if src.kw.drain then drained[src.owner] = drained[src.owner] + h.amt end
        if src.kw.stealth then
          src.kw.stealth = nil
          unstealthed[#unstealthed + 1] = src
        end
      end
      for p = 1, 2 do
        if drained[p] > 0 then R.RestoreMorale(st, p, drained[p]) end
      end
      for _, u in ipairs(unstealthed) do setEvent(st, u, "reveal") end
      emit(st, { t = "beat" })
      R.Cleanup(st)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Rounds
-- ---------------------------------------------------------------------------
function R.EndRound(st)
  for p = 1, 2 do
    local board = st.players[p].board
    for l = 1, LANES do
      local u = board[l]
      if u then
        local changed = false
        if u.kw.regen and u.hp < u.maxHp then u.hp = u.maxHp; changed = true end
        if (u.tmpAtk or 0) ~= 0 then u.tmpAtk = 0; changed = true end
        if u.frozen then u.frozen = nil; changed = true end
        u.new = nil
        if changed then setEvent(st, u, "endround") end
      end
    end
  end
  local m1, m2 = st.players[1].morale, st.players[2].morale
  if m1 <= 0 or m2 <= 0 or st.round >= R.MAX_ROUNDS then
    if m1 == m2 then -- tiebreak: more units on the board
      m1, m2 = #R.Units(st, 1), #R.Units(st, 2)
      st.tiebreak = true
    end
    st.winner = (m1 > m2) and 1 or (m2 > m1) and 2 or 0
    emit(st, { t = "over", winner = st.winner, tiebreak = st.tiebreak })
  end
end

function R.StartRound(st)
  st.round = st.round + 1
  st.init = (st.round % 2 == 1) and st.first or (3 - st.first)
  emit(st, { t = "round", n = st.round, init = st.init })
  for p = 1, 2 do
    local P = st.players[p]
    P.supply = min(st.round, R.SUPPLY_CAP)
    R.Draw(st, p, 1, R.GUIDED_DRAWS[st.round])
  end
  local a, b = order(st)
  local list = {}
  for _, p in ipairs({ a, b }) do
    for _, u in ipairs(R.Units(st, p)) do list[#list + 1] = u end
  end
  for _, u in ipairs(list) do
    local c = card(u.id)
    if c.roundStart and st.players[u.owner].board[u.lane] == u then c.roundStart(st, u) end
  end
  R.Cleanup(st)
end

-- opts: seed, decks = { {ids}, {ids} }, names = { a, b }, first = 1|2 (optional)
function R.NewGame(o)
  local st = { v = 1, round = 0, rng = R.Seed(o.seed), uid = 0, players = {} }
  for p = 1, 2 do
    local deck = {}
    for i, id in ipairs(o.decks[p]) do card(id); deck[i] = id end
    st.players[p] = {
      name = o.names and o.names[p] or ("Player " .. p),
      morale = R.START_MORALE, deck = deck, hand = {}, grave = {}, board = {}, supply = 0,
    }
    shuffle(st, deck)
  end
  st.first = o.first or R.Random(st, 2)
  for p = 1, 2 do R.Draw(st, p, R.OPENING_HAND) end
  R.StartRound(st)
  return st
end

-- Play one round. plans = { plan1, plan2 }. opts.noAdvance stops before the
-- next round starts (the AI evaluates the board right after combat).
function R.Resolve(st, plans, opts)
  if st.winner then error("Deckhand: the game is over", 2) end
  for p = 1, 2 do
    local ok, err = R.CheckPlan(st, p, plans[p] or {})
    if not ok then error("Deckhand: bad plan for player " .. p .. ": " .. tostring(err), 2) end
  end
  local a, b = order(st)

  -- take the played cards out of the hands
  local played = { {}, {} }
  for p = 1, 2 do
    local P = st.players[p]
    local hs = {}
    for i, act in ipairs(plans[p] or {}) do
      played[p][i] = { id = P.hand[act.h], lane = act.lane }
      hs[#hs + 1] = act.h
    end
    table.sort(hs, function(x, y) return x > y end)
    for _, h in ipairs(hs) do table.remove(P.hand, h) end
  end
  emit(st, { t = "phase", name = "reveal" })

  -- 1. units appear together, then Arrive effects (initiative first, by lane)
  local arrivals = {}
  for _, p in ipairs({ a, b }) do
    local units = {}
    for _, act in ipairs(played[p]) do
      if card(act.id).type == "unit" then units[#units + 1] = act end
    end
    table.sort(units, function(x, y) return x.lane < y.lane end)
    for _, act in ipairs(units) do
      local u = newUnit(st, p, act.id, act.lane)
      st.players[p].board[act.lane] = u
      emit(st, { t = "place", p = p, lane = act.lane, unit = R.Snapshot(u) })
      arrivals[#arrivals + 1] = u
    end
  end
  if #arrivals > 0 then emit(st, { t = "beat" }) end
  for _, u in ipairs(arrivals) do
    local c = card(u.id)
    if c.arrive and st.players[u.owner].board[u.lane] == u then
      emit(st, { t = "trigger", p = u.owner, lane = u.lane, id = u.id, kind = "arrive" })
      c.arrive(st, u)
      R.Cleanup(st)
      emit(st, { t = "beat" })
    end
  end

  -- 2. tactics, initiative first, in the order they were planned
  for _, p in ipairs({ a, b }) do
    for _, act in ipairs(played[p]) do
      local c = card(act.id)
      if c.type == "tactic" then
        emit(st, { t = "tactic", p = p, id = act.id, lane = act.lane })
        c.play(st, p, act.lane)
        st.players[p].grave[#st.players[p].grave + 1] = act.id
        R.Cleanup(st)
        emit(st, { t = "beat" })
      end
    end
  end

  -- 3. combat, 4. end of round
  R.Combat(st)
  R.EndRound(st)
  if not st.winner and not (opts and opts.noAdvance) then R.StartRound(st) end
end
