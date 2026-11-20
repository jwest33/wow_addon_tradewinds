-- Collection, deck, packs, crafting, stars, daily tasks and rewards.
-- Everything works on the saved per-character table (TradewindsCharDB) passed
-- in as `db`, and takes its random numbers from `rnd`, so it can be tested
-- outside the game.
--
-- The reward numbers are tuned for this pace (tests/engine.lua checks the
-- pack side of it): about three quarters of the pack cards after two to
-- three weeks of casual play, everything after two to three months.
local _, ns = ...
local L = ns.L
local Cards = ns.Cards

local C = {}
ns.Collection = C

C.MAX_COPIES = { common = 2, uncommon = 2, rare = 2, epic = 2, legendary = 1 }
C.SHARD_VALUE = { common = 1, uncommon = 3, rare = 10, epic = 25, legendary = 50 }  -- a copy past the limit
C.CRAFT_COST = { common = 10, uncommon = 25, rare = 60, epic = 150, legendary = 400 }
C.SIGNATURE_CRAFT_COST = 400   -- signature cards, whatever their rarity
C.PACK_COST = 30               -- shards
C.PACK_SIZE = 3                -- two commons and one uncommon or better
-- The third card, per 1000 packs: a legendary (any of them, signature cards
-- included) 5, an epic 30, a rare 250, otherwise an uncommon.
C.PACK_ODDS = { legendary = 5, epic = 30, rare = 250 }
C.PITY = 25                    -- at most this many packs in a row without an epic or better
C.HOLO_ODDS = 100              -- 1 pack in this many has a holographic card
C.TRAVEL_PACK_SECONDS = 1200
C.STARTER_PACKS = 1
C.TUTORIAL_PACKS = 1           -- for finishing the tutorial, once
C.REWARD = {
  win = { easy = 2, normal = 4, hard = 6, heroic = 8, pvp = 4 },  -- shards, by the opponent's level
  heroicPacks = 1,    -- the first heroic win against each opponent (with a holographic signature card)
  fullWins = 3,       -- wins per opponent per day that pay the full amount
  reducedWin = 1,     -- what later wins that day pay
  loss = 1,           -- a loss or draw...
  lossRound = 4,      -- ...that reached this round
  level = 5,          -- shards per level gained
  levelPackEvery = 10, -- and a pack on these levels
  flightPath = 5,     -- shards per flight path discovered
  daily = 10,         -- shards for the daily task
  decisive = 6,       -- Morale lead for the second star
}
C.STARTER = {
  "kobold", "kobold", "murloc", "murloc", "wolf", "wolf", "boar", "boar", "thug", "thug",
  "strider", "strider", "spider", "spider", "grunt", "grunt", "croc", "croc", "fireball", "fireball",
}

C.SETTING_DEFAULTS = {
  toast = true,        -- offer a game when a flight starts
  hideOnLand = true,   -- close the window when the flight ends
  hideInCombat = true,
  speed = 1,           -- replay speed
  forecast = true,     -- show what your planned round would do
  minimap = true,
  minimapAngle = 200,
  scale = 1,
  sound = true,
  chatter = true,      -- the opponent's lines during a match
}
C.DECK_SLOTS = 3

function C.MaxCopies(id)
  return C.MAX_COPIES[Cards.byId[id].rarity] or 2
end

local function count(list, id)
  local n = 0
  for _, x in ipairs(list) do if x == id then n = n + 1 end end
  return n
end
C.Count = count

