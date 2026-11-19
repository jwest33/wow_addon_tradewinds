-- Balance harness, run on demand (it takes minutes, so the normal test run
-- leaves it out):
--
--   python tests/run_tests.py balance ai              AI levels against each other
--   python tests/run_tests.py balance ladder          the circuit, as a new player sees it
--   python tests/run_tests.py balance cards [n] [ids] each card's effect on winning
--
-- "cards" plays each card in a range of decks against the same decks with a
-- plain unit of the same cost in its place (cost c: c attack, c + 1 health),
-- with the same seeds, and reports the change in win rate. n scales the
-- number of games (default 4 per deck pairing); ids is a comma-separated list.
local ROOT = ROOT or "."
local ARGS = ARGS or {}

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

local function lcg(seed)
  local s = R.Seed(seed)
  return function(n)
    s = (s * 48271) % 2147483647
    return (s % n) + 1
  end
end

local function copy(list)
  local o = {}
  for i, v in ipairs(list) do o[i] = v end
  return o
end

-- levels[p]: an AI level, or "pass". styles[p]: optional style.
local function play(seed, decks, levels, styles)
  local rnd = lcg(seed)
  local st = R.NewGame({ seed = seed, decks = { copy(decks[1]), copy(decks[2]) } })
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

local function pct(x) return math.floor(x * 1000 + 0.5) / 10 end

