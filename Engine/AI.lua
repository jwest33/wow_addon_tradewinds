-- The computer opponent.
--
-- Each round it lists the plans it could play (every legal one when there
-- aren't too many, otherwise a random sample), plays each one out on a copy of
-- the game and scores the board after combat. Higher levels also test every
-- plan against a few made-up replies: plays the other player could make with
-- their Supply and number of cards, drawn from a pool of ordinary cards. It
-- never looks at the other player's hand or plan, and plans from R.Redact's
-- copy of the game, so it knows how many traps you have set but not where.
--
-- Opponents have a style (Data/Opponents.lua): how much they care about
-- hitting your Morale, keeping their own, and holding the board.
local _, ns = ...
local R = ns.Rules

local AI = {}
ns.AI = AI

local min, max = math.min, math.max

-- samples   random plans tried
-- search    list every plan instead, when there are at most this many
-- replies   made-up replies each plan is tested against (none: it assumes
--           you add nothing)
-- quiet     the weight of "you add nothing" against each reply
-- pickTop, noise   how loosely it chooses (easy)
--
-- Measured with tests/balance.lua (random decks, 600 games): listing every
-- plan without replies loses to random sampling (it plays too exactly to
-- "you add nothing"); the replies are what make it stronger.
AI.LEVELS = {
  easy = { samples = 6, pickTop = 0.6, noise = 10 },
  normal = { samples = 60, noise = 0.5 },
  hard = { samples = 100, replies = 2 },
  heroic = { samples = 200, search = 300, replies = 6 },
}
AI.LEVEL_ORDER = { "easy", "normal", "hard", "heroic" }

local KW_VALUE = {
  swift = 1, guard = 1, ranged = 1, pierce = 1, cleave = 1.5, venom = 1.5,
  drain = 1, sturdy = 1, regen = 1, rally = 1, stealth = 0.3,
}

local function unitValue(st, u)
  local v = R.Attack(st, u) * 1.1 + max(0, u.hp) * 0.8 + 0.5
  for k in pairs(u.kw) do v = v + (KW_VALUE[k] or 0) end
  return v
end

-- A trap that's set and hasn't sprung yet, for each Supply it cost (so
-- setting one doesn't look like wasted Supply). One that springs this round
-- shows its worth in the simulation itself.
AI.TRAP_VALUE = 0.8

local function trapValue(P)
  local v = 0
  for l = 1, R.LANES do
    local t = P.traps and P.traps[l]
    if t then v = v + R.Card(t.id).cost * AI.TRAP_VALUE end
  end
  return v
end

local NEUTRAL = {}

-- Score of the position for player p (higher is better). how (optional):
-- the opponent's style, aggro, guard and board (weights, 1 = neutral).
function AI.Evaluate(st, p, how)
  if st.winner then
    if st.winner == p then return 10000 elseif st.winner == 0 then return 0 end
    return -10000
  end
  how = how or NEUTRAL
  local me, op = st.players[p], st.players[3 - p]
  local left = R.MAX_ROUNDS - st.round
  local wMorale = 2 + (R.MAX_ROUNDS - left) * 0.25
  local wBoard = (0.4 + 0.6 * min(1, left / 4)) * (how.board or 1)
  local s = me.morale * wMorale * (how.guard or 1) - op.morale * wMorale * (how.aggro or 1)
  local bv = 0
  for l = 1, R.LANES do
    local u = me.board[l]
    if u then bv = bv + unitValue(st, u) end
    local x = op.board[l]
    if x then bv = bv - unitValue(st, x) end
  end
  bv = bv + trapValue(me) - trapValue(op)
  s = s + bv * wBoard
  -- cards in hand: options for later rounds (valuing them by cost instead
  -- was tried and won no more games)
  s = s + (#me.hand - #op.hand) * 0.7 * min(1, left / 3)
  return s
end

-- A random legal plan. Each affordable card is played with 85% chance, in a
-- random order, into a random free lane / at a sensible random target. A
-- trap goes in a free lane, as a unit does.
function AI.RandomPlan(st, p, rnd)
  local P, E = st.players[p], st.players[3 - p]
  local supply = P.supply
  local idx = {}
  for i = 1, #P.hand do idx[i] = i end
  for i = #idx, 2, -1 do
    local j = rnd(i)
    idx[i], idx[j] = idx[j], idx[i]
  end
  local free, own, foes = {}, {}, {}
  for l = 1, R.LANES do
    if P.board[l] then own[#own + 1] = l elseif not R.TrapAt(st, p, l) then free[#free + 1] = l end
    if R.Targetable(E.board[l], p) then foes[#foes + 1] = l end
  end
  local plan = {}
  for _, h in ipairs(idx) do
    local id = P.hand[h]
    local c = R.Card(id)
    if c.cost <= supply and rnd(100) > 15 then
      local lane, ok = nil, false
      if c.type == "unit" or c.type == "trap" then
        if #free > 0 then
          lane = table.remove(free, rnd(#free))
          if c.type == "unit" then own[#own + 1] = lane end
          ok = true
        end
      elseif c.target == "enemy" then
        if #foes > 0 and rnd(10) > 2 then lane = foes[rnd(#foes)] else lane = rnd(R.LANES) end
        ok = true
      elseif c.target == "friend" then
        if #own > 0 then lane = own[rnd(#own)]; ok = true end
      else
        ok = true
      end
      if ok then
        plan[#plan + 1] = { h = h, id = id, lane = lane }
        supply = supply - c.cost
      end
    end
  end
  return plan
end

-- Two plans that play the same cards in the same lanes are the same plan,
-- whichever copy of a card they use.
local function planKey(plan)
  local parts = {}
  for i, a in ipairs(plan) do parts[i] = tostring(a.id) .. ":" .. tostring(a.lane) end
  table.sort(parts)
  return table.concat(parts, ",")
end
AI.PlanKey = planKey

-- Every legal plan, or nil when there are more than `limit`. Units come
-- before tactics so a friendly tactic can target a unit played this round.
-- Enemy tactics are aimed at lanes where they can hit something (a unit they
-- can target, or one next to it) and at one empty lane (Fireball's Morale hit).
function AI.AllPlans(st, p, limit)
  local P, E = st.players[p], st.players[3 - p]
  local function inLane(id)
    local t = R.Card(id).type
    return t == "unit" or t == "trap"
  end
  local order = {}
  for h, id in ipairs(P.hand) do
    if inLane(id) then order[#order + 1] = h end
  end
  for h, id in ipairs(P.hand) do
    if not inLane(id) then order[#order + 1] = h end
  end
  local enemyLanes, emptyAdded = {}, false
  for l = 1, R.LANES do
    local here = R.Targetable(E.board[l], p)
    local near = R.Targetable(E.board[l - 1], p) or R.Targetable(E.board[l + 1], p)
    if here or near then
      enemyLanes[#enemyLanes + 1] = l
    elseif not E.board[l] and not emptyAdded then
      enemyLanes[#enemyLanes + 1] = l
      emptyAdded = true
    end
  end
  -- taken: lanes a planned unit or trap goes in; placed: the units only
  local out, seen, plan, taken, placed = {}, {}, {}, {}, {}
  local leaves, maxLeaves = 0, limit * 8
  local function leaf()
    leaves = leaves + 1
    if leaves > maxLeaves then return false end
    local key = planKey(plan)
    if seen[key] then return true end
    seen[key] = true
    if #out >= limit then return false end
    local copy = {}
    for i, a in ipairs(plan) do copy[i] = { h = a.h, id = a.id, lane = a.lane } end
    out[#out + 1] = copy
    return true
  end
  local function rec(i, left)
    if i > #order then return leaf() end
    if not rec(i + 1, left) then return false end -- without this card
    local h = order[i]
    local id = P.hand[h]
    local c = R.Card(id)
    if c.cost > left then return true end
    local lanes
    local lane = c.type == "unit" or c.type == "trap"
    if lane then
      lanes = {}
      for l = 1, R.LANES do
        if not P.board[l] and not taken[l] and not R.TrapAt(st, p, l) then lanes[#lanes + 1] = l end
      end
    elseif c.target == "enemy" then
      lanes = enemyLanes
    elseif c.target == "friend" then
      lanes = {}
      for l = 1, R.LANES do
        if P.board[l] or placed[l] then lanes[#lanes + 1] = l end
      end
    else
      lanes = { false }
    end
    for _, l in ipairs(lanes) do
      plan[#plan + 1] = { h = h, id = id, lane = l or nil }
      if lane then taken[l] = true end
      if c.type == "unit" then placed[l] = true end
      local ok = rec(i + 1, left - c.cost)
      if lane then taken[l] = nil end
      if c.type == "unit" then placed[l] = nil end
      plan[#plan] = nil
      if not ok then return false end
    end
    return true
  end
  if not rec(1, P.supply) then return nil end
  return out
end

-- The made-up replies are built from these: ordinary units by cost, and
-- Fireball as the stand-in for removal.
AI.GENERIC = {
  { "kobold", "murloc" },
  { "thug", "gnoll" },
  { "grunt", "croc" },
  { "patchwork", "crusader" },
  { "brave" },
  { "brave" },
}
AI.GENERIC_TACTIC = "fireball"

-- Something player q might play this round, judged only from what anyone at
-- the table can see: their Supply, how many cards they hold, their empty lanes
-- and p's units.
function AI.SampleReply(st, q, rnd)
  local Q, P = st.players[q], st.players[3 - q]
  local supply, cards = Q.supply, #Q.hand
  local free = R.EmptyLanes(st, q)
  local reply = {}
  local tcost = R.Card(AI.GENERIC_TACTIC).cost
  while #reply < cards and supply > 0 do
    if rnd(100) > 85 then break end -- sometimes they keep cards back
    local played = false
    if supply >= tcost and rnd(100) <= 20 then
      local targets = {}
      for l = 1, R.LANES do
        if R.Targetable(P.board[l], q) then targets[#targets + 1] = l end
      end
      if #targets > 0 then
        reply[#reply + 1] = { h = #reply + 1, id = AI.GENERIC_TACTIC, lane = targets[rnd(#targets)] }
        supply = supply - tcost
        played = true
      end
    end
    if not played then
      if #free == 0 then break end
      local cost = min(supply, #AI.GENERIC)
      if cost > 1 and rnd(100) <= 40 then cost = rnd(cost) end -- not always the biggest
      local pool = AI.GENERIC[cost]
      reply[#reply + 1] = { h = #reply + 1, id = pool[rnd(#pool)], lane = table.remove(free, rnd(#free)) }
      supply = supply - cost
    end
  end
  return reply
end

-- Plays `plan` out on a copy of the game (st: what p may know of it, see
-- R.Redact). scen.seed: the copy's random numbers (so the AI can't foresee
-- the real ones); scen.reply: the other side's made-up play, if any. Their
-- real hand is swapped for that reply plus blank cards, so only its size
-- carries over.
local function simulate(st, p, plan, scen, how)
  local c = R.Clone(st)
  c.rng = scen.seed
  local plans = { {}, {} }
  plans[p] = plan
  local q = 3 - p
  local Q = c.players[q]
  local hand = {}
  local reply = scen.reply
  if reply then
    for i, a in ipairs(reply) do hand[i] = a.id end
    plans[q] = reply
  end
  for i = #hand + 1, #Q.hand do hand[i] = "ghost" end
  Q.hand = hand
  R.Resolve(c, plans, { noAdvance = true })
  return AI.Evaluate(c, p, how)
end

-- Round 1's plans: one unit the AI can afford, in each free lane. Every deck
-- has units costing 1 and round 1's draw is one of them (Rules.GUIDED_DRAWS),
-- so there is nearly always one. Tactics are never played in round 1: Morale
-- is full and the board is empty, so they would be wasted.
local function openingPlans(st, p)
  local P = st.players[p]
  local out = {}
  for h, id in ipairs(P.hand) do
    local c = R.Card(id)
    if c.type == "unit" and c.cost <= P.supply then
      for l = 1, R.LANES do
        if not P.board[l] and not R.TrapAt(st, p, l) then out[#out + 1] = { { h = h, id = id, lane = l } } end
      end
    end
  end
  return out
end
AI.OpeningPlans = openingPlans

-- Returns plan, score. rnd(n) -> 1..n (defaults to math.random).
-- opts (optional):
--   style   the opponent's weights { aggro, guard, board } (Data/Opponents.lua)
--   yield   called after every simulation (the UI uses it to spread the work
--           over several frames)
--
-- Noise and pickTop make the easy level play loosely, but no level picks a
-- plan it scores below doing nothing (a Healing Potion at full Morale, a
-- Battle Shout with no units): the noise only chooses among the sensible ones.
function AI.ChoosePlan(st, p, level, rnd, opts)
  rnd = rnd or math.random
  opts = opts or {}
  local L = AI.LEVELS[level] or AI.LEVELS.normal
  local style = opts.style or NEUTRAL
  local how = style
  -- everything below works on what p may know: your traps are a count
  st = R.Redact(st, p)
  -- Every plan meets the same random numbers and the same replies, so they
  -- are compared on equal terms.
  -- quiet: the weight of "they add nothing" against each made-up reply.
  local scens = { { seed = R.Seed(rnd(2147483646)), w = L.quiet or 1 } }
  local wsum = scens[1].w
  for _ = 1, L.replies or 0 do
    scens[#scens + 1] = { seed = R.Seed(rnd(2147483646)), reply = AI.SampleReply(st, 3 - p, rnd), w = 1 }
    wsum = wsum + 1
  end
  local seen, cands = {}, {}
  local function consider(plan)
    local key = planKey(plan)
    if seen[key] then return end
    seen[key] = true
    local total = 0
    for _, scen in ipairs(scens) do
      if scen.w > 0 then
        total = total + simulate(st, p, plan, scen, how) * scen.w
        if opts.yield then opts.yield() end
      end
    end
    local base = total / wsum
    local score = base
    if (L.noise or 0) > 0 then score = score + (rnd(1000) / 1000 - 0.5) * L.noise end
    cands[#cands + 1] = { plan = plan, score = score, base = base }
  end
  local opening = st.round == 1 and openingPlans(st, p) or {}
  if #opening > 0 then
    for _, plan in ipairs(opening) do consider(plan) end
  else
    consider({})
    local all = (L.search or 0) > 0 and AI.AllPlans(st, p, L.search) or nil
    if all then
      for _, plan in ipairs(all) do consider(plan) end
    else
      for _ = 1, L.samples do consider(AI.RandomPlan(st, p, rnd)) end
    end
    local pass = cands[1].base
    local keep = {}
    for i, cd in ipairs(cands) do
      if i == 1 or cd.base >= pass then keep[#keep + 1] = cd end
    end
    cands = keep
  end
  table.sort(cands, function(a, b) return a.score > b.score end)
  local pick = 1
  if (L.pickTop or 0) > 0 then pick = rnd(max(1, math.floor(#cands * L.pickTop))) end
  return cands[pick].plan, cands[pick].score
end
