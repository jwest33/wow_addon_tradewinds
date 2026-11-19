-- Collection, deck, packs and rewards. Everything works on the saved
-- per-character table (DeckhandCharDB) passed in as `db`, and takes its random
-- numbers from `rnd`, so it can be tested outside the game.
local _, ns = ...
local Cards = ns.Cards

local C = {}
ns.Collection = C

C.MAX_COPIES = { common = 2, uncommon = 2, rare = 2, epic = 2, legendary = 1 }
C.SHARD_VALUE = { common = 1, uncommon = 2, rare = 5, epic = 10, legendary = 25 }
C.PACK_COST = 20         -- shards
C.PACK_SIZE = 5
C.TRAVEL_PACK_SECONDS = 600
C.STARTER_PACKS = 3
C.STARTER = {
  "kobold", "kobold", "murloc", "murloc", "wolf", "wolf", "boar", "boar", "thug", "thug",
  "strider", "strider", "spider", "spider", "grunt", "grunt", "croc", "croc", "fireball", "fireball",
}

C.SETTING_DEFAULTS = {
  toast = true,        -- offer a game when a flight starts
  hideOnLand = true,   -- close the window when the flight ends
  hideInCombat = true,
  speed = 1,           -- replay speed
  portraits = true,    -- creature portraits in card tooltips
  forecast = true,     -- show what your planned round would do
  minimap = true,
  minimapAngle = 200,
  scale = 1,
}

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
}
C.SCHEMA = #C.MIGRATIONS

-- Is this saved match something the game can carry on with?
local function playable(m)
  if type(m) ~= "table" or not ns.OpponentById[m.opp] then return false end
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
-- id of a match it ended, if any.
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
  db.packs = db.packs or 0
  db.shards = db.shards or 0
  db.stats = db.stats or { wins = 0, losses = 0, draws = 0 }
  db.record = db.record or {}
  db.progress = db.progress or {}
  db.progress.travel = db.progress.travel or 0
  db.settings = db.settings or {}
  for k, v in pairs(C.SETTING_DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.displays = db.displays or {}
  -- forget cards that no longer exist (renamed or removed in an update)
  for id in pairs(db.collection) do
    if not (Cards.byId[id] and Cards.byId[id].collectible) then db.collection[id] = nil end
  end
  for i = #db.deck, 1, -1 do
    if not (Cards.byId[db.deck[i]] and Cards.byId[db.deck[i]].collectible) then table.remove(db.deck, i) end
  end
  if db.match and (not playable(db.match) or (rules and db.match.rules ~= rules)) then
    local opp = type(db.match) == "table" and db.match.opp or nil
    db.match = nil
    return ns.OpponentById[opp] and opp or nil
  end
end

function C.Owned(db, id)
  return db.collection[id] or 0
end

-- Adds a card. Past the copy limit it turns into shards.
-- Returns "new" | "copy" | "shards", shards gained.
function C.Add(db, id)
  local n = db.collection[id] or 0
  if n >= C.MaxCopies(id) then
    local v = C.SHARD_VALUE[Cards.byId[id].rarity] or 1
    db.shards = db.shards + v
    return "shards", v
  end
  db.collection[id] = n + 1
  return n == 0 and "new" or "copy", 0
end

-- Five cards: three commons, an uncommon (15%: rare) and a rare slot that is
-- epic 12.5% and legendary 3.5% of the time.
function C.RollPack(rnd)
  local function pick(r)
    local pool = Cards.byRarity[r]
    return pool[rnd(#pool)]
  end
  local out = { pick("common"), pick("common"), pick("common") }
  out[4] = pick(rnd(100) <= 15 and "rare" or "uncommon")
  local x = rnd(1000)
  out[5] = pick(x <= 35 and "legendary" or x <= 160 and "epic" or "rare")
  return out
end

-- Returns a list of { id, kind, shards } or nil when there's no pack to open.
function C.OpenPack(db, rnd)
  if db.packs <= 0 then return nil end
  db.packs = db.packs - 1
  local results = {}
  for i, id in ipairs(C.RollPack(rnd)) do
    local kind, shards = C.Add(db, id)
    results[i] = { id = id, kind = kind, shards = shards }
  end
  return results
end

function C.BuyPack(db)
  if db.shards < C.PACK_COST then return false end
  db.shards = db.shards - C.PACK_COST
  db.packs = db.packs + 1
  return true
end

-- Deck building ---------------------------------------------------------------
function C.CanAdd(db, id)
  local c = Cards.byId[id]
  if not (c and c.collectible) then return false, "Not a deck card." end
  if #db.deck >= ns.Rules.DECK_SIZE then return false, "Your deck is full (20 cards)." end
  local inDeck = count(db.deck, id)
  if inDeck >= C.MaxCopies(id) then
    return false, c.rarity == "legendary" and "Only one copy of a legendary." or "At most two copies of a card."
  end
  if inDeck >= C.Owned(db, id) then return false, "You don't own another copy." end
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
C.CURVE = {
  { cost = 1, unit = true, min = 2, label = "units costing 1" },
  { cost = 2, min = 4, label = "cards costing 2" },
  { cost = 3, min = 3, label = "cards costing 3" },
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
      return false, ("A deck needs at least %d %s (yours has %d)."):format(rule.min, rule.label, counts[i])
    end
  end
  return true
end

function C.CheckDeck(db)
  local n = #db.deck
  if n ~= ns.Rules.DECK_SIZE then return false, ("Your deck has %d of 20 cards."):format(n) end
  local seen = {}
  for _, id in ipairs(db.deck) do
    seen[id] = (seen[id] or 0) + 1
    if seen[id] > C.MaxCopies(id) or seen[id] > C.Owned(db, id) then
      return false, "Your deck has more copies of " .. Cards.byId[id].name .. " than allowed."
    end
  end
  return C.CheckCurve(db.deck)
end

function C.ResetDeck(db)
  db.deck = {}
  for i, id in ipairs(C.STARTER) do db.deck[i] = id end
end

-- Rewards -----------------------------------------------------------------------
-- result: "win" | "loss" | "draw". today: a date string. conceded: the player
-- ended the match early (a loss that pays nothing, so starting and ending
-- matches can't be farmed). Returns a list of { packs = n } / { shards = n }
-- rewards, each with a reason.
function C.RecordResult(db, oppId, result, today, conceded)
  local rec = db.record[oppId] or { w = 0, l = 0, d = 0 }
  db.record[oppId] = rec
  local out = {}
  if result == "win" then
    db.stats.wins = db.stats.wins + 1
    if rec.w == 0 then
      out[#out + 1] = { packs = 1, why = "first win against this opponent" }
    end
    rec.w = rec.w + 1
    if db.progress.dailyWin ~= today then
      db.progress.dailyWin = today
      out[#out + 1] = { packs = 1, why = "first win of the day" }
    end
    out[#out + 1] = { shards = 3, why = "victory" }
  elseif result == "loss" then
    db.stats.losses = db.stats.losses + 1
    rec.l = rec.l + 1
    if not conceded then out[#out + 1] = { shards = 1, why = "good game" } end
  else
    db.stats.draws = db.stats.draws + 1
    rec.d = rec.d + 1
    out[#out + 1] = { shards = 1, why = "good game" }
  end
  for _, r in ipairs(out) do
    db.packs = db.packs + (r.packs or 0)
    db.shards = db.shards + (r.shards or 0)
  end
  return out
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
