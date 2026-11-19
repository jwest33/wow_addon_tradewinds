-- The computer opponent. It builds random legal plans, plays each one out on a
-- copy of the game (the opponent's side doing nothing new), scores the board
-- after combat and keeps the best. It never looks at the other player's hand
-- or plan. Difficulty sets how many plans it tries, how much noise it adds,
-- and whether it also checks each plan against the opponent blocking.
local _, ns = ...
local R = ns.Rules

local AI = {}
ns.AI = AI

AI.LEVELS = {
  easy = { samples = 6, pickTop = 0.6, noise = 10, block = false },
  normal = { samples = 60, pickTop = 0, noise = 0.5, block = false },
  hard = { samples = 140, pickTop = 0, noise = 0, block = true },
}

local KW_VALUE = {
  swift = 1, guard = 1, ranged = 1, pierce = 1, cleave = 1.5, venom = 1.5,
  drain = 1, sturdy = 1, regen = 1, rally = 1, stealth = 0.3,
}

local function unitValue(st, u)
  local v = R.Attack(st, u) * 1.1 + math.max(0, u.hp) * 0.8 + 0.5
  for k in pairs(u.kw) do v = v + (KW_VALUE[k] or 0) end
  return v
end

-- Score of the position for player p (higher is better).
function AI.Evaluate(st, p)
  if st.winner then
    if st.winner == p then return 10000 elseif st.winner == 0 then return 0 end
    return -10000
  end
  local me, op = st.players[p], st.players[3 - p]
  local left = R.MAX_ROUNDS - st.round
  local wMorale = 2 + (R.MAX_ROUNDS - left) * 0.25
  local wBoard = 0.4 + 0.6 * math.min(1, left / 4)
  local s = (me.morale - op.morale) * wMorale
  local bv = 0
  for l = 1, R.LANES do
    local u = me.board[l]
    if u then bv = bv + unitValue(st, u) end
    local x = op.board[l]
    if x then bv = bv - unitValue(st, x) end
  end
  s = s + bv * wBoard
  s = s + (#me.hand - #op.hand) * 0.7 * math.min(1, left / 3)
  return s
end

-- A random legal plan. Each affordable card is played with 85% chance, in a
-- random order, into a random free lane / at a sensible random target.
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
    if P.board[l] then own[#own + 1] = l else free[#free + 1] = l end
    if R.Targetable(E.board[l], p) then foes[#foes + 1] = l end
  end
  local plan = {}
  for _, h in ipairs(idx) do
    local id = P.hand[h]
    local c = R.Card(id)
    if c.cost <= supply and rnd(100) > 15 then
      local lane, ok = nil, false
      if c.type == "unit" then
        if #free > 0 then
          lane = table.remove(free, rnd(#free))
          own[#own + 1] = lane
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

local function planKey(plan)
  local parts = {}
  for i, a in ipairs(plan) do parts[i] = a.h .. ":" .. tostring(a.lane) end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- "What if they block my best attacker?": a stand-in enemy unit, sized to
-- the opponent's supply, in the empty enemy lane across from p's strongest
-- attacker (existing or about to be played).
local function addBlocker(c, p, plan)
  local P, eb = c.players[p], c.players[3 - p].board
  local atk = {}
  for l = 1, R.LANES do
    if P.board[l] then atk[l] = R.Attack(c, P.board[l]) end
  end
  for _, a in ipairs(plan) do
    local cd = R.Card(P.hand[a.h])
    if cd.type == "unit" then atk[a.lane] = cd.atk end
  end
  local best
  for l = 1, R.LANES do
    if atk[l] and not eb[l] and (not best or atk[l] > atk[best]) then best = l end
  end
  if not best then return end
  local s = c.players[3 - p].supply
  local g = R.Summon(c, 3 - p, best, "ghost")
  g.atk = math.max(1, math.floor(s * 0.7 + 0.5))
  g.hp, g.maxHp = s + 1, s + 1
end

local function simulate(st, p, plan, rnd, block)
  local c = R.Clone(st)
  c.rng = R.Seed(rnd(2147483646)) -- don't let the AI foresee random effects
  local plans = { {}, {} }
  plans[p] = plan
  if block then addBlocker(c, p, plan) end
  R.Resolve(c, plans, { noAdvance = true })
  return AI.Evaluate(c, p)
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
        if not P.board[l] then out[#out + 1] = { { h = h, id = id, lane = l } } end
      end
    end
  end
  return out
end
AI.OpeningPlans = openingPlans

-- Returns plan, score. rnd(n) -> 1..n (defaults to math.random).
-- opts.yield: called every few simulations (the UI uses it to spread the work
-- over several frames).
--
-- Noise and pickTop make the easy level play loosely, but no level picks a
-- plan it scores below doing nothing (a Healing Potion at full Morale, a
-- Battle Shout with no units): the noise only chooses among the sensible ones.
function AI.ChoosePlan(st, p, level, rnd, opts)
  rnd = rnd or math.random
  local L = AI.LEVELS[level] or AI.LEVELS.normal
  local seen, cands, n = {}, {}, 0
  local function consider(plan)
    local key = planKey(plan)
    if seen[key] then return end
    seen[key] = true
    local base = simulate(st, p, plan, rnd, false)
    if L.block then base = (base + simulate(st, p, plan, rnd, true)) / 2 end
    local score = base
    if L.noise > 0 then score = score + (rnd(1000) / 1000 - 0.5) * L.noise end
    cands[#cands + 1] = { plan = plan, score = score, base = base }
    n = n + 1
    if opts and opts.yield and n % 10 == 0 then opts.yield() end
  end
  local opening = st.round == 1 and openingPlans(st, p) or {}
  if #opening > 0 then
    for _, plan in ipairs(opening) do consider(plan) end
  else
    consider({})
    for _ = 1, L.samples do consider(AI.RandomPlan(st, p, rnd)) end
    local pass = cands[1].base
    local keep = {}
    for i, cd in ipairs(cands) do
      if i == 1 or cd.base >= pass then keep[#keep + 1] = cd end
    end
    cands = keep
  end
  table.sort(cands, function(a, b) return a.score > b.score end)
  local pick = 1
  if L.pickTop > 0 then pick = rnd(math.max(1, math.floor(#cands * L.pickTop))) end
  return cands[pick].plan, cands[pick].score
end