-- Saved-data migrations, in order. db.schema is the number of the last one
-- applied; a table with none has never been migrated. Each must be safe on
-- any table an older version could have saved.
C.MIGRATIONS = {
  -- 1 (v0.3.0): matches record the rules version instead of the addon
  -- version; the window position is stored in screen units, not in units of
  -- whatever the window's scale was.
  function(db)
    local m = db.match
    if type(m) == "table" and m.rules == nil and (m.version == "0.2.2" or m.version == "0.2.3") then m.rules = 1 end
    local s = db.settings
    if type(s) == "table" and type(s.point) == "table" then
      local k = tonumber(s.scale) or 1
      s.point = { (tonumber(s.point[1]) or 0) * k, (tonumber(s.point[2]) or 0) * k }
    end
  end,
  -- 2 (v0.4.0): stars. An opponent already beaten has the first one (that
  -- win was paid for at the time, so no reward now).
  function(db)
    db.stars = type(db.stars) == "table" and db.stars or {}
    if type(db.record) == "table" then
      for opp, rec in pairs(db.record) do
        if type(rec) == "table" and (tonumber(rec.w) or 0) > 0 then
          db.stars[opp] = type(db.stars[opp]) == "table" and db.stars[opp] or {}
          db.stars[opp][1] = true
        end
      end
    end
  end,
  -- 3 (v0.5.0): three deck slots. The deck you had is the first.
  function(db)
    db.decks = type(db.decks) == "table" and db.decks or {}
    if type(db.deck) == "table" then db.decks[1] = db.deck end
    db.deckSlot = 1
  end,
  -- 4 (v0.5.2): the portrait beside card tooltips is off unless asked for.
  function(db)
    if type(db.settings) == "table" then db.settings.portraits = false end
  end,
  -- 5 (v0.7.0): first-time tips for each keyword, and a welcome that offers
  -- the tutorial. Someone who has already played has seen the keywords and
  -- doesn't need the welcome (the tutorial is still there, with its pack).
  function(db)
    local s = db.stats
    local played = type(s) == "table" and ((tonumber(s.wins) or 0) + (tonumber(s.losses) or 0) + (tonumber(s.draws) or 0)) or 0
    if played > 0 and type(db.settings) == "table" then
      db.settings.seenKw = {}
      for _, k in ipairs(ns.Rules.KEYWORDS) do db.settings.seenKw[k.key] = true end
      db.settings.seenWelcome = true
    end
  end,
  -- 6 (v0.10.0): games against players get their own list (db.games, by game
  -- id), so several can run beside your match against the computer
  -- (db.match). db.active says which one is on the board.
  function(db)
    db.games = type(db.games) == "table" and db.games or {}
    local m = db.match
    if type(m) == "table" and type(m.pvp) == "table" and type(m.pvp.gid) == "string" then
      db.games[m.pvp.gid] = m
      db.match = nil
      db.active = m.pvp.gid
    elseif type(m) == "table" then
      db.active = "ai"
    end
  end,
  -- 7 (v0.13.0): the creature portrait beside card tooltips is gone (the
  -- card art already shows the creature), with its saved lookups.
  function(db)
    if type(db.settings) == "table" then db.settings.portraits = nil end
    db.displays = nil
  end,
}
C.SCHEMA = #C.MIGRATIONS
C.MAX_GAMES = 8   -- games against players at once (one per player)

-- Is this saved match something the game can carry on with?
local function playable(m)
  if type(m) ~= "table" then return false end
  if m.opp == "pvp" then
    local p = m.pvp
    if type(p) ~= "table" or type(p.name) ~= "string" or type(p.gid) ~= "string" then return false end
    for _, k in ipairs({ "mine", "theirs", "sums", "theirSums" }) do
      if type(p[k]) ~= "table" then return false end
    end
  elseif not ns.OpponentById[m.opp] then
    return false
  end
  local st = m.st
  if type(st) ~= "table" or type(st.round) ~= "number" or type(st.rng) ~= "number" or type(st.players) ~= "table" then
    return false
  end
  for p = 1, 2 do
    local P = st.players[p]
    if type(P) ~= "table" or type(P.morale) ~= "number" or type(P.supply) ~= "number" then return false end
    for _, k in ipairs({ "deck", "hand", "grave", "board" }) do
      if type(P[k]) ~= "table" then return false end
    end
    for _, k in ipairs({ "deck", "hand" }) do
      for _, id in ipairs(P[k]) do
        if not Cards.byId[id] then return false end
      end
    end
    for _, u in pairs(P.board) do
      if type(u) ~= "table" or not Cards.byId[u.id] or type(u.kw) ~= "table" then return false end
    end
  end
  return true
end