local function randomDeck(rnd)
  for _ = 1, 200 do
    local d, n = {}, {}
    while #d < 20 do
      local c = Cards.collectible[rnd(#Cards.collectible)]
      if (n[c.id] or 0) < C.MaxCopies(c.id) then
        n[c.id] = (n[c.id] or 0) + 1
        d[#d + 1] = c.id
      end
    end
    if C.CheckCurve(d) then return d end
  end
  error("no legal random deck")
end

local mode = ARGS[1] or "ai"
local t0 = os.clock()

-- ---------------------------------------------------------------------------
if mode == "ai" then
  local levels = AI.LEVEL_ORDER
  local N = tonumber(ARGS[2]) or 100
  print(("AI levels, random legal decks, %d games per pairing (seats swapped half the time)"):format(N))
  for i = 1, #levels do
    for j = i + 1, #levels do
      local a, b = levels[i], levels[j]
      local wb, d = 0, 0
      for g = 1, N do
        local rnd = lcg(g * 13)
        local decks = { randomDeck(rnd), randomDeck(rnd) }
        local seatB = g % 2 + 1
        local lv = {}
        lv[seatB], lv[3 - seatB] = b, a
        local st = play(9000 + g, decks, lv)
        if st.winner == seatB then wb = wb + 1 elseif st.winner == 0 then d = d + 1 end
      end
      print(("  %-7s beats %-7s %5.1f%%  (draws %d)"):format(b, a, pct(wb / N), d))
    end
  end

-- ---------------------------------------------------------------------------
elseif mode == "ladder" then
  local N = tonumber(ARGS[2]) or 100
  print(("The circuit with the starter deck, %d games each"):format(N))
  print("  careful = the normal AI plays your side; careless = the easy AI")
  for _, o in ipairs(ns.Opponents) do
    local res = {}
    for k, lv in ipairs({ "normal", "easy" }) do
      local w = 0
      for g = 1, N do
        local st = play(5000 + g, { C.STARTER, o.deck }, { lv, o.level }, { nil, o.style })
        if st.winner == 1 then w = w + 1 end
      end
      res[k] = pct(w / N)
    end
    print(("  %-24s %-6s careful %5.1f%%  careless %5.1f%%"):format(o.name, o.level, res[1], res[2]))
  end
  do
    print("Heroic rematches (opponent: heroic deck and AI)")
    for _, o in ipairs(ns.Opponents) do
      if o.heroic then
        local res = {}
        for k, mine in ipairs({ C.STARTER, ns.OpponentById.prestor.deck }) do
          local w = 0
          for g = 1, N do
            local st = play(7000 + g, { mine, o.heroic }, { "hard", "heroic" }, { nil, o.style })
            if st.winner == 1 then w = w + 1 end
          end
          res[k] = pct(w / N)
        end
        print(("  %-24s starter deck %5.1f%%   Prestor's deck %5.1f%%  (your side played by the hard AI)"):format(
          o.name, res[1], res[2]))
      end
    end
  end

-- ---------------------------------------------------------------------------
elseif mode == "cards" then
  local per = tonumber(ARGS[2]) or 4
  local only
  if ARGS[3] then
    only = {}
    for id in ARGS[3]:gmatch("[^,]+") do only[id] = true end
  end
  -- plain units, one per cost
  for cost = 1, 6 do
    Cards.Add({ id = "ref" .. cost, name = "Plain " .. cost, cost = cost, type = "unit", rarity = "common",
      atk = cost, hp = cost == 1 and 2 or cost + 1, collectible = false })
  end
  local bases = { { name = "starter", deck = C.STARTER } }
  for _, o in ipairs(ns.Opponents) do bases[#bases + 1] = { name = o.id, deck = o.deck } end
  local gauntlet = {}
  for _, o in ipairs(ns.Opponents) do gauntlet[#gauntlet + 1] = o.deck end

  -- The deck with `id` in it, and the same deck with plain units instead.
  local function pair(base, id)
    local c = Cards.byId[id]
    local with, without = copy(base), copy(base)
    local n = 0
    for i, x in ipairs(base) do
      if x == id then without[i] = "ref" .. c.cost; n = n + 1 end
    end
    if n > 0 then return with, without end
    local want = C.MaxCopies(id)
    -- swap in for cards of the same cost, commons first
    local slots = {}
    for i, x in ipairs(base) do
      local xc = Cards.byId[x]
      slots[#slots + 1] = { i = i, d = math.abs(xc.cost - c.cost) * 10 + Cards.RARITY_RANK[xc.rarity] }
    end
    table.sort(slots, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
    for k = 1, want do
      with[slots[k].i] = id
      without[slots[k].i] = "ref" .. c.cost
    end
    return with, without
  end

  local rows = {}
  local games = 0
  for _, c in ipairs(Cards.collectible) do
    if not only or only[c.id] then
      local sum, sq, n = 0, 0, 0
      for bi, b in ipairs(bases) do
        local with, without = pair(b.deck, c.id)
        for gi, g in ipairs(gauntlet) do
          for k = 1, per do
            local seed = bi * 100003 + gi * 1009 + k * 17
            local a = play(seed, { with, g }, { "normal", "normal" })
            local z = play(seed, { without, g }, { "normal", "normal" })
            local function score(st) return st.winner == 1 and 1 or st.winner == 0 and 0.5 or 0 end
            local d = score(a) - score(z)
            sum, sq, n = sum + d, sq + d * d, n + 1
            games = games + 2
          end
        end
      end
      local mean = sum / n
      local se = math.sqrt(math.max(0, sq / n - mean * mean) / n)
      rows[#rows + 1] = { c = c, mean = mean, se = se }
      io.write(".")
      io.flush()
    end
  end
  print()
  table.sort(rows, function(a, b) return a.mean > b.mean end)
  print(("Win rate with the card minus with a plain unit of the same cost (%d games). +/- is one standard error."):format(games))
  local byRarity = {}
  for _, r in ipairs(rows) do
    print(("  %+6.1f +/- %3.1f   %-26s %-9s %d"):format(r.mean * 100, r.se * 100, r.c.name, r.c.rarity, r.c.cost))
    local x = byRarity[r.c.rarity] or { s = 0, n = 0 }
    x.s, x.n = x.s + r.mean, x.n + 1
    byRarity[r.c.rarity] = x
  end
  print("Average by rarity:")
  for _, r in ipairs(Cards.RARITIES) do
    local x = byRarity[r]
    if x then print(("  %-10s %+5.1f (%d cards)"):format(r, x.s / x.n * 100, x.n)) end
  end
else
  print("Unknown mode " .. mode .. ". Try ai, ladder or cards.")
end
print(("(%.0f s)"):format(os.clock() - t0))
