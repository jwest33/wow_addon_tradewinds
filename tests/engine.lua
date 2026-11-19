-- Engine tests: rules, cards, AI, collection. Pure Lua, no WoW mock needed.
-- Run with tests/run_tests.py.
local ROOT = ROOT or "."

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

-- load the engine files listed in the .toc (everything that isn't UI/Core)
local ns = {}
local ENGINE = { ["Engine/Rules.lua"] = true, ["Engine/Cards.lua"] = true, ["Engine/CardsRoads.lua"] = true, ["Engine/AI.lua"] = true,
  ["Data/Opponents.lua"] = true, ["Data/Tutorial.lua"] = true, ["Data/CardText.lua"] = true, ["Collection.lua"] = true }
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
  for _, o in ipairs(ns.Opponents) do
    validDeck(o.deck, o.name)
    validDeck(o.heroic, o.name .. " (heroic)")
    check(type(o.rematch) == "string" and type(o.style) == "table", o.name .. " has a rematch line and a style")
    local has = false
    for _, id in ipairs(o.heroic) do if id == o.signature then has = true end end
    check(has, o.name .. "'s heroic deck plays their signature card")
    check(table.concat(o.deck, ",") ~= table.concat(o.heroic, ","), o.name .. "'s heroic deck differs from their circuit deck")
  end
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

-- 2b. the second set: tribes, auras and its cards -----------------------------------
do
  local function arrive(st, p, lane, id)
    local u = R.Summon(st, p, lane, id)
    Cards.byId[id].arrive(st, u)
    R.Cleanup(st)
    return u
  end
  local function cast(st, p, id, lane)
    Cards.byId[id].play(st, p, lane)
    R.Cleanup(st)
  end
  local function kill(st, u)
    R.Damage(st, u, 99)
    R.Cleanup(st)
  end

  for _, c in ipairs(Cards.list) do
    if c.tribe then check(Cards.TRIBES[c.tribe], c.id .. " tribe " .. tostring(c.tribe)) end
    if c.aura then check(type(c.aura.atk) == "number" and (not c.aura.tribe or Cards.TRIBES[c.aura.tribe]), c.id .. " aura") end
    check(Cards.SETS[c.set], c.id .. " set")
  end
  for _, c in ipairs(Cards.list) do
    if c.text then
      check(type(c.short) == "string" and #c.short <= 38, c.id .. " has short text for its face (" .. tostring(c.short) .. ")")
    else
      check(c.short == nil, c.id .. " has no rules text, so no short text")
    end
  end
  for id in pairs(Cards.SHORT) do check(Cards.byId[id], "short text for a card that exists: " .. id) end
  check(Cards.byId.wolf.tribe == "beast" and Cards.byId.onyxia.tribe == "dragonkin" and Cards.byId.kobold.tribe == nil,
    "core cards have their tribes")
  for _, o in ipairs(ns.Opponents) do
    local c = Cards.byId[o.signature]
    check(c and c.collectible and c.signature == o.id and C.InPacks(c.id) == (c.rarity == "legendary"),
      o.name .. " has a signature card, in packs only if it's legendary")
  end
  check(Cards.byId[ns.CHAMPION_CARD].signature == "champion" and C.InPacks(ns.CHAMPION_CARD),
    "the champion's card is a legendary, so very rarely in packs")

  -- Beasts
  local st = blank()
  put(st, 1, 1, "wolf")
  check(arrive(st, 1, 2, "cub").atk == 2, "cub: +1 attack with another Beast")
  check(arrive(blank(), 1, 2, "cub").atk == 1, "cub: nothing alone")

  st = blank()
  local pl = put(st, 1, 1, "packleader")
  local w, k = put(st, 1, 3, "wolf"), put(st, 1, 2, "kobold")
  local ew = put(st, 2, 1, "wolf")
  check(R.Attack(st, w) == 2 and R.Attack(st, k) == 1 and R.Attack(st, pl) == 2 and R.Attack(st, ew) == 1,
    "packleader: +1 attack for your other Beasts only")
  local view = { players = { { board = R.DeepCopy(st.players[1].board) }, { board = {} } } }
  check(R.Attack(view, view.players[1].board[3]) == 2, "auras work on a replay view")

  st = blank()
  arrive(st, 1, 2, "tamer")
  check(st.players[1].board[1] and st.players[1].board[1].id == "hound" and not st.players[1].board[3], "tamer: one hound beside it")
  st = blank()
  put(st, 1, 1, "kobold")
  arrive(st, 1, 2, "tamer")
  check(st.players[1].board[3] and st.players[1].board[3].id == "hound", "tamer: the other side when the first is taken")
  st = blank()
  put(st, 1, 1, "kobold"); put(st, 1, 3, "kobold")
  arrive(st, 1, 2, "tamer")
  check(#R.Units(st, 1) == 3, "tamer: no room, no hound")

  st = blank()
  put(st, 1, 1, "wolf"); put(st, 1, 2, "boar"); put(st, 1, 4, "kobold")
  local g = arrive(st, 1, 3, "gorilla")
  check(g.atk == 6 and g.hp == 7 and g.maxHp == 7, "gorilla: +1/+1 per other Beast")

  st = blank()
  local b = put(st, 1, 1, "bangalash")
  kill(st, put(st, 1, 2, "wolf"))
  check(b.atk == 5 and b.hp == 4, "bangalash grows when your Beast dies")
  kill(st, put(st, 1, 2, "kobold"))
  kill(st, put(st, 2, 2, "wolf"))
  check(b.atk == 5, "bangalash: not for other units or enemy Beasts")

  st = blank()
  w, k = put(st, 1, 1, "wolf"), put(st, 1, 2, "kobold")
  cast(st, 1, "callwild")
  check(w.atk == 2 and w.hp == 2 and k.atk == 1 and k.hp == 2, "call of the wild buffs Beasts only")

  -- Murlocs
  st = blank()
  local cr = put(st, 1, 1, "coastrunner")
  check(R.Attack(st, cr) == 1, "coastrunner alone")
  put(st, 1, 2, "murloc"); put(st, 1, 3, "scout"); put(st, 1, 4, "kobold"); put(st, 2, 1, "murloc")
  check(R.Attack(st, cr) == 3, "coastrunner: +1 per other Murloc of yours")
  st = blank()
  local me = put(st, 1, 1, "murkeye")
  put(st, 1, 2, "warrior")
  check(R.Attack(st, me) == 4, "murk-eye: +1 for the other Murloc, +1 from the warrior's aura")

  st = blank()
  arrive(st, 1, 4, "tidehunter")
  check(st.players[1].board[3] and st.players[1].board[3].id == "scout", "tidehunter brings a scout")

  st = blank()
  put(st, 2, 1, "grunt")
  st.players[1].hand = { "netter" }
  R.Resolve(st, { { { h = 1, lane = 1 } }, {} }, { noAdvance = true })
  check(st.players[1].board[1].hp == 3 and st.players[2].board[1].hp == 3, "netter: the unit across doesn't strike that round")

  st = blank()
  local m1, k1 = put(st, 1, 1, "murloc"), put(st, 1, 3, "kobold")
  local o = arrive(st, 1, 2, "oracle")
  check(m1.atk == 3 and m1.hp == 2 and k1.atk == 1 and o.atk == 2, "oracle: +1/+1 for your other Murlocs")

  st = blank()
  put(st, 1, 2, "kobold")
  cast(st, 1, "shoal")
  local sb = st.players[1].board
  check(sb[1].id == "scout" and sb[2].id == "kobold" and sb[3].id == "scout" and sb[4].id == "scout", "shoal fills your empty lanes")

  -- Undead
  st = blank()
  local c1 = put(st, 2, 1, "croc")
  kill(st, put(st, 1, 1, "skeleton"))
  check(c1.hp == 4, "skeleton: 1 damage across when it falls")

  st = blank()
  kill(st, put(st, 1, 2, "corpse"))
  check(st.players[1].board[2] and st.players[1].board[2].id == "bones", "corpse leaves a skeleton in its lane")

  st = blank()
  put(st, 1, 2, "necro")
  R.StartRound(st)
  check(st.players[1].board[1] and st.players[1].board[1].id == "bones", "necromancer raises a skeleton each round")
  R.StartRound(st)
  check(st.players[1].board[3] and st.players[1].board[3].id == "bones", "and another, on the other side")

  st = blank()
  local gr = put(st, 2, 1, "grunt")
  kill(st, put(st, 1, 1, "banshee"))
  check(gr.atk == 1 and R.Attack(st, gr) == 1, "banshee: -2 attack across when she falls")
  kill(st, put(st, 1, 1, "banshee"))
  check(R.Attack(st, gr) == 0, "attack never goes below 0")

  st = blank()
  local co, ko = put(st, 1, 1, "corpse"), put(st, 1, 3, "kobold")
  arrive(st, 1, 2, "rivendare")
  check(co.atk == 3 and co.hp == 3 and co.kw.sturdy and ko.atk == 1 and not ko.kw.sturdy, "rivendare: your other Undead get +1/+1 and Sturdy")

  st = blank()
  st.players[1].morale = 5
  local t1 = put(st, 2, 2, "thug")
  cast(st, 1, "deathcoil", 2)
  check(t1.hp == 1 and st.players[1].morale == 7, "death coil: 2 damage and 2 Morale")

  st = blank()
  st.players[1].grave = { "grunt", "fireball", "potion" }
  cast(st, 1, "raise")
  local raised = R.Units(st, 1)
  check(#raised == 1 and raised[1].id == "grunt" and raised[1].hp == 4, "raise dead brings back the last unit that died")
  st = blank()
  st.players[1].grave = { "fireball" }
  cast(st, 1, "raise")
  check(#R.Units(st, 1) == 0, "raise dead with no dead unit does nothing")

  -- Defias
  st = blank()
  local fp = put(st, 2, 1, "footpad")
  cast(st, 1, "fireball", 1)
  check(fp.hp == 2 and st.players[2].morale == M, "footpad: Stealth, tactics can't target it")

  st = blank()
  arrive(st, 1, 1, "pillager")
  check(st.players[2].morale == M - 1, "pillager: the enemy loses 1 Morale")

  st = blank()
  local hand = #st.players[1].hand
  arrive(st, 1, 1, "smuggler")
  check(#st.players[1].hand == hand, "smuggler alone draws nothing")
  put(st, 1, 2, "thug")
  arrive(st, 1, 3, "smuggler")
  check(#st.players[1].hand == hand + 1, "smuggler with another Defias draws a card")

  st = blank()
  local th = put(st, 1, 1, "thug")
  put(st, 1, 2, "taskmaster")
  check(R.Attack(st, th) == 3 and R.Attack(st, put(st, 1, 3, "kobold")) == 1, "taskmaster: +1 attack for your other Defias")

  st = blank()
  put(st, 2, 1, "grunt"); put(st, 2, 2, "grunt"); put(st, 2, 3, "grunt")
  local far = put(st, 2, 4, "grunt")
  far.lane = 4
  st.players[1].hand = { "smite" }
  R.Resolve(st, { { { h = 1, lane = 2 } }, {} }, { noAdvance = true })
  check(st.players[1].board[2].hp == 5 and st.players[1].morale == M - 3, "mr. smite freezes the three units in front; the fourth still strikes")

  st = blank()
  local old = put(st, 2, 2, "grunt")
  st.players[1].hand = { "ambush", "ambush" }
  st.players[2].hand = { "grunt" }
  R.Resolve(st, { { { h = 1, lane = 1 }, { h = 2, lane = 2 } }, { { h = 1, lane = 1 } } }, { noAdvance = true })
  check(st.players[2].board[1] == nil and old.hp == 2, "ambush: 4 damage to a unit that arrived this round, 2 to an older one")

  st = blank()
  local vk = put(st, 1, 1, "kobold")
  Cards.byId.vanish.play(st, 1, 1)
  R.EndRound(st)
  check(vk.kw.stealth and R.Attack(st, vk) == 3 and vk.hp == 4 and vk.maxHp == 4, "vanish: Stealth and +2/+2, to keep")

  -- Dragonkin
  st = blank()
  local e1, e2 = put(st, 2, 1, "kobold"), put(st, 2, 3, "croc")
  arrive(st, 1, 2, "drake")
  check(e1.hp == 1 and e2.hp == 4, "drake: 1 damage to every enemy unit")

  st = blank()
  local wh = put(st, 1, 1, "whelp")
  put(st, 1, 2, "technician")
  check(R.Attack(st, wh) == 3 and R.Attack(st, put(st, 1, 3, "kobold")) == 1, "technician: +1 attack for your Dragonkin")

  st = blank()
  wh = put(st, 1, 1, "whelp")
  arrive(st, 1, 2, "drakkisath")
  check(wh.hp == 3 and wh.maxHp == 3 and R.Attack(st, wh) == 3, "drakkisath: +2 health for your other Dragonkin, and Rally")

  st = blank()
  local f1, f2, f3, f4 = put(st, 2, 1, "croc"), put(st, 2, 2, "croc"), put(st, 2, 3, "croc"), put(st, 2, 4, "croc")
  cast(st, 1, "flamebreath", 2)
  check(f1.hp == 3 and f2.hp == 1 and f3.hp == 3 and f4.hp == 5, "flame breath: 4 in the lane, 2 beside it")

  -- Neutral
  st = blank()
  arrive(st, 1, 1, "peon")
  check(st.players[1].morale == M - 1, "peon costs you 1 Morale")

  st = blank()
  st.players[1].morale = 6
  put(st, 1, 1, "chaplain")
  R.StartRound(st)
  check(st.players[1].morale == 7, "chaplain restores 1 Morale each round")

  st = blank()
  local s1, s2, s4 = put(st, 2, 1, "croc"), put(st, 2, 2, "croc"), put(st, 2, 4, "croc")
  kill(st, put(st, 1, 2, "sapper"))
  check(s1.hp == 4 and s2.hp == 4 and s4.hp == 5, "sapper: 1 damage across and beside when it falls")

  st = blank()
  hand = #st.players[1].hand
  arrive(st, 1, 1, "seahorn")
  check(#st.players[1].hand == hand + 2, "seahorn draws 2 cards")

  st = blank()
  put(st, 2, 1, "grunt"); put(st, 2, 2, "grunt"); put(st, 2, 3, "grunt")
  cast(st, 1, "warstomp", 2)
  combatOnly(st)
  check(st.players[1].morale == M, "war stomp: none of the three strike")

  st = blank()
  k = put(st, 1, 1, "kobold")
  cast(st, 1, "might", 1)
  R.EndRound(st)
  check(k.atk == 3 and k.hp == 4, "blessing of might: +2/+2 that stays")

  st = blank()
  st.players[1].morale = 7
  local bu = put(st, 1, 2, "croc")
  bu.hp = 1
  cast(st, 1, "bandage", 2)
  check(bu.hp == 5 and st.players[1].morale == 9, "bandage: full heal and 2 Morale")

  st = blank()
  st.players[1].morale = 5
  arrive(st, 1, 1, "kazzak")
  check(st.players[1].morale == 8, "kazzak restores 3 Morale when he arrives")

  st = blank()
  local hurt, fresh, tough = put(st, 2, 1, "croc"), put(st, 2, 2, "croc"), put(st, 2, 3, "ghoul")
  hurt.hp, tough.hp = 4, 1
  cast(st, 1, "execute", 1); cast(st, 1, "execute", 2); cast(st, 1, "execute", 3)
  check(st.players[2].board[1] == nil and fresh.hp == 5, "execute destroys a damaged unit only")
  check(st.players[2].board[3] == tough and tough.hp == 1 and not tough.kw.sturdy, "Sturdy survives an execute, once")
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

local function playGame(seed, levels, decks, styles)
  local rnd = lcg(seed)
  decks = decks or { randomDeck(rnd), randomDeck(rnd) }
  local st = R.NewGame({ seed = seed, decks = decks })
  while not st.winner do
    local plans = {}
    for p = 1, 2 do
      if levels[p] == "pass" then plans[p] = {}
      else plans[p] = AI.ChoosePlan(st, p, levels[p], rnd, { style = styles and styles[p] }) end
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

-- 3b. player against player: each side runs the game as player 1, and the two
-- mirrored copies must stay identical
do
  local rnd = lcg(31)
  local drift, games, mirrored = 0, 0, 0
  for g = 1, 30 do
    local d1, d2 = randomDeck(rnd), randomDeck(rnd)
    local host = R.NewGame({ seed = g * 7919, decks = { d1, d2 }, seats = { 1, 2 } })
    local guest = R.NewGame({ seed = g * 7919, decks = { d2, d1 }, seats = { 2, 1 } })
    while not host.winner do
      if R.Checksum(host) ~= R.Checksum(guest) then drift = drift + 1; break end
      local mine = AI.ChoosePlan(host, 1, "normal", rnd)      -- each side plans as its own player 1
      local theirs = AI.ChoosePlan(guest, 1, "normal", rnd)
      R.Resolve(host, { mine, theirs })
      R.Resolve(guest, { theirs, mine })
    end
    games = games + 1
    if R.Checksum(host) ~= R.Checksum(guest) then drift = drift + 1 end
    if guest.winner == (host.winner == 0 and 0 or 3 - host.winner) then mirrored = mirrored + 1 end
  end
  check(drift == 0, ("mirrored copies of a game stay identical round by round (%d drifted)"):format(drift))
  check(mirrored == games, "and agree on the winner")
  local a = R.NewGame({ seed = 5, decks = { C.STARTER, C.STARTER } })
  local b = R.Clone(a)
  check(R.Checksum(a) == R.Checksum(b), "a checksum is the same for the same game")
  b.players[2].morale = b.players[2].morale - 1
  check(R.Checksum(a) ~= R.Checksum(b), "and changes when the game does")
  local plain = R.NewGame({ seed = 77, decks = { C.STARTER, ns.OpponentById.dorn.deck } })
  local seated = R.NewGame({ seed = 77, decks = { C.STARTER, ns.OpponentById.dorn.deck }, seats = { 1, 2 } })
  check(R.Checksum(plain) == R.Checksum(seated), "seats { 1, 2 } is the same game as no seats")
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
  w = series(100, { "heroic", "normal" }, "heroic vs normal")
  check(w[1] >= 55, "heroic beats normal more often than not")

  -- AI decks against the starter deck
  for _, o in ipairs(ns.Opponents) do
    local ww, dd, n = 0, 0, 60
    for i = 1, n do
      local st = playGame(5000 + i, { "normal", o.level }, { C.STARTER, o.deck }, { nil, o.style })
      if st.winner == 1 then ww = ww + 1 elseif st.winner == 0 then dd = dd + 1 end
    end
    print(("starter deck (normal play) vs %-22s (%s): wins %d%%, draws %d%%"):format(o.name, o.level,
      math.floor(ww / n * 100 + 0.5), math.floor(dd / n * 100 + 0.5)))
  end
end

-- The AI opens with a unit (never a tactic), and never plays something it
-- rates worse than passing, at any level.
do
  local bad, total = 0, 0
  for _, o in ipairs(ns.Opponents) do
    for seed = 1, 30 do
      local st = R.NewGame({ seed = seed * 31 + o.index, decks = { C.STARTER, o.deck } })
      local plan = AI.ChoosePlan(st, 2, o.level, lcg(seed))
      total = total + 1
      if not (#plan == 1 and Cards.byId[plan[1].id].type == "unit" and Cards.byId[plan[1].id].cost == 1) then bad = bad + 1 end
    end
  end
  check(bad == 0, ("every opponent opens round 1 with a 1-cost unit (%d of %d didn't)"):format(bad, total))
  local wasted = 0
  for seed = 1, 60 do
    local st = R.NewGame({ seed = seed, decks = { C.STARTER, ns.OpponentById.dorn.deck } })
    R.Resolve(st, { {}, {} })
    st.players[2].hand = { "potion", "shout", "potion" }
    for l = 1, R.LANES do st.players[2].board[l] = nil end
    st.players[2].morale = R.MAX_MORALE
    for _, level in ipairs(AI.LEVEL_ORDER) do
      if #AI.ChoosePlan(st, 2, level, lcg(seed)) > 0 then wasted = wasted + 1 end
    end
  end
  check(wasted == 0, ("no Healing Potion at full Morale, no Battle Shout without units (%d wasted)"):format(wasted))
  bad = 0
  for _, o in ipairs(ns.Opponents) do
    for seed = 1, 6 do
      local st = R.NewGame({ seed = seed * 37 + o.index, decks = { C.STARTER, o.heroic } })
      local plan = AI.ChoosePlan(st, 2, "heroic", lcg(seed), { style = o.style })
      if not (#plan == 1 and Cards.byId[plan[1].id].type == "unit") then bad = bad + 1 end
    end
  end
  check(bad == 0, "heroic opponents open with a unit too")
end

-- Listing every plan, and the made-up replies
do
  local rnd = lcg(5)
  local checked, illegal, dupes, overs, replies, badReplies = 0, 0, 0, 0, 0, 0
  for g = 1, 12 do
    local st = R.NewGame({ seed = g, decks = { randomDeck(rnd), randomDeck(rnd) } })
    while not st.winner do
      local all = AI.AllPlans(st, 2, 5000)
      if all then
        local keys, empty = {}, false
        for _, p in ipairs(all) do
          checked = checked + 1
          if not R.CheckPlan(st, 2, p) then illegal = illegal + 1 end
          local k = AI.PlanKey(p)
          if keys[k] then dupes = dupes + 1 end
          keys[k] = true
          if #p == 0 then empty = true end
        end
        check(empty, "the plans include playing nothing")
        if #all > 2 and AI.AllPlans(st, 2, #all - 1) ~= nil then overs = overs + 1 end
      end
      for _ = 1, 5 do
        local q = 1
        local reply = AI.SampleReply(st, q, rnd)
        replies = replies + 1
        local cost, lanes = 0, {}
        for i, a in ipairs(reply) do
          local c = Cards.byId[a.id]
          cost = cost + c.cost
          if a.h ~= i then badReplies = badReplies + 1 end
          if c.type == "unit" then
            if st.players[q].board[a.lane] or lanes[a.lane] then badReplies = badReplies + 1 end
            lanes[a.lane] = true
          end
        end
        if cost > st.players[q].supply or #reply > #st.players[q].hand then badReplies = badReplies + 1 end
      end
      R.Resolve(st, { AI.ChoosePlan(st, 1, "hard", rnd), AI.ChoosePlan(st, 2, "heroic", rnd) })
    end
  end
  check(checked > 500 and illegal == 0 and dupes == 0, ("every listed plan is legal and listed once (%d plans)"):format(checked))
  check(overs == 0, "too many plans for the limit: no list")
  check(replies > 100 and badReplies == 0, "made-up replies fit the Supply, the hand size and the empty lanes")
  -- styles change what the AI values
  local full, hurt = blank(), blank()
  hurt.players[2].morale = 6
  local calm = AI.Evaluate(hurt, 1) - AI.Evaluate(full, 1)
  local keen = AI.Evaluate(hurt, 1, { aggro = 1.5 }) - AI.Evaluate(full, 1, { aggro = 1.5 })
  check(calm > 0 and keen > calm * 1.4, "an aggressive style values the opponent's lost Morale more")
end

-- 5. AI speed ----------------------------------------------------------------------
do
  local st = R.NewGame({ seed = 42, decks = { randomDeck(lcg(1)), randomDeck(lcg(2)) } })
  for _ = 1, 4 do R.Resolve(st, { AI.ChoosePlan(st, 1, "normal", lcg(3)), AI.ChoosePlan(st, 2, "normal", lcg(4)) }) end
  for _, level in ipairs({ "hard", "heroic" }) do
    local t0 = os.clock()
    for _ = 1, 5 do AI.ChoosePlan(st, 2, level, lcg(5)) end
    local ms = (os.clock() - t0) / 5 * 1000
    print(("%s AI decision: %.1f ms (round %d)"):format(level, ms, st.round))
    check(ms < 400, level .. " AI decides fast enough")
  end
  -- the slowest case: a full hand in the middle of the game
  local worst = 0
  for g = 1, 20 do
    local s = R.NewGame({ seed = g, decks = { randomDeck(lcg(g)), randomDeck(lcg(g + 50)) } })
    for _ = 1, 3 do R.Resolve(s, { {}, {} }) end
    local t0 = os.clock()
    AI.ChoosePlan(s, 2, "heroic", lcg(g))
    worst = math.max(worst, (os.clock() - t0) * 1000)
  end
  print(("heroic AI, full hand in round 4: at most %.0f ms"):format(worst))
  check(worst < 1500, "heroic AI's slowest decision stays reasonable")
end

-- 6. collection ----------------------------------------------------------------------
do
  local db = {}
  C.Init(db)
  check(#db.deck == 20 and C.CheckDeck(db), "new character gets a legal starter deck")
  check(db.packs == C.STARTER_PACKS, "starter packs")

  -- packs
  local rnd = lcg(77)
  local counts = { common = 0, uncommon = 0, rare = 0, epic = 0, legendary = 0 }
  local N, outside, holos, badSlot = 60000, 0, 0, 0
  for _ = 1, N do
    local cards, _, holo = C.RollPack(rnd)
    for _, id in ipairs(cards) do
      local c = Cards.byId[id]
      counts[c.rarity] = counts[c.rarity] + 1
      if not C.InPacks(id) then outside = outside + 1 end
    end
    if holo then
      holos = holos + 1
      if not cards[holo] then badSlot = badSlot + 1 end
    end
  end
  print(("pack odds per pack: C %.2f U %.2f R %.3f E %.4f L %.4f, holographic %.4f"):format(counts.common / N,
    counts.uncommon / N, counts.rare / N, counts.epic / N, counts.legendary / N, holos / N))
  check(counts.common == 2 * N and outside == 0, "a pack: two commons, nothing from outside the pack pools")
  check(math.abs(counts.legendary / N - C.PACK_ODDS.legendary / 1000) < 0.0015, "legendary odds (very rare)")
  check(math.abs(counts.epic / N - C.PACK_ODDS.epic / 1000) < 0.004, "epic odds")
  check(math.abs(counts.rare / N - C.PACK_ODDS.rare / 1000) < 0.01, "rare odds")
  check(math.abs(holos / N - 1 / C.HOLO_ODDS) < 0.002 and badSlot == 0, "holographic odds")
  local legends = {}
  for _, id in ipairs(C.PackPool("legendary")) do legends[id] = true end
  check(legends.onyxia and legends.ragnaros and legends.vancleef and legends.rivendare, "every legendary can come from a pack")
  for _, id in ipairs(C.PackPool("epic")) do
    check(not Cards.byId[id].signature, "signature epics stay out of packs: " .. id)
  end
  local dry = function(n) return n end   -- the die always comes up highest: never a rare or an epic by luck
  local pity, sawEpic = 0, {}
  for i = 1, C.PITY * 2 do
    local cards
    cards, pity = C.RollPack(dry, pity)
    if Cards.byId[cards[3]].rarity == "epic" then sawEpic[#sawEpic + 1] = i end
  end
  check(#sawEpic == 2 and sawEpic[1] == C.PITY and sawEpic[2] == C.PITY * 2, "an epic at least every " .. C.PITY .. " packs")

  local res = C.OpenPack(db, rnd)
  check(res and #res == C.PACK_SIZE and db.packs == C.STARTER_PACKS - 1 and db.progress.pity == 1, "open pack")

  -- holographic copies
  local hdb = {}
  C.Init(hdb)
  check(not C.IsHolo(hdb, "kobold"), "starter cards aren't holographic")
  check(C.Add(hdb, "raptor", true) == "new" and C.IsHolo(hdb, "raptor") and C.Owned(hdb, "raptor") == 1,
    "a holographic pull of a new card")
  check(C.Add(hdb, "raptor") == "copy" and C.IsHolo(hdb, "raptor") and C.Owned(hdb, "raptor") == 2,
    "a plain copy later keeps it holographic")
  hdb.collection.ogre = 2
  local hk, hs = C.Add(hdb, "ogre", true)
  check(hk == "holo" and hs == 0 and C.IsHolo(hdb, "ogre") and C.Owned(hdb, "ogre") == 2,
    "at the copy limit, a holographic pull makes your copy holographic instead of shards")
  local sh0 = hdb.shards
  hk = C.Add(hdb, "ogre", true)
  check(hk == "shards" and hdb.shards == sh0 + C.SHARD_VALUE.common, "a holographic pull of a card already holographic is shards")
  hdb.holo.nothere = true
  C.Init(hdb)
  check(hdb.holo.nothere == nil and hdb.holo.ogre, "holographic marks for cards you don't have are dropped")
  -- a pack whose holographic roll comes up: rnd answers 1 to the 1-in-HOLO_ODDS roll
  hdb.packs = 1
  local calls = 0
  local hres = C.OpenPack(hdb, function(n)
    calls = calls + 1
    if n == C.HOLO_ODDS then return 1 end
    if n == C.PACK_SIZE then return 2 end
    return n
  end)
  check(hres and hres[2].holo and not hres[1].holo and not hres[3].holo and C.IsHolo(hdb, hres[2].id),
    "a holographic card from a pack")
  db.collection.onyxia = 1
  local kind, sh = C.Add(db, "onyxia")
  check(kind == "shards" and sh == C.SHARD_VALUE.legendary, "extra legendary becomes shards")
  db.shards = C.PACK_COST + 5
  check(C.BuyPack(db) and db.shards == 5 and not C.BuyPack(db), "buy a pack with shards")

  -- crafting
  db.collection.bruiser = nil
  db.shards = C.CRAFT_COST.rare - 1
  check(not C.CanCraft(db, "bruiser") and not C.Craft(db, "bruiser") and db.collection.bruiser == nil, "can't craft without the shards")
  db.shards = C.CRAFT_COST.rare
  check(C.Craft(db, "bruiser") and db.collection.bruiser == 1 and db.shards == 0, "craft a rare")
  db.shards = 5000
  check(C.CraftCost("hogger") == C.SIGNATURE_CRAFT_COST and C.CraftCost("ragnaros") == C.CRAFT_COST.legendary
    and C.CraftCost("kazzak") == C.CRAFT_COST.epic, "craft costs: signature cards cost the most")
  db.collection.kobold = 2
  check(not C.CanCraft(db, "kobold") and not C.CanCraft(db, "runt"), "no crafting past the copy limit, no tokens")
  db.collection.rivendare = nil
  check(C.Craft(db, "rivendare") and not C.CanCraft(db, "rivendare"), "one legendary")
  db.shards = 0

  -- decks
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
  check(C.PlainDeck(C.STARTER) and not C.PlainDeck({ "kobold", "bruiser" }) and C.PlainDeck({ "kobold", "tinker" }),
    "a plain deck has nothing rarer than uncommon")

  -- rewards, stars and the ladder
  local function tally(list)
    local t = { packs = 0, shards = 0, stars = 0, cards = {}, unlocked = {} }
    for _, r in ipairs(list) do
      t.packs = t.packs + (r.packs or 0)
      t.shards = t.shards + (r.shards or 0)
      if r.star then t.stars = t.stars + 1 end
      if r.card then t.cards[#t.cards + 1] = r end
      if r.unlocked then t.unlocked[#t.unlocked + 1] = r.unlocked end
    end
    return t
  end
  local day, nextDay = "2026-11-19", "2026-11-20"
  local function quiet(d) db.daily = { date = d, id = "rounds", n = 0, done = false } end   -- a task wins don't touch
  quiet(day)
  check(C.Unlocked(db, "dorn") and not C.Unlocked(db, "bluegill") and not C.Unlocked(db, "prestor"), "only the first opponent is open")
  local packs, shards = db.packs, db.shards
  local t = tally(C.RecordResult(db, "dorn", "win", day))
  check(t.packs == 2 and t.stars == 1 and t.shards == C.REWARD.win.easy, "first win: a star, its pack, the day's pack, shards")
  check(db.packs == packs + 2 and db.shards == shards + C.REWARD.win.easy, "and they're paid once")
  check(t.unlocked[1] == "bluegill" and C.Unlocked(db, "bluegill") and not C.Unlocked(db, "sally"), "the next opponent opens")
  db.collection.bangalash = nil
  t = tally(C.RecordResult(db, "dorn", "win", day, { margin = C.REWARD.decisive, plain = true }))
  check(t.stars == 2 and t.packs == 2 and #t.cards == 1 and t.cards[1].card == "bangalash" and t.cards[1].kind == "new"
    and db.collection.bangalash == 1, "second and third star: the signature card and two packs")
  local _, n = C.Stars(db, "dorn")
  check(n == 3, "three stars")
  t = tally(C.RecordResult(db, "dorn", "win", day, { margin = 9, plain = true }))
  check(t.stars == 0 and t.packs == 0 and #t.cards == 0 and t.shards == C.REWARD.win.easy, "stars pay once; third win of the day still pays in full")
  t = tally(C.RecordResult(db, "dorn", "win", day))
  check(t.shards == C.REWARD.reducedWin, "the fourth win against the same opponent that day pays less")
  quiet(nextDay)
  t = tally(C.RecordResult(db, "dorn", "win", nextDay))
  check(t.shards == C.REWARD.win.easy and t.packs == 1, "next day: full pay again, and the first-win pack")
  t = tally(C.RecordResult(db, "prestor", "win", nextDay, { margin = 1 }))
  check(t.shards == C.REWARD.win.hard and t.stars == 1, "harder opponents pay more")

  shards = db.shards
  check(#C.RecordResult(db, "dorn", "loss", nextDay, { round = C.REWARD.lossRound - 1 }) == 0, "a loss before round 4 pays nothing")
  check(tally(C.RecordResult(db, "dorn", "loss", nextDay, { round = C.REWARD.lossRound })).shards == C.REWARD.loss, "a later loss pays a shard")
  check(tally(C.RecordResult(db, "dorn", "draw", nextDay, { round = 8 })).shards == C.REWARD.loss, "so does a draw")
  local losses = db.stats.losses
  check(#C.RecordResult(db, "dorn", "loss", nextDay, { round = 8, conceded = true }) == 0 and db.stats.losses == losses + 1,
    "a conceded match counts and pays nothing")
  check(db.shards == shards + 2 * C.REWARD.loss, "losses paid once")

  db.collection.hogger = 2
  shards = db.shards
  t = tally(C.RecordResult(db, "grumbletusk", "win", nextDay, { margin = 7 }))
  check(#t.cards == 1 and t.cards[1].kind == "shards" and t.cards[1].dupe == C.SHARD_VALUE.epic
    and db.shards == shards + C.REWARD.win.normal + C.SHARD_VALUE.epic, "a signature card you can't use more of becomes shards")

  for _, o in ipairs(ns.Opponents) do db.stars[o.id] = { true, true, true } end
  db.stars.prestor[3] = nil
  db.collection.ragnaros = nil
  check(not C.AllStars(db), "not every star yet")
  t = tally(C.RecordResult(db, "prestor", "win", nextDay, { plain = true }))
  check(C.AllStars(db) and #t.cards == 1 and t.cards[1].card == ns.CHAMPION_CARD and db.collection.ragnaros == 1,
    "every star on the circuit: the champion's card")
  t = tally(C.RecordResult(db, "prestor", "win", nextDay, { plain = true }))
  check(#t.cards == 0, "once")

  -- heroic rematches
  do
    local h = {}
    C.Init(h)
    h.daily = { date = day, id = "rounds", n = 0, done = false }
    check(not C.HeroicUnlocked(h), "heroic rematches start closed")
    for _, o in ipairs(ns.Opponents) do
      if o.index < #ns.Opponents then h.stars[o.id] = { true } end
    end
    local opened = false
    for _, r in ipairs(C.RecordResult(h, "prestor", "win", day)) do if r.heroic then opened = true end end
    check(opened and C.HeroicUnlocked(h), "beating the last opponent opens them, and says so")
    for _, r in ipairs(C.RecordResult(h, "prestor", "win", day)) do check(not r.heroic, "it says so once") end
    local wins, starsBefore = h.stats.wins, C.Stars(h, "dorn")[2]
    h.collection.bangalash = nil
    local t2 = tally(C.RecordResult(h, "dorn", "win", nextDay, { heroic = true, margin = 9, plain = true }))
    check(t2.stars == 0 and C.Stars(h, "dorn")[2] == starsBefore and h.record.dorn == nil,
      "a heroic win earns no stars and keeps its own record")
    check(h.heroic.dorn.w == 1 and h.heroic.dorn.beaten and h.stats.wins == wins + 1, "the heroic record")
    check(t2.shards == C.REWARD.win.heroic and t2.packs == C.REWARD.heroicPacks + 1, "heroic pay: shards, a pack, the day's first win")
    check(#t2.cards == 1 and t2.cards[1].card == "bangalash" and t2.cards[1].holo and C.IsHolo(h, "bangalash"),
      "first heroic win: their signature card, holographic")
    h.collection.murkeye = 2
    t2 = tally(C.RecordResult(h, "bluegill", "win", nextDay, { heroic = true }))
    check(t2.cards[1].kind == "holo" and C.IsHolo(h, "murkeye") and h.collection.murkeye == 2,
      "a signature card you already have turns holographic")
    t2 = tally(C.RecordResult(h, "dorn", "win", nextDay, { heroic = true }))
    check(#t2.cards == 0 and t2.packs == 0, "once per opponent")
    for _, o in ipairs(ns.Opponents) do
      if o.id ~= "prestor" then C.HeroicRecord(h, o.id).beaten = true end
    end
    h.collection.ragnaros = 1
    t2 = tally(C.RecordResult(h, "prestor", "win", nextDay, { heroic = true }))
    check(C.AllHeroic(h) and #t2.cards == 2 and t2.cards[2].card == ns.CHAMPION_CARD and C.IsHolo(h, ns.CHAMPION_CARD),
      "every heroic rematch won: the champion's card turns holographic")
    local l = h.stats.losses
    C.RecordResult(h, "dorn", "loss", nextDay, { heroic = true, round = 8 })
    check(h.heroic.dorn.l == 1 and h.stats.losses == l + 1, "heroic losses are recorded")
  end

  -- levels, flight paths, flight time
  packs, shards = db.packs, db.shards
  t = tally(C.LevelUp(db, 23))
  check(t.shards == C.REWARD.level and t.packs == 0, "a level gives shards")
  t = tally(C.LevelUp(db, 30))
  check(t.shards == C.REWARD.level and t.packs == 1, "every tenth level also gives a pack")
  t = tally(C.FlightPath(db))
  check(t.shards == C.REWARD.flightPath and db.shards == shards + 2 * C.REWARD.level + C.REWARD.flightPath and db.packs == packs + 1,
    "a new flight path gives shards")
  local before = db.packs
  db.progress.travel = 0
  check(C.AddTravel(db, 2 * C.TRAVEL_PACK_SECONDS + 50) == 2 and db.packs == before + 2 and db.progress.travel == 50, "travel packs")

  -- the daily task
  local f = {}
  C.Init(f)
  local d1 = C.Daily(f, day)
  check(C.TaskById[d1.id] and d1.n == 0 and C.Daily(f, day) == d1, "one task a day")
  local prev, repeats, seen = d1.id, 0, {}
  for i = 1, 60 do
    local d = C.Daily(f, ("2027-%02d-%02d"):format(1 + math.floor((i - 1) / 28), 1 + (i - 1) % 28))
    if d.id == prev then repeats = repeats + 1 end
    prev = d.id
    seen[d.id] = true
  end
  local kinds = 0
  for _ in pairs(seen) do kinds = kinds + 1 end
  check(repeats == 0 and kinds >= #C.TASKS - 1, "never the same task two days running, and they all come up (" .. kinds .. ")")

  local events = {
    { t = "die", p = 2 }, { t = "die", p = 1 }, { t = "morale", p = 2, delta = -3 }, { t = "morale", p = 1, delta = -2 },
    { t = "morale", p = 2, delta = 2 }, { t = "tactic", p = 1 }, { t = "tactic", p = 2 },
    { t = "place", p = 1, unit = { id = "wolf" } }, { t = "place", p = 1, unit = { id = "kobold" } },
    { t = "place", p = 1, unit = { id = "runt" }, summon = true }, { t = "place", p = 2, unit = { id = "wolf" } },
  }
  for id, want in pairs({ kills = 1, morale = 3, tactics = 1, units = 2, beasts = 1, rounds = 1 }) do
    f.daily = { date = day, id = id, n = 0, done = false }
    check(C.TaskEvents(f, day, events, 1) == nil and f.daily.n == want, "task progress from a round: " .. id .. " (" .. f.daily.n .. ")")
  end
  f.daily = { date = day, id = "kills", n = C.TaskById.kills.goal - 1, done = false }
  shards = f.shards
  local r = C.TaskEvents(f, day, events, 1)
  check(r and r.shards == C.REWARD.daily and f.daily.done and f.shards == shards + C.REWARD.daily, "finishing the task pays shards")
  check(C.TaskEvents(f, day, events, 1) == nil and f.shards == shards + C.REWARD.daily, "once")

  f.daily = { date = day, id = "wins", n = 1, done = false }
  shards = f.shards
  t = tally(C.RecordResult(f, "dorn", "win", day))
  check(f.daily.done and f.shards == shards + C.REWARD.win.easy + C.REWARD.daily and t.shards == C.REWARD.win.easy + C.REWARD.daily,
    "the win task finishes on a win, paid once")
  f.daily = { date = day, id = "healthy", n = 0, done = false }
  C.RecordResult(f, "dorn", "win", day, { morale = 7 })
  check(not f.daily.done, "7 Morale left isn't 8")
  C.RecordResult(f, "dorn", "win", day, { morale = 8 })
  check(f.daily.done, "8 is")
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

  -- migration 2: stars for opponents already beaten, nothing paid again
  local v3 = {}
  C.Init(v3)
  v3.schema, v3.stars = 1, nil
  v3.record = { dorn = { w = 2, l = 1, d = 0 }, sally = { w = 0, l = 3, d = 0 }, grumbletusk = { w = 1, l = 0, d = 0 } }
  local p0, s0 = v3.packs, v3.shards
  C.Init(v3, R.RULES_VERSION)
  check(v3.schema == C.SCHEMA and v3.stars.dorn[1] and not v3.stars.dorn[2] and v3.stars.sally == nil, "migration 2: a star for each opponent already beaten")
  check(v3.packs == p0 and v3.shards == s0, "migration 2 pays nothing")
  check(C.Unlocked(v3, "bluegill") and not C.Unlocked(v3, "sally") and C.Unlocked(v3, "grumbletusk") and C.Unlocked(v3, "fingers")
    and not C.Unlocked(v3, "graves"), "an opponent you had beaten stays open, and opens the one after")
  -- v0.8.0 swapped Graves (was 6th) and Pellwick (was 7th): nobody loses access
  local v4 = {}
  C.Init(v4)
  for _, id in ipairs({ "dorn", "bluegill", "sally", "grumbletusk", "fingers", "graves" }) do v4.stars[id] = { true } end
  check(C.Unlocked(v4, "pellwick") and C.Unlocked(v4, "graves") and C.Unlocked(v4, "prestor"),
    "beaten up to Graves under the old order: Pellwick, Graves and Prestor are all open")
end

-- 7b. deck slots
do
  local db = {}
  C.Init(db)
  check(db.deckSlot == 1 and db.decks[1] == db.deck, "a new character's deck is slot 1")
  local first = db.deck
  check(C.SelectDeck(db, 3) and db.deckSlot == 3 and db.deck ~= first and C.CheckDeck(db), "an unused slot starts as the starter deck")
  C.SetDeck(db, {})
  check(#db.deck == 0 and db.decks[3] == db.deck and #first == 20, "emptying a deck only touches that slot")
  check(not C.SelectDeck(db, 0) and not C.SelectDeck(db, C.DECK_SLOTS + 1) and not C.SelectDeck(db, 1.5) and db.deckSlot == 3,
    "only real slots")
  C.SelectDeck(db, 1)
  check(db.deck == first, "back to the first")
  -- migration 3: the old single deck becomes slot 1
  local old = {}
  C.Init(old)
  old.schema, old.decks, old.deckSlot = 2, nil, nil
  old.deck = { "kobold", "wolf" }
  local deck = old.deck
  C.Init(old)
  check(old.schema == C.SCHEMA and old.deckSlot == 1 and old.decks[1] == deck and old.deck == deck, "migration 3: your deck is slot 1")
  old.decks[2] = { "kobold", "gone", "wolf" }
  C.Init(old)
  check(#old.decks[2] == 2, "cards that no longer exist leave every deck")
  -- migration 5: someone who has played skips the welcome and the keyword tips
  local played = {}
  C.Init(played)
  played.schema, played.stats.wins = 4, 3
  C.Init(played)
  check(played.settings.seenWelcome and played.settings.seenKw.swift and played.settings.seenKw.stealth,
    "migration 5: a player with games behind them has seen the keywords")
  local fresh5 = {}
  C.Init(fresh5)
  check(not fresh5.settings.seenWelcome and not fresh5.settings.seenKw, "a new character gets the welcome and the tips")
  check(fresh5.packs == C.STARTER_PACKS and C.STARTER_PACKS == 1, "one starter pack (the tutorial pays the second)")
  local t1 = C.FinishTutorial(fresh5)
  local t2 = C.FinishTutorial(fresh5)
  check(#t1 == 1 and t1[1].packs == C.TUTORIAL_PACKS and #t2 == 0 and fresh5.packs == 1 + C.TUTORIAL_PACKS,
    "finishing the tutorial pays once")

  -- migration 6: a game against a player moves out of the computer's slot
  local function pvpGame(gid)
    return { opp = "pvp", rules = R.RULES_VERSION, st = R.NewGame({ seed = 9, decks = { C.STARTER, C.STARTER } }),
      pvp = { name = "Bob-Realm", gid = gid, host = true, mine = {}, theirs = {}, sums = {}, theirSums = {} } }
  end
  local v6 = {}
  C.Init(v6)
  v6.schema, v6.games, v6.active = 5, nil, nil
  v6.match = pvpGame("123")
  C.Init(v6, R.RULES_VERSION)
  check(v6.match == nil and v6.games["123"] and v6.games["123"].pvp.name == "Bob-Realm" and v6.active == "123",
    "migration 6: a game against a player moves to the games list, still on the board")
  local v6b = {}
  C.Init(v6b)
  v6b.schema = 5
  v6b.match = { opp = "dorn", rules = R.RULES_VERSION, st = R.NewGame({ seed = 4, decks = { C.STARTER, C.STARTER } }) }
  C.Init(v6b, R.RULES_VERSION)
  check(v6b.match and v6b.active == "ai" and next(v6b.games) == nil, "migration 6: a computer match stays on the board")
  -- the games list is checked like the match
  v6.games["456"] = pvpGame("456")
  v6.games["456"].rules = R.RULES_VERSION - 1
  v6.games["789"] = pvpGame("789")
  v6.games["789"].pvp.mine = nil
  v6.games["999"] = pvpGame("111")
  local _, ended = C.Init(v6, R.RULES_VERSION)
  check(ended == 3 and v6.games["123"] and not v6.games["456"] and not v6.games["789"] and not v6.games["999"],
    "games from other rules, damaged ones and mislabelled ones are ended")
  v6.active = "gone"
  C.Init(v6, R.RULES_VERSION)
  check(v6.active == nil, "the board forgets a game that isn't there")
  check(#C.Games(v6) == 1, "C.Games lists them")
end

-- 8. the pace of the collection -------------------------------------------------------
-- How many packs (earned, not counting the ones bought with shards from
-- duplicates) it takes to own the cards packs hold. At roughly 13 packs a week
-- of casual play, the target is three quarters in two to three weeks and
-- everything in two to three months; crafting shortens the tail further.
-- Legendaries are left out: packs hold them only very rarely, as a jackpot.
do
  local function counted(c) return C.InPacks(c.id) and c.rarity ~= "legendary" end
  local total, playset = 0, 0
  for _, c in ipairs(Cards.collectible) do
    if counted(c) then total = total + 1; playset = playset + C.MaxCopies(c.id) end
  end
  local function run(seed)
    local rnd = lcg(seed)
    local db = {}
    C.Init(db)
    db.packs = 0
    local marks, earned = {}, 0
    while not marks.all and earned < 2000 do
      earned = earned + 1
      db.packs = db.packs + 1
      while db.packs > 0 do
        C.OpenPack(db, rnd)
        -- shards from duplicates: more packs early on; once most cards are
        -- owned, craft the cheapest one still missing instead
        local have, missing = 0, {}
        for _, c in ipairs(Cards.collectible) do
          if counted(c) then
            if C.Owned(db, c.id) > 0 then have = have + 1 else missing[#missing + 1] = c.id end
          end
        end
        if have >= total * 0.75 then
          table.sort(missing, function(x, y) return C.CraftCost(x) < C.CraftCost(y) end)
          for _, id in ipairs(missing) do
            if not C.Craft(db, id) then break end
          end
        else
          while C.BuyPack(db) do end
        end
      end
      local have, copies = 0, 0
      for _, c in ipairs(Cards.collectible) do
        if counted(c) and C.Owned(db, c.id) > 0 then have = have + 1; copies = copies + C.Owned(db, c.id) end
      end
      if not marks.half and have >= total * 0.5 then marks.half = earned end
      if not marks.most and have >= total * 0.75 then marks.most = earned end
      if not marks.one and have == total then marks.one = earned end
      if copies == playset then marks.all = earned end
    end
    return marks
  end
  local runs = {}
  for seed = 1, 120 do runs[seed] = run(seed * 7919) end
  local function median(key)
    local v = {}
    for i, r in ipairs(runs) do v[i] = r[key] or 2000 end
    table.sort(v)
    return v[math.floor(#v / 2) + 1]
  end
  local half, most, one, all = median("half"), median("most"), median("one"), median("all")
  print(("collection pace: %d cards in packs; median packs to own 50%%: %d, 75%%: %d, one of each: %d, full playset: %d"):format(
    total, half, most, one, all))
  check(most >= 28 and most <= 48, "75% of the pack cards takes about three weeks of packs (" .. most .. ")")
  check(one >= 90 and one <= 170, "one of every pack card takes two to three months of packs (" .. one .. ")")
end


-- 9. the tutorial --------------------------------------------------------------------
-- Plays the script and checks that each round does what the coach says.
do
  local T = ns.Tutorial
  local st = T.NewGame()
  check(st.stacked and st.round == 1 and st.init == 1 and #st.players[1].hand == R.OPENING_HAND + 1,
    "tutorial: stacked decks, you have initiative")
  local affordable = {}
  for _, id in ipairs(st.players[1].hand) do
    if Cards.byId[id].cost <= st.players[1].supply then affordable[#affordable + 1] = id end
  end
  check(#affordable == 1 and affordable[1] == "kobold", "round 1: the Kobold is the only card you can play")
  local function play(r)
    local round = T.ROUNDS[r]
    check(T.Round(st) == round, "tutorial round " .. r .. " is scripted")
    local mine, theirs = T.PlanFor(st, 1, round.you), T.PlanFor(st, 2, round.dorn)
    check(mine and theirs, "tutorial round " .. r .. ": the scripted cards are in both hands")
    check(#T.Remaining(st, {}) == #round.you and #T.Remaining(st, mine) == 0, "tutorial round " .. r .. ": the plan matches")
    check(R.CheckPlan(st, 1, mine) and R.CheckPlan(st, 2, theirs), "tutorial round " .. r .. ": both plans are legal")
    check(T.Allowed(st, {}, round.you[1].id, round.you[1].lane) and not T.Allowed(st, {}, round.you[1].id, 5)
      and not T.Allowed(st, {}, "ogre"), "tutorial round " .. r .. ": only the asked-for play is allowed")
    st.events = {}
    R.Resolve(st, { mine, theirs })
    local ev = st.events
    st.events = nil
    return ev
  end
  local P, D = st.players[1], st.players[2]
  play(1)
  check(P.morale == 11 and D.morale == 11, "round 1: each Kobold hits the other's Morale")
  play(2)
  check(D.board[4] == nil and P.board[4].id == "thug" and P.board[2].id == "kobold" and D.board[2].id == "strider",
    "round 2: the Thug blocks Dorn's Kobold and destroys it")
  check(P.morale == 11 and D.morale == 12, "round 2: nothing gets through; Plainstrider's Arrive gives Dorn Morale back")
  local ev = play(3)
  local cast, died, combat, raptorStrikes = nil, nil, nil, 0
  for i, e in ipairs(ev) do
    if e.t == "tactic" and e.id == "fireball" then cast = i end
    if e.t == "die" and e.id == "raptor" then died = i end
    if e.t == "phase" and e.name == "combat" then combat = i end
    if e.t == "strike" and e.p == 2 and e.lane == 3 then raptorStrikes = raptorStrikes + 1 end
  end
  check(cast and died and combat and cast < died and died < combat and raptorStrikes == 0,
    "round 3: Fireball hits the Lashtail after it arrives, and it never strikes")
  check(D.morale == 9 and P.morale == 11 and P.board[1].id == "wolf", "round 3: the Wolf and the Thug hit Dorn's Morale")
  ev = play(4)
  local guarded = false
  for _, e in ipairs(ev) do
    if e.t == "strike" and e.p == 2 and e.lane == 3 and e.tp == 1 and e.tl == 2 then guarded = true end
  end
  check(guarded and P.morale == 11 and P.board[2] and P.board[2].id == "bear",
    "round 4: Dorn's Boar strikes the Guard Bear instead of your Morale")
  check(D.morale == 6 and T.Round(st) == nil and st.round == T.GUIDED + 1, "round 5 is yours to play, 11 Morale to 6")
  -- from there the player should usually win
  local wins, n = 0, 60
  for seed = 1, n do
    local c = R.Clone(st)
    local rnd = lcg(seed * 13)
    while not c.winner do R.Resolve(c, { AI.ChoosePlan(c, 1, "normal", rnd), AI.ChoosePlan(c, 2, T.LEVEL, rnd) }) end
    if c.winner == 1 then wins = wins + 1 end
  end
  print(("tutorial: from round 5 the player wins %d%%"):format(math.floor(wins / n * 100 + 0.5)))
  check(wins >= n * 0.75, "the tutorial is usually won")
  -- about 100 characters a line, five lines in the coach's box
  local function visible(s) return #(s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  for _, r in ipairs(T.ROUNDS) do
    check(visible(r.say) <= 400 and visible(r.after) <= 400 and visible(r.watch) <= 90,
      "the coach's text fits its box: " .. r.say:sub(1, 30))
  end
  check(visible(T.FREE) <= 400, "the hand-over text fits too")
end


print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
