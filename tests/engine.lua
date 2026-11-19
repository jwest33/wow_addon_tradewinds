-- Engine tests: rules, cards, AI, collection. Pure Lua, no WoW mock needed.
-- Run with tests/run_tests.py.
local ROOT = ROOT or "."

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

-- load the engine files listed in the .toc (everything that isn't UI/Core)
local ns = {}
local ENGINE = { ["Engine/Rules.lua"] = true, ["Engine/Cards.lua"] = true, ["Engine/AI.lua"] = true,
  ["Data/Opponents.lua"] = true, ["Collection.lua"] = true }
for line in io.lines(ROOT .. "/Deckhand.toc") do
  local file = line:match("^%s*([^#].-%.lua)%s*$")
  if file then
    file = file:gsub("\\", "/")
    if ENGINE[file] then assert(loadfile(ROOT .. "/" .. file))("Deckhand", ns) end
  end
end
local R, Cards, AI, C = ns.Rules, ns.Cards, ns.AI, ns.Collection
local M = R.START_MORALE
assert(R and Cards and AI and C, "engine files missing from the .toc")

local function filler(n)
  local d = {}
  for i = 1, n or 20 do d[i] = "kobold" end
  return d
end

-- A game with empty hands and boards, round 1 started, player 1 has initiative.
local function blank(opts)
  opts = opts or {}
  local st = R.NewGame({ seed = opts.seed or 7, decks = { filler(), filler() }, first = 1 })
  for p = 1, 2 do
    st.players[p].hand = {}
    st.players[p].board = {}
    st.players[p].supply = 6
  end
  return st
end

local function put(st, p, lane, id)
  local u = R.Summon(st, p, lane, id)
  u.new = nil
  return u
end

local function combatOnly(st)
  R.Combat(st)
  R.EndRound(st)
end

-- 1. card data ------------------------------------------------------------------
do
  local ids = {}
  for _, c in ipairs(Cards.list) do
    check(not ids[c.id], "unique id " .. c.id)
    ids[c.id] = true
    check(type(c.name) == "string" and c.cost and c.cost >= 0 and c.cost <= 6, c.id .. " name/cost")
    check(Cards.RARITY_RANK[c.rarity], c.id .. " rarity")
    check(type(c.icon) == "table" and #c.icon >= 1, c.id .. " icon")
    if c.type == "unit" then
      check(type(c.atk) == "number" and type(c.hp) == "number" and c.hp > 0, c.id .. " stats")
    else
      check(c.type == "tactic" and type(c.play) == "function", c.id .. " tactic play")
      check(c.target == "enemy" or c.target == "friend" or c.target == "none", c.id .. " target")
    end
    for k in pairs(c.kw) do check(R.KEYWORD[k], c.id .. " keyword " .. k) end
  end
  local per = {}
  for _, c in ipairs(Cards.collectible) do per[c.rarity] = (per[c.rarity] or 0) + 1 end
  print(("cards: %d collectible (C %d, U %d, R %d, E %d, L %d)"):format(#Cards.collectible,
    per.common or 0, per.uncommon or 0, per.rare or 0, per.epic or 0, per.legendary or 0))
  for _, r in ipairs(Cards.RARITIES) do check((per[r] or 0) > 0, "cards of rarity " .. r) end

  local function validDeck(d, label)
    check(#d == 20, label .. " has 20 cards (" .. #d .. ")")
    local n = {}
    for _, id in ipairs(d) do
      local c = Cards.byId[id]
      check(c and c.collectible, label .. " card " .. tostring(id))
      n[id] = (n[id] or 0) + 1
    end
    for id, k in pairs(n) do check(k <= C.MaxCopies(id), label .. " copies of " .. id) end
    local ok, why = C.CheckCurve(d)
    check(ok, label .. " curve: " .. tostring(why))
  end
  validDeck(C.STARTER, "starter deck")
  for _, o in ipairs(ns.Opponents) do validDeck(o.deck, o.name) end
end

-- 2. rules -----------------------------------------------------------------------
do -- unblocked units hit Morale, blocked ones trade
  local st = blank()
  put(st, 1, 1, "grunt")            -- 3/4, lane 1 open
  put(st, 1, 2, "thug")             -- 2/3 vs gnoll 3/2
  put(st, 2, 2, "gnoll")
  combatOnly(st)
  check(st.players[2].morale == M - 3, "unblocked grunt deals 3 to Morale")
  check(st.players[2].board[2] == nil, "thug kills gnoll")
  check(st.players[1].board[2] == nil, "gnoll kills thug")
end

do -- Swift: kills first, no strike back
  local st = blank()
  put(st, 1, 1, "raptor")           -- 3/2 swift
  put(st, 2, 1, "gnoll")            -- 3/2
  combatOnly(st)
  check(st.players[2].board[1] == nil and st.players[1].board[1] and st.players[1].board[1].hp == 2, "swift kills before strike back")
end

do -- Guard takes hits from the neighbouring open lane
  local st = blank()
  put(st, 1, 1, "grunt")            -- lane 1 open on p2's side
  put(st, 2, 2, "mountaineer")      -- 1/4 guard
  combatOnly(st)
  check(st.players[2].morale == M, "guard protects Morale")
  check(st.players[2].board[2].hp == 1, "guard took the hit")
end

do -- Ranged picks the weakest enemy unit
  local st = blank()
  put(st, 1, 1, "axe")              -- 2/3 ranged
  put(st, 2, 3, "croc")             -- 2/5
  put(st, 2, 4, "murloc")           -- 2/1
  combatOnly(st)
  check(st.players[2].board[4] == nil, "ranged kills the weakest")
  check(st.players[2].morale == M, "ranged doesn't hit Morale while enemies exist")
end

do -- Pierce
  local st = blank()
  put(st, 1, 1, "ragnaros")         -- 6/6 cleave pierce
  put(st, 2, 1, "kobold")           -- 1/2
  combatOnly(st)
  check(st.players[2].morale == M - 4, "pierce carries 4 to Morale (" .. st.players[2].morale .. ")")
end

do -- Cleave
  local st = blank()
  put(st, 1, 2, "ogre")             -- 4/5 cleave
  put(st, 2, 1, "thug"); put(st, 2, 2, "thug"); put(st, 2, 3, "thug")
  combatOnly(st)
  check(not st.players[2].board[1] and not st.players[2].board[2] and not st.players[2].board[3], "cleave hits three lanes")
end

do -- Venom
  local st = blank()
  put(st, 1, 1, "spider")           -- 1/3 venom
  put(st, 2, 1, "kodo")             -- 3/8
  combatOnly(st)
  check(st.players[2].board[1] == nil, "venom destroys the kodo")
end

do -- Drain, capped at max Morale
  local st = blank()
  st.players[1].morale = M - 4
  put(st, 1, 1, "bat")              -- 2/2 drain, open lane
  combatOnly(st)
  check(st.players[1].morale == M - 2 and st.players[2].morale == M - 2, "drain restores Morale")
  local st2 = blank()
  put(st2, 1, 1, "bat")
  combatOnly(st2)
  check(st2.players[1].morale == M, "drain capped at the starting Morale")
end

do -- Sturdy survives once
  local st = blank()
  local g = put(st, 1, 1, "ghoul")  -- 2/2 sturdy
  put(st, 2, 1, "grunt")
  combatOnly(st)
  check(st.players[1].board[1] and st.players[1].board[1].hp == 1 and not st.players[1].board[1].kw.sturdy, "sturdy survives at 1")
  R.Combat(st)
  check(st.players[1].board[1] == nil, "sturdy only once")
end

do -- Regenerate
  local st = blank()
  put(st, 1, 1, "troll")            -- 3/3 regen
  put(st, 2, 1, "thug")             -- 2/3
  combatOnly(st)
  check(st.players[1].board[1].hp == 3, "regenerate heals at end of round")
end

do -- Rally
  local st = blank()
  put(st, 1, 2, "crusader")         -- rally
  local k = put(st, 1, 1, "kobold")
  check(R.Attack(st, k) == 2, "rally gives +1 to neighbours")
  local k3 = put(st, 1, 4, "kobold")
  check(R.Attack(st, k3) == 1, "rally doesn't reach two lanes away")
end

do -- Stealth blocks enemy tactics, ends after striking
  local st = blank()
  put(st, 2, 1, "vancleef")
  st.players[1].hand = { "evisc" }
  st.players[1].supply = 2
  R.Resolve(st, { { { h = 1, lane = 1 } }, {} }, { noAdvance = true })
  check(st.players[2].board[1] and st.players[2].board[1].hp == 3, "stealth dodges eviscerate")
  check(not st.players[2].board[1].kw.stealth, "stealth gone after striking")
end

do -- Fireball on an empty lane hits Morale
  local st = blank()
  st.players[1].hand = { "fireball" }
  R.Resolve(st, { { { h = 1, lane = 3 } }, {} }, { noAdvance = true })
  check(st.players[2].morale == M - 2, "fireball empty lane -> 2 Morale")
end

do -- Tactics land after the reveal: fireball hits a unit played the same round
  local st = blank()
  st.players[1].hand = { "fireball" }
  st.players[2].hand = { "gnoll" }
  R.Resolve(st, { { { h = 1, lane = 2 } }, { { h = 1, lane = 2 } } }, { noAdvance = true })
  check(st.players[2].board[2] == nil and st.players[2].morale == M, "fireball hits the newly revealed gnoll")
end

do -- Polymorph, Frost Nova, Hogger, Onyxia, Vulture
  local st = blank()
  put(st, 2, 1, "ragnaros")
  st.players[1].hand = { "poly" }
  R.Resolve(st, { { { h = 1, lane = 1 } }, {} }, { noAdvance = true })
  check(st.players[2].board[1] and st.players[2].board[1].id == "sheep", "polymorph makes a sheep")

  st = blank()
  put(st, 2, 1, "grunt"); put(st, 2, 2, "grunt")
  st.players[1].hand = { "nova" }
  R.Resolve(st, { { { h = 1 } }, {} }, { noAdvance = true })
  check(st.players[1].morale == M, "frozen units don't strike")
  check(not st.players[2].board[1].frozen, "freeze ends with the round")

  st = blank()
  st.players[1].hand = { "hogger" }
  R.Resolve(st, { { { h = 1, lane = 2 } }, {} }, { noAdvance = true })
  local b = st.players[1].board
  check(b[1] and b[1].id == "runt" and b[3] and b[3].id == "runt", "hogger summons runts")

  st = blank()
  put(st, 2, 1, "thug"); put(st, 2, 3, "kobold")
  local v = put(st, 2, 4, "vulture")
  st.players[1].hand = { "onyxia" }
  R.Resolve(st, { { { h = 1, lane = 2 } }, {} }, { noAdvance = true })
  check(st.players[2].board[3] == nil, "onyxia's breath kills the kobold")
  check(st.players[2].board[4] == nil or st.players[2].board[4].atk > 1, "vulture grew or died")
end

do -- Fallen effects
  local st = blank()
  put(st, 1, 1, "demo")             -- 2/2, fallen: 3 to the unit across
  put(st, 2, 1, "croc")             -- 2/5
  combatOnly(st)
  check(st.players[2].board[1] == nil, "demolitionist + strike kill the croc")
  local st2 = blank()
  st2.players[1].morale = 5
  put(st2, 1, 1, "princess")
  put(st2, 2, 1, "ragnaros")
  combatOnly(st2)
  check(st2.players[1].morale == 8, "princess restores 4 when she dies, after 1 pierce damage (" .. st2.players[1].morale .. ")")
end

do -- plan checks
  local st = blank()
  st.players[1].hand = { "ogre", "grunt", "bandage" }
  st.players[1].supply = 6
  check(not R.CheckPlan(st, 1, { { h = 1, lane = 1 }, { h = 2, lane = 2 } }), "over supply rejected")
  check(R.CheckPlan(st, 1, { { h = 2, lane = 2 }, { h = 3, lane = 2 } }), "friend tactic on a unit played this round")
  check(not R.CheckPlan(st, 1, { { h = 3, lane = 2 } }), "friend tactic needs a unit")
  put(st, 1, 1, "kobold")
  check(not R.CheckPlan(st, 1, { { h = 2, lane = 1 } }), "lane taken rejected")
  check(not R.CheckPlan(st, 1, { { h = 2, lane = 2 }, { h = 2, lane = 3 } }), "same card twice rejected")
end

do -- game end
  local st = blank()
  st.players[2].morale = 2
  put(st, 1, 1, "grunt")
  combatOnly(st)
  check(st.winner == 1, "Morale 0 ends the game")
  local st2 = blank()
  st2.round = R.MAX_ROUNDS
  st2.players[1].morale = 9; st2.players[2].morale = 9
  combatOnly(st2)
  check(st2.winner == 0, "equal Morale and units after round 8 is a draw")
  local st3 = blank()
  st3.round = R.MAX_ROUNDS
  st3.players[1].morale = 9; st3.players[2].morale = 9
  put(st3, 2, 1, "sheep")
  combatOnly(st3)
  check(st3.winner == 2 and st3.tiebreak, "tied Morale: more units on the board wins")
end

do -- guided draws: round 1 a 1-cost unit, round 2 cost <= 2, round 3 cost <= 3
  local bad = { 0, 0, 0 }
  for seed = 1, 600 do
    for _, o in ipairs(ns.Opponents) do
      local st = R.NewGame({ seed = seed, decks = { C.STARTER, o.deck } })
      for p = 1, 2 do
        local ok = false
        for _, id in ipairs(st.players[p].hand) do
          local c = Cards.byId[id]
          if c.type == "unit" and c.cost <= 1 then ok = true end
        end
        if not ok then bad[1] = bad[1] + 1 end
      end
      for r = 2, 3 do
        R.Resolve(st, { {}, {} })
        for p = 1, 2 do
          local hand = st.players[p].hand
          if Cards.byId[hand[#hand]].cost > r then bad[r] = bad[r] + 1 end
        end
      end
    end
  end
  check(bad[1] == 0, "every round-1 hand has a 1-cost unit (" .. bad[1] .. " without)")
  check(bad[2] == 0 and bad[3] == 0, ("round 2/3 draws within supply (%d, %d over)"):format(bad[2], bad[3]))
end

-- 3. determinism ------------------------------------------------------------------
local function serialize(v, out)
  out = out or {}
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "="
      serialize(v[k], out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = tostring(v)
  end
  return out
end
local function sig(st) return table.concat(serialize(st)) end

local function randomDeck(rnd)
  local d, n = {}, {}
  while #d < 20 do
    local c = Cards.collectible[rnd(#Cards.collectible)]
    if (n[c.id] or 0) < C.MaxCopies(c.id) then
      n[c.id] = (n[c.id] or 0) + 1
      d[#d + 1] = c.id
    end
  end
  return d
end

local function lcg(seed)
  local s = R.Seed(seed)
  return function(n)
    s = (s * 48271) % 2147483647
    return (s % n) + 1
  end
end

local function playGame(seed, levels, decks)
  local rnd = lcg(seed)
  decks = decks or { randomDeck(rnd), randomDeck(rnd) }
  local st = R.NewGame({ seed = seed, decks = decks })
  while not st.winner do
    local plans = {}
    for p = 1, 2 do
      if levels[p] == "pass" then plans[p] = {}
      else plans[p] = AI.ChoosePlan(st, p, levels[p], rnd) end
    end
    R.Resolve(st, plans)
  end
  return st
end

do
  local a = playGame(1234, { "normal", "normal" })
  local b = playGame(1234, { "normal", "normal" })
  check(sig(a) == sig(b), "same seed and plans give the same game")
  local c = R.NewGame({ seed = 99, decks = { filler(), filler() } })
  local d = R.Clone(c)
  R.Resolve(c, { {}, {} }); R.Resolve(d, { {}, {} })
  check(sig(c) == sig(d), "a clone plays out the same")
end

-- 4. AI games ---------------------------------------------------------------------
do
  local function series(n, levels, label)
    local wins, draws, rounds, early, errors = { 0, 0 }, 0, 0, 0, 0
    for i = 1, n do
      local ok, st = pcall(playGame, 1000 + i * 7, levels)
      if not ok then
        errors = errors + 1
        if errors <= 3 then print("ERROR in game: " .. tostring(st)) end
      else
        if st.winner == 0 then draws = draws + 1 else wins[st.winner] = wins[st.winner] + 1 end
        rounds = rounds + st.round
        if st.round < R.MAX_ROUNDS then early = early + 1 end
      end
    end
    print(("%-20s %3d games: P1 %3d  P2 %3d  draws %2d | avg %.1f rounds, %d%% ended by Morale"):format(
      label, n, wins[1], wins[2], draws, rounds / n, math.floor(early / n * 100 + 0.5)))
    check(errors == 0, label .. " ran without errors")
    return wins, draws
  end
  local w = series(40, { "normal", "pass" }, "normal vs pass")
  check(w[1] >= 38, "normal AI beats a player who never plays")
  series(200, { "normal", "normal" }, "normal vs normal")
  w = series(100, { "hard", "easy" }, "hard vs easy")
  check(w[1] >= 60, "hard beats easy most of the time")
  w = series(100, { "normal", "easy" }, "normal vs easy")
  check(w[1] >= 55, "normal beats easy more often than not")

  -- AI decks against the starter deck
  for _, o in ipairs(ns.Opponents) do
    local ww, dd, n = 0, 0, 60
    for i = 1, n do
      local st = playGame(5000 + i, { "normal", o.level }, { C.STARTER, o.deck })
      if st.winner == 1 then ww = ww + 1 elseif st.winner == 0 then dd = dd + 1 end
    end
    print(("starter deck (normal play) vs %-22s (%s): wins %d%%, draws %d%%"):format(o.name, o.level,
      math.floor(ww / n * 100 + 0.5), math.floor(dd / n * 100 + 0.5)))
  end
end

-- 5. AI speed ----------------------------------------------------------------------
do
  local st = R.NewGame({ seed = 42, decks = { randomDeck(lcg(1)), randomDeck(lcg(2)) } })
  for _ = 1, 4 do R.Resolve(st, { AI.ChoosePlan(st, 1, "normal", lcg(3)), AI.ChoosePlan(st, 2, "normal", lcg(4)) }) end
  local t0 = os.clock()
  for _ = 1, 5 do AI.ChoosePlan(st, 2, "hard", lcg(5)) end
  local ms = (os.clock() - t0) / 5 * 1000
  print(("hard AI decision: %.1f ms (round %d)"):format(ms, st.round))
  check(ms < 400, "hard AI decides fast enough")
end

-- 6. collection ----------------------------------------------------------------------
do
  local db = {}
  C.Init(db)
  check(#db.deck == 20 and C.CheckDeck(db), "new character gets a legal starter deck")
  check(db.packs == C.STARTER_PACKS, "starter packs")
  local rnd = lcg(77)
  local counts = { common = 0, uncommon = 0, rare = 0, epic = 0, legendary = 0 }
  local N = 20000
  for _ = 1, N do
    for _, id in ipairs(C.RollPack(rnd)) do
      local r = Cards.byId[id].rarity
      counts[r] = counts[r] + 1
    end
  end
  print(("pack odds per pack: C %.2f U %.2f R %.3f E %.3f L %.3f"):format(counts.common / N, counts.uncommon / N,
    counts.rare / N, counts.epic / N, counts.legendary / N))
  check(math.abs(counts.legendary / N - 0.035) < 0.006, "legendary odds")
  check(math.abs(counts.epic / N - 0.125) < 0.012, "epic odds")

  local res = C.OpenPack(db, rnd)
  check(res and #res == 5 and db.packs == C.STARTER_PACKS - 1, "open pack")
  db.collection.onyxia = 1
  local kind, sh = C.Add(db, "onyxia")
  check(kind == "shards" and sh == 25, "extra legendary becomes shards")
  db.shards = 25
  check(C.BuyPack(db) and db.shards == 5, "buy a pack with shards")

  check(not C.CanAdd(db, "kobold"), "deck full")
  C.DeckRemove(db, "kobold")
  check(C.CanAdd(db, "kobold"), "room for a kobold again")
  check(not C.CanAdd(db, "ragnaros"), "can't add an unowned card")
  local saved = db.deck
  local cheapless = { "boar", "thug", "strider", "spider", "grunt", "croc", "fireball", "gnoll", "mountaineer", "axe" }
  db.deck = {}
  for _, id in ipairs(cheapless) do
    db.collection[id] = 2
    db.deck[#db.deck + 1] = id
    db.deck[#db.deck + 1] = id
  end
  local ok, why = C.CheckDeck(db)
  check(not ok and why:find("units costing 1"), "a deck with no 1-cost units is refused (" .. tostring(why) .. ")")
  db.deck[1], db.deck[2] = "kobold", "murloc"
  db.collection.kobold, db.collection.murloc = 2, 2
  check(C.CheckDeck(db), "two 1-cost units make it legal")
  db.deck = saved
  local r = C.RecordResult(db, "dorn", "win", "2026-11-19")
  local packs = 0
  for _, x in ipairs(r) do packs = packs + (x.packs or 0) end
  check(packs == 2, "first win ever and of the day: 2 packs")
  r = C.RecordResult(db, "dorn", "win", "2026-11-19")
  packs = 0
  for _, x in ipairs(r) do packs = packs + (x.packs or 0) end
  check(packs == 0, "second win the same day: no pack")
  local before = db.packs
  check(C.AddTravel(db, 1250) == 2 and db.packs == before + 2 and db.progress.travel == 50, "travel packs")

  -- ending a match early: a loss with no reward
  local shards, losses = db.shards, db.stats.losses
  r = C.RecordResult(db, "dorn", "loss", "2026-11-19", true)
  check(#r == 0 and db.shards == shards and db.stats.losses == losses + 1, "a conceded match pays nothing")
  r = C.RecordResult(db, "dorn", "loss", "2026-11-19")
  check(#r == 1 and db.shards == shards + 1, "a played-out loss still pays a shard")
end

-- 7. saved data: schema and migrations -----------------------------------------------
do
  local fresh = {}
  C.Init(fresh, R.RULES_VERSION)
  check(fresh.schema == C.SCHEMA, "a new character starts on the current schema")

  -- as saved by v0.2.3: no schema, position in window-scale units, a match
  -- tagged with the addon version
  local old = {}
  C.Init(old)
  old.schema = nil
  old.settings.scale = 0.8
  old.settings.point = { 100, 700 }
  old.match = { opp = "sally", version = "0.2.3", st = R.NewGame({ seed = 5, decks = { C.STARTER, C.STARTER } }) }
  local packs, owned = old.packs, old.collection.kobold
  check(C.Init(old, 1) == nil and old.match and old.match.rules == 1, "migration 1: a v0.2.3 match carries over")
  check(math.abs(old.settings.point[1] - 80) < 1e-9 and math.abs(old.settings.point[2] - 560) < 1e-9,
    "migration 1: window position converted to screen units")
  check(old.schema == C.SCHEMA and old.packs == packs and old.collection.kobold == owned, "collection untouched, schema recorded")
  C.Init(old, 1)
  check(math.abs(old.settings.point[1] - 80) < 1e-9, "migrations run once")

  local older = {}
  C.Init(older)
  older.schema = nil
  older.match = { opp = "sally", version = "0.1.0", st = R.NewGame({ seed = 5, decks = { C.STARTER, C.STARTER } }) }
  check(C.Init(older, 1) == "sally" and older.match == nil, "a match from before v0.2.2 is ended")

  -- damaged matches are dropped, not carried into the game
  local function damaged(label, breakIt)
    local db = {}
    C.Init(db)
    db.match = { opp = "dorn", rules = R.RULES_VERSION, st = R.NewGame({ seed = 5, decks = { C.STARTER, C.STARTER } }) }
    check(C.Init(db, R.RULES_VERSION) == nil and db.match ~= nil, "a sound match is kept (" .. label .. ")")
    breakIt(db.match)
    C.Init(db, R.RULES_VERSION)
    check(db.match == nil, "damaged match dropped: " .. label)
  end
  damaged("unknown opponent", function(m) m.opp = "nobody" end)
  damaged("no players", function(m) m.st.players = nil end)
  damaged("missing hand", function(m) m.st.players[2].hand = nil end)
  damaged("unknown card in a deck", function(m) m.st.players[1].deck[1] = "gone" end)
  damaged("unknown unit on the board", function(m) m.st.players[1].board[2] = { id = "gone", kw = {} } end)
  damaged("not a table", function(m) m.st = 7 end)
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