-- rules: the rules version (Rules.RULES_VERSION). A saved match from another
-- one, or one that's damaged, is ended without counting. Returns the opponent
-- id of a computer match it ended (if any), how many games against players it
-- ended, and whether the computer match was damaged (rather than from other
-- rules).
function C.Init(db, rules)
  if not db.collection then db.schema = C.SCHEMA end
  for i = (tonumber(db.schema) or 0) + 1, C.SCHEMA do
    C.MIGRATIONS[i](db)
    db.schema = i
  end
  if not db.collection then
    db.collection = {}
    for _, id in ipairs(C.STARTER) do db.collection[id] = (db.collection[id] or 0) + 1 end
    db.deck = {}
    for i, id in ipairs(C.STARTER) do db.deck[i] = id end
    db.packs = C.STARTER_PACKS
    db.shards = 0
  end
  db.deck = db.deck or {}
  db.decks = db.decks or {}
  db.deckSlot = (type(db.deckSlot) == "number" and db.deckSlot >= 1 and db.deckSlot <= C.DECK_SLOTS) and db.deckSlot or 1
  db.decks[db.deckSlot] = db.deck   -- db.deck is always the deck in use
  db.packs = db.packs or 0
  db.shards = db.shards or 0
  db.stats = db.stats or { wins = 0, losses = 0, draws = 0 }
  db.record = db.record or {}
  db.heroic = db.heroic or {}
  db.pvpRecord = db.pvpRecord or {}
  db.stars = db.stars or {}
  db.progress = db.progress or {}
  db.progress.travel = db.progress.travel or 0
  db.progress.pity = db.progress.pity or 0
  db.settings = db.settings or {}
  for k, v in pairs(C.SETTING_DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.holo = db.holo or {}
  -- forget cards that no longer exist (renamed or removed in an update)
  for id in pairs(db.collection) do
    if not (Cards.byId[id] and Cards.byId[id].collectible) then db.collection[id] = nil end
  end
  for id in pairs(db.holo) do
    if not db.collection[id] then db.holo[id] = nil end
  end
  for slot = 1, C.DECK_SLOTS do
    local deck = db.decks[slot]
    if type(deck) == "table" then
      for i = #deck, 1, -1 do
        if not (Cards.byId[deck[i]] and Cards.byId[deck[i]].collectible) then table.remove(deck, i) end
      end
    else
      db.decks[slot] = nil
    end
  end
  -- trades (see Trade.lua): deals you sent that wait for the other side's
  -- answer, and the deals you carried out for the side that sent them
  local function offer(list)
    if type(list) ~= "table" then return false end
    for _, e in ipairs(list) do
      if type(e) ~= "table" or not (Cards.byId[e.id] and Cards.byId[e.id].collectible) then return false end
    end
    return true
  end
  db.tradePending = type(db.tradePending) == "table" and db.tradePending or {}
  for tid, d in pairs(db.tradePending) do
    if not (type(tid) == "string" and type(d) == "table" and type(d.name) == "string" and offer(d.give) and offer(d.get)) then
      db.tradePending[tid] = nil
    end
  end
  db.tradesDone = type(db.tradesDone) == "table" and db.tradesDone or {}
  db.games = type(db.games) == "table" and db.games or {}
  local endedGames = 0
  for gid, m in pairs(db.games) do
    if not (type(m) == "table" and m.pvp and m.pvp.gid == gid and playable(m)) or (rules and m.rules ~= rules) then
      db.games[gid] = nil
      endedGames = endedGames + 1
    end
  end
  local ended, damaged
  if db.match and (type(db.match) ~= "table" or db.match.pvp or not playable(db.match)
      or (rules and db.match.rules ~= rules)) then
    local opp = type(db.match) == "table" and db.match.opp or nil
    damaged = not (type(db.match) == "table" and not db.match.pvp and playable(db.match))
    db.match = nil
    ended = ns.OpponentById[opp] and opp or nil
  end
  if db.active == "ai" then
    if not db.match then db.active = nil end
  elseif db.active ~= nil and not db.games[db.active] then
    db.active = nil
  end
  return ended, endedGames, damaged
end

-- Your games against players, oldest first.
function C.Games(db)
  local list = {}
  for _, m in pairs(db.games or {}) do list[#list + 1] = m end
  table.sort(list, function(a, b)
    if (a.started or 0) ~= (b.started or 0) then return (a.started or 0) < (b.started or 0) end
    return a.pvp.gid < b.pvp.gid
  end)
  return list
end

function C.Owned(db, id)
  return db.collection[id] or 0
end

-- Adds a card. Past the copy limit it turns into shards, except that a
-- holographic copy of a card you have no holographic copy of turns one of
-- yours holographic instead.
-- Returns "new" | "copy" | "holo" | "shards", shards gained.
function C.Add(db, id, holo)
  local n = db.collection[id] or 0
  if holo then
    db.holo = db.holo or {}
    if n >= C.MaxCopies(id) and not db.holo[id] then
      db.holo[id] = true
      return "holo", 0
    end
    if n < C.MaxCopies(id) then db.holo[id] = true end
  end
  if n >= C.MaxCopies(id) then
    local v = C.SHARD_VALUE[Cards.byId[id].rarity] or 1
    db.shards = db.shards + v
    return "shards", v
  end
  db.collection[id] = n + 1
  return n == 0 and "new" or "copy", 0
end

-- Holographic cards look different and play the same. Owning one holographic
-- copy shows every copy of that card you play or browse as holographic.
function C.IsHolo(db, id)
  return (db and db.holo and db.holo[id] and (db.collection[id] or 0) > 0) and true or false
end

-- Packs ---------------------------------------------------------------------------
-- The pools packs draw from. Signature cards are left out of the epic pool
-- (they are won from opponents, or crafted), but every legendary can turn up
-- in the very rare legendary slot, signature or not.
local pool
function C.PackPool(rarity)
  if not pool then
    pool = {}
    for _, r in ipairs(Cards.RARITIES) do pool[r] = {} end
    for _, c in ipairs(Cards.collectible) do
      if c.rarity == "legendary" or not c.signature then table.insert(pool[c.rarity], c.id) end
    end
  end
  return pool[rarity]
end

function C.InPacks(id)
  local c = Cards.byId[id]
  return (c.collectible and (c.rarity == "legendary" or not c.signature)) and true or false
end

-- Three cards: two commons and an uncommon, which is sometimes better (see
-- C.PACK_ODDS). pity: packs opened since the last epic or legendary; the pack
-- after C.PITY - 1 dry ones always has an epic. 1 pack in C.HOLO_ODDS has one
-- holographic card. Returns the cards, the new pity count, and the slot of the
-- holographic card (or nil).
function C.RollPack(rnd, pity)
  pity = pity or 0
  local function pick(r)
    local list = C.PackPool(r)
    return list[rnd(#list)]
  end
  local odds = C.PACK_ODDS
  local x = rnd(1000)
  local third = x <= odds.legendary and "legendary"
    or (x <= odds.legendary + odds.epic or pity >= C.PITY - 1) and "epic"
    or x <= odds.legendary + odds.epic + odds.rare and "rare" or "uncommon"
  local cards = { pick("common"), pick("common"), pick(third) }
  local holo = rnd(C.HOLO_ODDS) == 1 and rnd(C.PACK_SIZE) or nil
  local lucky = third == "epic" or third == "legendary"
  return cards, lucky and 0 or pity + 1, holo
end

-- Returns a list of { id, kind, shards, holo } or nil when there's no pack to
-- open.
function C.OpenPack(db, rnd)
  if db.packs <= 0 then return nil end
  db.packs = db.packs - 1
  local cards, holo
  cards, db.progress.pity, holo = C.RollPack(rnd, db.progress.pity)
  local results = {}
  for i, id in ipairs(cards) do
    local kind, shards = C.Add(db, id, holo == i)
    results[i] = { id = id, kind = kind, shards = shards, holo = holo == i or nil }
  end
  return results
end

function C.BuyPack(db)
  if db.shards < C.PACK_COST then return false end
  db.shards = db.shards - C.PACK_COST
  db.packs = db.packs + 1
  return true
end

-- Crafting ------------------------------------------------------------------------
function C.CraftCost(id)
  local c = Cards.byId[id]
  return c.signature and C.SIGNATURE_CRAFT_COST or C.CRAFT_COST[c.rarity]
end

function C.CanCraft(db, id)
  local c = Cards.byId[id]
  if not (c and c.collectible) then return false, L["That card can't be crafted."] end
  if C.Owned(db, id) >= C.MaxCopies(id) then return false, L["You already have every copy of %s you can use."]:format(c.name) end
  local cost = C.CraftCost(id)
  if db.shards < cost then
    return false, (L["%s costs %d shards to craft. You have %d."]):format(c.name, cost, db.shards)
  end
  return true, cost
end

function C.Craft(db, id)
  local ok, cost = C.CanCraft(db, id)
  if not ok then return false, cost end
  db.shards = db.shards - cost
  db.collection[id] = C.Owned(db, id) + 1
  return true, cost
end

-- Deck building ---------------------------------------------------------------
function C.CanAdd(db, id)
  local c = Cards.byId[id]
  if not (c and c.collectible) then return false, L["Not a deck card."] end
  if #db.deck >= ns.Rules.DECK_SIZE then return false, L["Your deck is full (20 cards)."] end
  local inDeck = count(db.deck, id)
  if inDeck >= C.MaxCopies(id) then
    return false, c.rarity == "legendary" and L["Only one copy of a legendary."] or L["At most two copies of a card."]
  end
  if inDeck >= C.Owned(db, id) then return false, L["You don't own another copy."] end
  return true
end

function C.DeckAdd(db, id)
  local ok, why = C.CanAdd(db, id)
  if ok then db.deck[#db.deck + 1] = id end
  return ok, why
end

function C.DeckRemove(db, id)
  for i = #db.deck, 1, -1 do
    if db.deck[i] == id then
      table.remove(db.deck, i)
      return true
    end
  end
  return false
end

-- Every deck needs some cheap cards, so the guided draws of rounds 1-3 always
-- find something to play (see R.GUIDED_DRAWS).
-- label: short, for the deck panel; need: why a deck isn't ready.
C.CURVE = {
  { cost = 1, unit = true, min = 2, label = L["Cost 1 units"],
    need = L["A deck needs at least %d units costing 1 (yours has %d)."] },
  { cost = 2, min = 4, label = L["Cost 2 cards"], need = L["A deck needs at least %d cards costing 2 (yours has %d)."] },
  { cost = 3, min = 3, label = L["Cost 3 cards"], need = L["A deck needs at least %d cards costing 3 (yours has %d)."] },
}

function C.CurveCounts(list)
  local out = {}
  for i, rule in ipairs(C.CURVE) do
    local n = 0
    for _, id in ipairs(list) do
      local c = Cards.byId[id]
      if c and c.cost == rule.cost and (not rule.unit or c.type == "unit") then n = n + 1 end
    end
    out[i] = n
  end
  return out
end

function C.CheckCurve(list)
  local counts = C.CurveCounts(list)
  for i, rule in ipairs(C.CURVE) do
    if counts[i] < rule.min then
      return false, rule.need:format(rule.min, counts[i])
    end
  end
  return true
end

function C.CheckDeck(db)
  local n = #db.deck
  if n ~= ns.Rules.DECK_SIZE then return false, (L["Your deck has %d of 20 cards."]):format(n) end
  local seen = {}
  for _, id in ipairs(db.deck) do
    seen[id] = (seen[id] or 0) + 1
    if seen[id] > C.MaxCopies(id) or seen[id] > C.Owned(db, id) then
      return false, L["Your deck has more copies of %s than allowed."]:format(Cards.byId[id].name)
    end
  end
  return C.CheckCurve(db.deck)
end

-- Replaces the deck in use.
function C.SetDeck(db, list)
  db.deck = list
  db.decks[db.deckSlot] = list
end

function C.ResetDeck(db)
  local list = {}
  for i, id in ipairs(C.STARTER) do list[i] = id end
  C.SetDeck(db, list)
end

-- Switches to deck slot i. A slot never used starts as the starter deck.
function C.SelectDeck(db, i)
  if type(i) ~= "number" or i < 1 or i > C.DECK_SLOTS or i ~= math.floor(i) then return false end
  db.decks[db.deckSlot] = db.deck
  db.deckSlot = i
  if type(db.decks[i]) == "table" then
    db.deck = db.decks[i]
  else
    C.ResetDeck(db)
  end
  return true
end

-- A deck with nothing rarer than uncommon (the third star).
function C.PlainDeck(list)
  for _, id in ipairs(list) do
    local c = Cards.byId[id]
    if c and Cards.RARITY_RANK[c.rarity] >= Cards.RARITY_RANK.rare then return false end
  end
  return true
end

-- Trading -----------------------------------------------------------------------
-- Players swap cards with each other (Trade.lua carries the deal). An offer is
-- a list of copies, { id =, holo = true | nil }. A holographic copy is the one
-- copy of a card that shines (see C.IsHolo), so a card has at most one; it
-- only goes when it's asked for, or when it's the last copy left to offer.
-- Any collectible card can be traded.
C.TRADE_MAX = 8   -- cards each side can put up in a trade

local function holoCopy(db, id)
  return (db.holo and db.holo[id] and C.Owned(db, id) > 0) and true or false
end

-- The copies of id you have to offer: how many plain ones, and whether the
-- holographic one is free. Copies in a deal still waiting for the other
-- side's answer are spoken for.
function C.Spare(db, id)
  local holo = holoCopy(db, id)
  local plain = C.Owned(db, id) - (holo and 1 or 0)
  for _, d in pairs(db.tradePending or {}) do
    for _, e in ipairs(d.give) do
      if e.id == id then
        if e.holo then holo = false else plain = plain - 1 end
      end
    end
  end
  return math.max(0, plain), holo
end

-- Can you give these copies? Returns false and why not.
function C.CanGive(db, offer)
  if #offer > C.TRADE_MAX then return false, L["A trade has room for %d cards from each side."]:format(C.TRADE_MAX) end
  local want = {}
  for _, e in ipairs(offer) do
    local c = Cards.byId[e.id]
    if not (c and c.collectible) then return false, L["That card can't be traded."] end
    want[e.id] = want[e.id] or { plain = 0, holo = 0 }
    if e.holo then want[e.id].holo = want[e.id].holo + 1 else want[e.id].plain = want[e.id].plain + 1 end
  end
  for id, w in pairs(want) do
    local plain, holo = C.Spare(db, id)
    if w.plain > plain or w.holo > (holo and 1 or 0) then
      return false, L["You don't have that many copies of %s to trade."]:format(Cards.byId[id].name)
    end
  end
  return true
end

-- What C.Add would make of each copy in the list (a { kind, shards } each),
-- without changing anything.
function C.PreviewAdd(db, list)
  local fake = { shards = 0, collection = setmetatable({}, { __index = db.collection }),
    holo = setmetatable({}, { __index = db.holo or {} }) }
  local out = {}
  for i, e in ipairs(list) do
    local kind, shards = C.Add(fake, e.id, e.holo)
    out[i] = { kind = kind, shards = shards }
  end
  return out
end

-- Takes out of every deck the copies you no longer own. Returns them, a
-- { id, slot } each.
function C.TrimDecks(db)
  local out = {}
  for slot = 1, C.DECK_SLOTS do
    local deck = db.decks[slot]
    if type(deck) == "table" then
      local counts = {}
      for _, id in ipairs(deck) do counts[id] = (counts[id] or 0) + 1 end
      for i = #deck, 1, -1 do
        local id = deck[i]
        if counts[id] > C.Owned(db, id) then
          table.remove(deck, i)
          counts[id] = counts[id] - 1
          out[#out + 1] = { id = id, slot = slot }
        end
      end
    end
  end
  return out
end

-- How many cards giving these copies away would take out of your decks.
function C.TradeTrims(db, give)
  local owned = {}
  for _, e in ipairs(give) do owned[e.id] = (owned[e.id] or C.Owned(db, e.id)) - 1 end
  local n = 0
  for slot = 1, C.DECK_SLOTS do
    local deck = db.decks[slot]
    if type(deck) == "table" then
      for id, left in pairs(owned) do n = n + math.max(0, count(deck, id) - math.max(0, left)) end
    end
  end
  return n
end

-- Carries out your side of a trade: the copies in `give` leave your
-- collection and those in `get` join it (a copy past the limit turns into
-- shards, as in a pack). Decks lose copies you no longer own. Returns what
-- you got (a { id, kind, shards, holo } each, like C.OpenPack) and the cards
-- taken out of decks (C.TrimDecks).
function C.ApplyTrade(db, give, get)
  db.holo = db.holo or {}
  for _, e in ipairs(give) do
    local n = C.Owned(db, e.id)
    if n > 0 then
      n = n - 1
      db.collection[e.id] = n > 0 and n or nil
      if e.holo or n == 0 then db.holo[e.id] = nil end
    end
  end
  local got = {}
  for i, e in ipairs(get) do
    local kind, shards = C.Add(db, e.id, e.holo)
    got[i] = { id = e.id, kind = kind, shards = shards, holo = e.holo or nil }
  end
  return got, C.TrimDecks(db)
end

-- Stars and the ladder ----------------------------------------------------------
-- Three per opponent. The first unlocks the next opponent.
C.STARS = {
  { name = L["Victory"], text = L["Win a match."], reward = L["a card pack"] },
  { name = L["Decisive"], text = (L["Win with at least %d more Morale than your opponent."]):format(C.REWARD.decisive),
    reward = L["their signature card"] },
  { name = L["Rank and file"], text = L["Win with a deck that has no rare, epic or legendary cards."], reward = L["2 card packs"] },
}

-- Returns the opponent's three stars (true / nil) and how many are earned.
function C.Stars(db, oppId)
  local s = db.stars[oppId] or {}
  local n = 0
  for i = 1, #C.STARS do if s[i] then n = n + 1 end end
  return s, n
end

function C.Unlocked(db, oppId)
  local o = ns.OpponentById[oppId]
  if not o then return false end
  if o.index == 1 then return true end
  local own = db.record[oppId]
  if (db.stars[oppId] and db.stars[oppId][1]) or (own and (own.w or 0) > 0) then return true end
  local prev = ns.Opponents[o.index - 1]
  return (db.stars[prev.id] and db.stars[prev.id][1]) and true or false
end

function C.AllStars(db)
  for _, o in ipairs(ns.Opponents) do
    local _, n = C.Stars(db, o.id)
    if n < #C.STARS then return false end
  end
  return true
end

-- Heroic rematches: every opponent again, with their heroic deck and the
-- strongest AI. They open once the last opponent on the circuit is beaten.
-- The first heroic win against each pays a pack and a holographic copy of
-- their signature card; all of them, a holographic champion's card.
function C.HeroicUnlocked(db)
  local last = ns.Opponents[#ns.Opponents]
  return (db.stars[last.id] and db.stars[last.id][1]) and true or false
end

-- { w, l, d, beaten }
function C.HeroicRecord(db, oppId)
  db.heroic[oppId] = db.heroic[oppId] or { w = 0, l = 0, d = 0 }
  return db.heroic[oppId]
end

function C.AllHeroic(db)
  for _, o in ipairs(ns.Opponents) do
    if not (db.heroic[o.id] and db.heroic[o.id].beaten) then return false end
  end
  return true
end

-- Daily task ----------------------------------------------------------------------
-- One a day. Most are counted from the events of each round you play.
C.TASKS = {
  { id = "wins", goal = 2, text = L["Win 2 matches"] },
  { id = "morale", goal = 20, text = L["Deal 20 damage to enemy Morale"] },
  { id = "kills", goal = 10, text = L["Destroy 10 enemy units"] },
  { id = "tactics", goal = 5, text = L["Cast 5 tactics"] },
  { id = "units", goal = 12, text = L["Play 12 units"] },
  { id = "beasts", goal = 6, text = L["Play 6 Beasts"] },
  { id = "rounds", goal = 15, text = L["Play 15 rounds"] },
  { id = "healthy", goal = 1, text = L["Win a match with 8 or more Morale left"] },
}
C.TaskById = {}
for i, t in ipairs(C.TASKS) do t.index = i; C.TaskById[t.id] = t end

-- Today's task (picked from the date, never the same two days running).
-- Returns the saved { date, id, n, done } and the task.
function C.Daily(db, today)
  local d = db.daily
  if type(d) ~= "table" or d.date ~= today or not C.TaskById[d.id] then
    local h = 0
    for i = 1, #today do h = (h * 31 + today:byte(i)) % 100003 end
    local i = h % #C.TASKS + 1
    if type(d) == "table" and C.TaskById[d.id] and C.TaskById[d.id].index == i then i = i % #C.TASKS + 1 end
    d = { date = today, id = C.TASKS[i].id, n = 0, done = false }
    db.daily = d
  end
  return d, C.TaskById[d.id]
end

-- Adds progress to today's task if it is `id`. Returns a reward when that
-- finishes it.
function C.TaskAdvance(db, today, id, amount)
  local d, task = C.Daily(db, today)
  if d.done or d.id ~= id or amount <= 0 then return nil end
  d.n = math.min(task.goal, d.n + amount)
  if d.n >= task.goal then
    d.done = true
    db.shards = db.shards + C.REWARD.daily
    return { shards = C.REWARD.daily, why = L["daily task: %s"]:format(task.text), paid = true }
  end
end

-- Counts one played round's events (from the rules engine) toward the task.
-- me: which player you are. Returns a reward when the task is finished.
function C.TaskEvents(db, today, events, me)
  local n = { rounds = 1, morale = 0, kills = 0, tactics = 0, units = 0, beasts = 0 }
  for _, e in ipairs(events) do
    if e.t == "morale" and e.p ~= me and e.delta < 0 then n.morale = n.morale - e.delta
    elseif e.t == "die" and e.p ~= me then n.kills = n.kills + 1
    elseif e.t == "tactic" and e.p == me then n.tactics = n.tactics + 1
    elseif e.t == "place" and e.p == me and not e.summon then
      n.units = n.units + 1
      if Cards.byId[e.unit.id].tribe == "beast" then n.beasts = n.beasts + 1 end
    end
  end
  local d = C.Daily(db, today)
  return n[d.id] and C.TaskAdvance(db, today, d.id, n[d.id]) or nil
end

-- Rewards -----------------------------------------------------------------------
local function pay(db, out)
  for _, r in ipairs(out) do
    if not r.paid then
      db.packs = db.packs + (r.packs or 0)
      db.shards = db.shards + (r.shards or 0)
    end
  end
  return out
end

local function giveCard(db, out, id, why, holo)
  local kind, shards = C.Add(db, id, holo)
  out[#out + 1] = { card = id, kind = kind, dupe = shards, why = why, holo = holo or nil }
end

-- result: "win" | "loss" | "draw". today: a date string. info (all optional):
--   conceded  the player ended the match early: a loss that pays nothing
--   round     the round the game ended in
--   morale, margin   your Morale at the end, and your lead
--   plain     the deck had nothing rarer than uncommon
--   heroic    a heroic rematch (no stars; see C.HeroicUnlocked)
-- Returns a list of rewards, each with a reason (why): { packs = n },
-- { shards = n }, { star = i }, { card = id, kind =, dupe = shards, holo = },
-- { unlocked = opponent id }.
function C.RecordResult(db, oppId, result, today, info)
  info = info or {}
  local o = ns.OpponentById[oppId]
  local heroic = info.heroic and true or false
  local rec
  if heroic then
    rec = C.HeroicRecord(db, oppId)
  else
    rec = db.record[oppId] or { w = 0, l = 0, d = 0 }
    db.record[oppId] = rec
  end
  local out = {}
  if result == "win" then
    local wasUnlocked = {}
    for _, x in ipairs(ns.Opponents) do wasUnlocked[x.id] = C.Unlocked(db, x.id) end
    db.stats.wins = db.stats.wins + 1
    rec.w = rec.w + 1
    -- shards: full value for the first few wins against this opponent today
    -- (heroic rematches count apart)
    local p = db.progress
    if type(p.wins) ~= "table" or p.wins.date ~= today then p.wins = { date = today, n = {} } end
    local key = heroic and (oppId .. ":heroic") or oppId
    local before = p.wins.n[key] or 0
    p.wins.n[key] = before + 1
    if before < C.REWARD.fullWins then
      out[#out + 1] = { shards = heroic and C.REWARD.win.heroic or C.REWARD.win[o.level] or C.REWARD.win.normal,
        why = heroic and L["heroic victory"] or L["victory"] }
    else
      out[#out + 1] = { shards = C.REWARD.reducedWin,
        why = (L["victory; %s has paid in full %d times today"]):format(o.short, C.REWARD.fullWins) }
    end
    if p.dailyWin ~= today then
      p.dailyWin = today
      out[#out + 1] = { packs = 1, why = L["first win of the day"] }
    end
    if heroic then
      if not rec.beaten then
        rec.beaten = true
        local why = L["first heroic win against %s"]:format(o.short)
        out[#out + 1] = { packs = C.REWARD.heroicPacks, why = why }
        giveCard(db, out, o.signature, why, true)
      end
      if not p.heroicChampion and C.AllHeroic(db) then
        p.heroicChampion = true
        giveCard(db, out, ns.CHAMPION_CARD, L["every heroic rematch won"], true)
      end
    else
      -- stars
      db.stars[oppId] = db.stars[oppId] or {}
      local stars = db.stars[oppId]
      local earned = { true, (info.margin or 0) >= C.REWARD.decisive, info.plain and true or false }
      for i, got in ipairs(earned) do
        if got and not stars[i] then
          stars[i] = true
          local why = L["star: %s"]:format(C.STARS[i].name)
          out[#out + 1] = { star = i, why = C.STARS[i].name }
          if i == 1 then out[#out + 1] = { packs = 1, why = why }
          elseif i == 2 then giveCard(db, out, o.signature, why)
          else out[#out + 1] = { packs = 2, why = why } end
        end
      end
      for _, x in ipairs(ns.Opponents) do
        if not wasUnlocked[x.id] and C.Unlocked(db, x.id) then out[#out + 1] = { unlocked = x.id, why = L["beat %s"]:format(o.short) } end
      end
      if C.HeroicUnlocked(db) and not p.heroicOpen then
        p.heroicOpen = true
        out[#out + 1] = { heroic = true, why = L["beat %s"]:format(o.short) }
      end
      if not p.champion and C.AllStars(db) then
        p.champion = true
        giveCard(db, out, ns.CHAMPION_CARD, L["every star on the circuit"])
      end
    end
    local t = C.TaskAdvance(db, today, "wins", 1)
    if t then out[#out + 1] = t end
    if (info.morale or 0) >= 8 then
      t = C.TaskAdvance(db, today, "healthy", 1)
      if t then out[#out + 1] = t end
    end
  else
    if result == "loss" then
      db.stats.losses = db.stats.losses + 1
      rec.l = rec.l + 1
    else
      db.stats.draws = db.stats.draws + 1
      rec.d = rec.d + 1
    end
    if not info.conceded and (info.round or C.REWARD.lossRound) >= C.REWARD.lossRound then
      out[#out + 1] = { shards = C.REWARD.loss, why = L["good game"] }
    end
  end
  return pay(db, out)
end

-- A match against another player (name: as it shows on the board). info:
--   conceded      you ended it early: a loss that pays nothing
--   theyConceded  they did: a win
--   round, morale
-- A win pays like a normal opponent's (and counts for the first win of the
-- day and the daily task), but only if the game reached round 4: a friend
-- giving up straight away pays nothing.
function C.RecordPvP(db, name, result, today, info)
  info = info or {}
  db.pvpRecord = db.pvpRecord or {}
  local rec = db.pvpRecord[name] or { w = 0, l = 0, d = 0 }
  db.pvpRecord[name] = rec
  local out = {}
  local played = (info.round or C.REWARD.lossRound) >= C.REWARD.lossRound
  if result == "win" then
    db.stats.wins = db.stats.wins + 1
    rec.w = rec.w + 1
    if played then
      local p = db.progress
      if type(p.wins) ~= "table" or p.wins.date ~= today then p.wins = { date = today, n = {} } end
      local key = "pvp:" .. name
      local before = p.wins.n[key] or 0
      p.wins.n[key] = before + 1
      if before < C.REWARD.fullWins then
        out[#out + 1] = { shards = C.REWARD.win.pvp, why = L["victory over %s"]:format(name) }
      else
        out[#out + 1] = { shards = C.REWARD.reducedWin,
          why = (L["victory; games against %s have paid in full %d times today"]):format(name, C.REWARD.fullWins) }
      end
      if p.dailyWin ~= today then
        p.dailyWin = today
        out[#out + 1] = { packs = 1, why = L["first win of the day"] }
      end
      local t = C.TaskAdvance(db, today, "wins", 1)
      if t then out[#out + 1] = t end
      if (info.morale or 0) >= 8 then
        t = C.TaskAdvance(db, today, "healthy", 1)
        if t then out[#out + 1] = t end
      end
    end
  else
    if result == "loss" then
      db.stats.losses = db.stats.losses + 1
      rec.l = rec.l + 1
    else
      db.stats.draws = db.stats.draws + 1
      rec.d = rec.d + 1
    end
    if not info.conceded and played then out[#out + 1] = { shards = C.REWARD.loss, why = L["good game"] } end
  end
  return pay(db, out)
end

-- The tutorial match was played to the end (any result). Pays once.
function C.FinishTutorial(db)
  db.tutorial = type(db.tutorial) == "table" and db.tutorial or {}
  if db.tutorial.done then return {} end
  db.tutorial.done = true
  return pay(db, { { packs = C.TUTORIAL_PACKS, why = L["finishing the tutorial"] } })
end

-- A level gained: shards, and a pack on every tenth level.
function C.LevelUp(db, level)
  local out = { { shards = C.REWARD.level, why = L["reaching level %s"]:format(tostring(level)) } }
  if type(level) == "number" and level > 0 and level % C.REWARD.levelPackEvery == 0 then
    out[#out + 1] = { packs = 1, why = L["reaching level %s"]:format(tostring(level)) }
  end
  return pay(db, out)
end

function C.FlightPath(db)
  return pay(db, { { shards = C.REWARD.flightPath, why = L["a new flight path"] } })
end

-- Adds flight time; returns the number of packs it earned.
function C.AddTravel(db, seconds)
  local p = db.progress
  p.travel = (p.travel or 0) + seconds
  local earned = 0
  while p.travel >= C.TRAVEL_PACK_SECONDS do
    p.travel = p.travel - C.TRAVEL_PACK_SECONDS
    earned = earned + 1
  end
  db.packs = db.packs + earned
  return earned
end
