-- Saved data: loading a save must never lose anything.
--
-- Every save here, real (tests/saves/*.lua: copies of players' saved files,
-- git-ignored because they hold character names) and constructed, goes
-- through the whole addon in the WoW mock:
--   1. load: every card count the same, cards this version doesn't know set
--      aside in db.stash (Collection.SetAside), fields this version doesn't
--      use (an unreleased 0.17's) left exactly as they were
--   2. save to text the way WoW does, load again: nothing changes
--   3. use it: every tab, packs, a round of a match; save and load again
--   4. the previous version (OLD_ROOT, exported from git by run_tests.py)
--      loads it and sees the same cards, and this version loads what it saved
-- Then the set-aside store on its own: cards, decks and deals that name a
-- card this version doesn't know go aside and come back when it's known.
local ROOT = ROOT or "."
local OLD_ROOT = OLD_ROOT
local SAVE_FILES = SAVE_FILES or {}

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

-- ---------------------------------------------------------------------------
-- WoW's SavedVariables, in Lua: a table written out as text and read back.
-- Like the game, a table saved in two places comes back as two tables; unlike
-- it, anything the game couldn't save (a function, NaN, a table inside
-- itself, a table as a key) is an error here.
-- ---------------------------------------------------------------------------
local function keyText(k, path)
  local t = type(k)
  if t == "string" then return ("[%q]"):format(k) end
  if t == "number" then
    if k ~= k or k == math.huge or k == -math.huge then error("unsavable key at " .. path) end
    return ("[%.17g]"):format(k)
  end
  if t == "boolean" then return "[" .. tostring(k) .. "]" end
  error(("a %s as a key at %s"):format(t, path))
end

local function serialize(v, out, indent, path, open)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = ("%q"):format(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("unsavable number at " .. path) end
    out[#out + 1] = ("%.17g"):format(v)
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "table" then
    if open[v] then error("a table inside itself at " .. path) end
    if getmetatable(v) then error("a table with a metatable at " .. path) end
    open[v] = true
    out[#out + 1] = "{\n"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) ~= type(b) then return type(a) < type(b) end
      if type(a) == "boolean" then return tostring(a) < tostring(b) end
      return a < b
    end)
    for _, k in ipairs(keys) do
      out[#out + 1] = indent .. "  " .. keyText(k, path) .. " = "
      serialize(v[k], out, indent .. "  ", path .. "." .. tostring(k), open)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
    open[v] = nil
  else
    error(("can't save a %s at %s"):format(t, path))
  end
end

local function saveText(db)
  local out = { "TradewindsCharDB = " }
  serialize(db, out, "", "db", {})
  return table.concat(out) .. "\n"
end

local function loadText(text)
  local f = assert(loadstring(text))
  local env = {}
  setfenv(f, env)
  f()
  return env.TradewindsCharDB
end

local function roundTrip(db)
  local ok, text = pcall(saveText, db)
  check(ok, "the game could save it: " .. tostring(not ok and text or ""))
  if not ok then return nil end
  return loadText(text)
end

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = deepCopy(v) end
  return o
end

-- The first difference between a and b (a path), or nil when they're equal.
local function diff(a, b, path)
  path = path or "db"
  if type(a) ~= type(b) then return path .. (" (%s vs %s)"):format(type(a), type(b)) end
  if type(a) ~= "table" then
    if a ~= b then return path .. (" (%s vs %s)"):format(tostring(a), tostring(b)) end
    return nil
  end
  for k, v in pairs(a) do
    local d = diff(v, b[k], path .. "." .. tostring(k))
    if d then return d end
  end
  for k in pairs(b) do
    if a[k] == nil then return path .. "." .. tostring(k) .. " (only in the second)" end
  end
  return nil
end

-- The parts of the saved data a player would miss.
local KEEP = { "collection", "holo", "decks", "deck", "deckSlot", "packs", "shards", "stars", "record", "heroic",
  "pvpRecord", "stats", "tradePending", "tradesDone", "stash", "schema", "tutorial", "daily" }

local function kept(db)
  local out = {}
  for _, k in ipairs(KEEP) do out[k] = deepCopy(db[k]) end
  return out
end

-- Fields an unreleased 0.17 wrote, which this version doesn't use: kept as
-- they are, so nothing a newer version saved is lost.
local NEWER = { "finish", "look", "styles", "backs", "backup", "holoSeen", "packLog", "fresh", "wish" }

-- ---------------------------------------------------------------------------
-- A whole addon in a sandbox of its own (as in tests/pvp.lua). root: the
-- addon's folder (this version's, or OLD_ROOT). opts.beforeLoad(ns) runs
-- after the files are loaded and before ADDON_LOADED (to add a card a newer
-- version would have).
-- ---------------------------------------------------------------------------
local clients = 0
local function client(saved, root, opts)
  opts = opts or {}
  root = root or ROOT
  clients = clients + 1
  local env = setmetatable({}, { __index = _G })
  env._G = env
  local function run(path, base, ...)
    local f = assert(loadfile(base .. "/" .. path))
    setfenv(f, env)
    return f(...)
  end
  run("tests/wowmock.lua", ROOT)
  local M = env.MOCK
  M.playerName = "Saver" .. clients
  env.TradewindsCharDB = saved
  local ns = {}
  for line in io.lines(root .. "/Tradewinds.toc") do
    local file = line:match("^%s*([^#].-%.lua)%s*$")
    if file then run((file:gsub("\\", "/")), root, "Tradewinds", ns) end
  end
  if opts.beforeLoad then opts.beforeLoad(ns) end
  M.Fire("ADDON_LOADED", "Tradewinds")
  M.Fire("PLAYER_LOGIN")
  M.Fire("PLAYER_ENTERING_WORLD")
  M.Advance(2)
  local c = { env = env, MOCK = M, ns = ns, C = ns.Collection, UI = ns.UI }
  c.db = function() return env.TradewindsCharDB end
  c.chat = function(text)
    for _, m in ipairs(M.chat) do if tostring(m):find(text, 1, true) then return true end end
    return false
  end
  return c
end

local ASIDE_TEXT = "from a newer version of Tradewinds"

local function isCount(n) return type(n) == "number" and n > 0 and n == math.floor(n) end

-- Checks a save loaded by this version against what it was before.
local function checkLoaded(name, before, c)
  local db, C, Cards = c.db(), c.C, c.ns.Cards
  local function known(id) return Cards.byId[id] ~= nil and Cards.byId[id].collectible end
  check(type(db.schema) == "number" and db.schema >= C.SCHEMA, name .. ": schema " .. tostring(db.schema))
  local same, aside = true, true
  local bcol = {}
  for id, n in pairs(type(before.collection) == "table" and before.collection or {}) do bcol[id] = n end
  -- the one thing a login may add: the traps' gift, once (0.18.0)
  local gifted = not (type(before.progress) == "table" and before.progress.trapGift)
  if gifted then
    for _, id in ipairs(C.TRAP_GIFT) do
      if (tonumber(bcol[id]) or 0) < C.MaxCopies(id) then bcol[id] = (tonumber(bcol[id]) or 0) + 1 end
    end
  end
  check(db.progress.trapGift == true, name .. ": the traps' gift is marked given")
  for id, n in pairs(bcol) do
    if isCount(n) then
      if known(id) then
        if db.collection[id] ~= n then same = false; print("  " .. tostring(id), n, db.collection[id]) end
      elseif type(id) == "string" then
        if not (db.stash.collection[id] and db.stash.collection[id] >= n) then aside = false end
      end
    end
  end
  for id in pairs(db.collection) do
    if not bcol[id] then same = false; print("  extra " .. tostring(id)) end
  end
  check(same, name .. ": every card count is exactly what it was" .. (gifted and " (and the traps' gift)" or ""))
  check(aside, name .. ": cards this version doesn't know are set aside, not lost")
  for id, on in pairs(type(before.holo) == "table" and before.holo or {}) do
    if on and isCount(bcol[id]) and known(id) then check(C.IsHolo(db, id), name .. ": " .. id .. " is still holographic") end
  end
  if isCount(before.packs) or before.packs == 0 then check(db.packs == before.packs, name .. ": packs") end
  if isCount(before.shards) or before.shards == 0 then check(db.shards == before.shards, name .. ": shards") end
  for _, k in ipairs({ "stars", "record", "heroic", "pvpRecord", "tradesDone", "stats" }) do
    if type(before[k]) == "table" then
      local d = diff(before[k], db[k], k)
      check(d == nil, name .. ": " .. k .. " unchanged " .. tostring(d))
    end
  end
  if type(before.decks) == "table" then
    for slot, d in pairs(before.decks) do
      if type(d) == "table" and type(slot) == "number" and slot <= C.DECK_SLOTS then
        local ok = {}
        for _, id in ipairs(d) do if known(id) then ok[#ok + 1] = id end end
        check(diff(ok, db.decks[slot]) == nil, name .. ": deck " .. slot .. " unchanged")
        if #ok < #d then check(diff(d, db.stash.decks[slot]) == nil, name .. ": deck " .. slot .. " set aside whole") end
      end
    end
  end
  if type(before.settings) == "table" then
    for k, v in pairs(before.settings) do
      if k ~= "portraits" and k ~= "point" and type(v) ~= "table" then
        check(db.settings[k] == v, name .. ": setting " .. tostring(k) .. " kept")
      end
    end
  end
  for _, k in ipairs(NEWER) do
    if before[k] ~= nil then
      local d = diff(before[k], db[k], k)
      check(d == nil, name .. ": " .. k .. " (a newer version's) left as it was " .. tostring(d))
    end
  end
  if type(before.stash) == "table" and before.stash.finish ~= nil then
    check(diff(before.stash.finish, db.stash.finish) == nil, name .. ": the stash's finish records left as they were")
  end
end

-- Plays with a loaded save: every tab, packs, a round of a match.
local function use(name, c)
  local UI, C, db = c.UI, c.C, c.db()
  for _, tab in ipairs({ "play", "cards", "packs", "guide", "options" }) do
    UI.Show(tab)
    check(UI.tab == tab, name .. ": the " .. tab .. " tab opens")
  end
  db.packs = db.packs + 3
  UI.Show("packs")
  UI.Packs.Open()
  UI.Packs.RevealAll()
  UI.Packs.OpenAll()
  check(db.packs == 0, name .. ": packs opened")
  if not db.match and C.CheckDeck(db) then
    UI.Show("play")
    UI.Game.Start(c.ns.Opponents[1].id)
    if db.match then
      UI.Game.LockIn()
      c.MOCK.Advance(60)
      check(db.match and db.match.st.round >= 2, name .. ": a round of a match")
    end
  end
  UI.Hide()
end

-- The whole treatment for one save.
local function treat(name, original)
  local before = deepCopy(original)
  -- 1. load
  local c1 = client(deepCopy(original))
  checkLoaded(name, before, c1)
  local loaded = kept(c1.db())
  -- 2. save and load again: the same
  local again = roundTrip(c1.db())
  if not again then return end
  local c2 = client(again)
  local d = diff(loaded, kept(c2.db()))
  check(d == nil, name .. ": loading it again changes nothing " .. tostring(d))
  check(not c2.chat(ASIDE_TEXT), name .. ": and says nothing about cards set aside")
  -- 3. use it, save, load
  use(name, c2)
  local afterUse = deepCopy(c2.db())
  local used = roundTrip(c2.db())
  if not used then return end
  local c3 = client(used)
  d = diff(kept(afterUse), kept(c3.db()))
  check(d == nil, name .. ": playing, then a reload, keeps everything " .. tostring(d))
  if afterUse.match then
    check(c3.db().match and c3.db().match.st.round == afterUse.match.st.round, name .. ": the match carries on after a reload")
  end
  -- 4. the previous version loads it, and this version loads that again
  if OLD_ROOT then
    local old = client(roundTrip(c3.db()), OLD_ROOT)
    local odb = old.db()
    -- (0.17.0 sets aside the cards it doesn't know; 0.16.0 and older delete
    -- them, which is why going back past 0.17.0 loses new cards)
    local sameCards = true
    for id, n in pairs(c3.db().collection) do
      local known = old.ns.Cards.byId[id] and old.ns.Cards.byId[id].collectible
      if known and odb.collection[id] ~= n then sameCards = false end
    end
    check(sameCards, name .. ": the previous version sees the same cards (the ones it knows)")
    -- the cards it doesn't know (this version's new ones), it sets aside
    -- (0.17.0 and later have the stash), and this version takes them back:
    -- the whole trip leaves everything as this version had it
    local back = client(roundTrip(odb))
    local function noStash(db)
      local k = kept(db)
      k.stash = nil
      return k
    end
    d = diff(noStash(c3.db()), noStash(back.db()))
    check(d == nil, name .. ": and this version gets back everything it had " .. tostring(d))
    local s3, sb = c3.db().stash or {}, back.db().stash or {}
    d = diff(s3.collection or {}, sb.collection or {})
    check(d == nil, name .. ": with only the cards it doesn't know still set aside " .. tostring(d))
  end
end

-- ---------------------------------------------------------------------------
-- Real saves
-- ---------------------------------------------------------------------------
local real = 0
for _, file in ipairs(SAVE_FILES) do
  local f = assert(loadfile(ROOT .. "/tests/saves/" .. file))
  local env = {}
  setfenv(f, env)
  f()
  -- Deckhand was the addon's first name: its saves are the same data
  local db = env.TradewindsCharDB or env.DeckhandCharDB
  if type(db) == "table" then
    real = real + 1
    treat(file, db)
  end
end
print(("real saves: %d (tests/saves/)"):format(real))

-- ---------------------------------------------------------------------------
-- Constructed saves
-- ---------------------------------------------------------------------------
local STARTER = { "kobold", "kobold", "murloc", "murloc", "wolf", "wolf", "boar", "boar", "thug", "thug",
  "strider", "strider", "spider", "spider", "grunt", "grunt", "croc", "croc", "fireball", "fireball" }
local function starter()
  local t = {}
  for i, id in ipairs(STARTER) do t[i] = id end
  return t
end
local function starterCollection(extra)
  local t = {}
  for _, id in ipairs(STARTER) do t[id] = (t[id] or 0) + 1 end
  for id, n in pairs(extra or {}) do t[id] = n end
  return t
end

-- v0.2: no schema, one deck
treat("constructed v0.2.2", {
  collection = starterCollection({ ogre = 1, hogger = 1 }), deck = starter(), packs = 2, shards = 7,
  stats = { wins = 1, losses = 2, draws = 0 }, record = { dorn = { w = 1, l = 2, d = 0 } },
  settings = { point = { 100, 200 }, scale = 1.25, sound = false },
})

-- v0.6: holographic cards (one not owned any more), two decks
local d1, d2 = starter(), starter()
d2[20] = "ogre"
treat("constructed v0.6 with holographics", {
  schema = 4, collection = starterCollection({ ogre = 2, raptor = 1, azuregos = 1 }),
  holo = { ogre = true, raptor = true, hogger = true },
  decks = { d1, d2 }, deck = d2, deckSlot = 2, packs = 0, shards = 31, stars = { dorn = { true, true } },
  record = { dorn = { w = 3, l = 1, d = 0 } }, stats = { wins = 3, losses = 1, draws = 0 },
  progress = { travel = 300, pity = 12 }, settings = { forecast = false },
})

-- a newer version's save: cards, a deck and a deal this version doesn't know,
-- and that version's own fields
local newer = starter()
newer[20] = "newcard"
treat("constructed newer version", {
  schema = 9, collection = starterCollection({ newcard = 2, kodo = 1 }), holo = { newcard = true, kodo = true },
  decks = { newer, starter() }, deck = newer, deckSlot = 1, packs = 1, shards = 40,
  tradePending = { t1 = { name = "Friend", give = { { id = "newcard" } }, get = { { id = "kodo" } } } },
  finish = { newcard = { holo = { src = "pack" } } }, look = { kodo = { art = "classic" } }, wish = { onyxia = true },
  stash = { collection = {}, finish = { oldcard = { gilded = { src = "gild" } } }, decks = {}, trades = {} },
})

-- ---------------------------------------------------------------------------
-- The set-aside store, step by step
-- ---------------------------------------------------------------------------
local NEWCARD = { id = "newcard", name = "New Card", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1 }

local function knowNewcard(ns)
  local card = {}
  for k, v in pairs(NEWCARD) do card[k] = v end
  card.icon = ns.Cards.Icons("INV_Misc_QuestionMark")
  ns.Cards.Add(card)
  ns.Cards.Finish()
end

do
  -- a newer version's card, with a holographic copy and a deck
  local deck = starter()
  deck[20] = "newcard"
  local c = client({ schema = 7, collection = starterCollection({ newcard = 2 }), holo = { newcard = true },
    decks = { deck }, deck = deck, deckSlot = 1, packs = 0, shards = 0 })
  local db, C = c.db(), c.C
  check(db.collection.newcard == nil and db.stash.collection.newcard == 2 and db.stash.holo.newcard and db.holo.newcard == nil,
    "an unknown card is set aside with its holographic copy")
  check(#db.deck == 19 and db.decks[1] == db.deck and #db.stash.decks[1] == 20 and db.stash.deckLeft[1] == 19,
    "a deck loses the card; the whole list is set aside")
  check(c.chat(ASIDE_TEXT), "and chat says the cards are kept safe")
  check(not C.CheckDeck(db), "(the trimmed deck needs a card before it can play)")
  -- the version that knows the card again
  local back = client(roundTrip(db), nil, { beforeLoad = knowNewcard })
  local bdb, BC = back.db(), back.C
  check(bdb.collection.newcard == 2 and BC.IsHolo(bdb, "newcard") and bdb.stash.collection.newcard == nil
    and bdb.stash.holo.newcard == nil, "the card comes back, holographic, when it's known again")
  check(#bdb.deck == 20 and bdb.deck[20] == "newcard" and bdb.decks[1] == bdb.deck and bdb.stash.decks[1] == nil
    and bdb.stash.deckLeft[1] == nil, "and the deck is whole again")
  check(not back.chat(ASIDE_TEXT), "nothing set aside: no message")
  check(BC.CheckDeck(bdb), "and it can play")
end

do
  local c = client({})
  local C, Cards = c.C, c.ns.Cards
  local card = { id = "newcard", name = "New Card", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1,
    kw = {}, collectible = true, set = "core", icon = { "x" } }
  local function db0(extra)
    local deck = starter()
    deck[20] = "newcard"
    local db = { schema = 7, collection = starterCollection({ newcard = 1 }), decks = { deck, starter() }, deck = deck,
      deckSlot = 1, packs = 0, shards = 0 }
    for k, v in pairs(extra or {}) do db[k] = v end
    return db
  end
  -- a deck changed meanwhile stays as it is now
  local db = db0()
  C.Init(db)
  table.insert(db.decks[1], "wolf")
  Cards.byId.newcard = card
  C.Init(db)
  check(#db.deck == 20 and db.deck[20] == "wolf" and db.stash.decks[1] == nil, "a deck that gained a card meanwhile stays as it is")
  Cards.byId.newcard = nil
  -- and so does one that lost another card meanwhile
  db = db0()
  C.Init(db)
  table.remove(db.decks[1], 1)
  Cards.byId.newcard = card
  C.Init(db)
  check(#db.deck == 18 and db.stash.decks[1] == nil, "a deck that lost another card meanwhile stays as it is")
  Cards.byId.newcard = nil
  -- a deck 0.17 set aside (no count left) comes back if it's unchanged
  db = db0()
  C.Init(db)
  db.stash.deckLeft = nil
  Cards.byId.newcard = card
  C.Init(db)
  check(#db.deck == 20 and db.deck[20] == "newcard", "a deck 0.17 set aside comes back")
  Cards.byId.newcard = nil
  -- the other deck slot, not the one in use
  db = db0()
  db.decks[2][20] = "newcard"
  C.Init(db)
  check(#db.decks[2] == 19 and #db.stash.decks[2] == 20, "a deck in another slot is set aside too")
  Cards.byId.newcard = card
  C.Init(db)
  check(#db.decks[2] == 20 and db.decks[2][20] == "newcard" and db.deck == db.decks[1], "and comes back to its slot")
  Cards.byId.newcard = nil
  -- deals waiting for an answer
  local deal = { name = "Friend", give = { { id = "newcard" } }, get = { { id = "kodo", holo = true } } }
  db = db0({ tradePending = { t1 = deal, t2 = { name = "Friend", give = {}, get = { { id = "kodo" } } }, bad = { name = 3 } } })
  C.Init(db)
  check(db.tradePending.t1 == nil and db.stash.trades.t1 and db.tradePending.t2 and db.tradePending.bad == nil,
    "a deal that names an unknown card is set aside; a known one stays; a broken one goes")
  Cards.byId.newcard = card
  C.Init(db)
  check(db.tradePending.t1 and db.tradePending.t1.get[1].holo and db.stash.trades.t1 == nil, "and it comes back to wait for its answer")
  Cards.byId.newcard = nil
  -- what's set aside never shrinks; what comes back never lowers a count
  db = db0({ collection = starterCollection({ ghost = 1, kodo = 1 }),
    stash = { collection = { ghost = 2, kodo = 2 }, finish = { ghost = { holo = { src = "pack" } } } } })
  C.Init(db)
  check(db.stash.collection.ghost == 2 and db.collection.ghost == nil, "a card set aside keeps its count")
  check(db.collection.kodo == 2 and db.stash.collection.kodo == nil, "one that's known comes back at its higher count")
  check(db.stash.finish.ghost and db.stash.finish.ghost.holo, "0.17's records in the stash are left as they are")
  -- odd values
  db = db0({ collection = starterCollection({ oddity = "3", halfway = 2.5, none = 0, minus = -1, [7] = 1 }) })
  C.Init(db)
  local sc = db.stash.collection
  check(sc.oddity == 3 and sc.halfway == 2 and sc.none == nil and sc.minus == nil and sc[7] == nil and db.collection[7] == nil,
    "odd counts: a number in text and a fraction are set aside; nothing, less than nothing and a number id are dropped")
  db = db0({ stash = "broken" })
  C.Init(db)
  check(type(db.stash) == "table" and db.stash.collection.newcard == 1, "a broken stash is replaced")
  db = db0({ stash = { decks = { a = starter(), [9] = starter(), [2] = "x" }, deckLeft = { a = 3 } } })
  C.Init(db)
  check(db.stash.decks.a == nil and db.stash.decks[9] == nil and db.stash.decks[2] == nil and db.stash.decks[1]
    and db.stash.deckLeft.a == nil, "set-aside decks for slots that don't exist are dropped")
  -- logging in twice changes nothing
  db = db0({ holo = { newcard = true } })
  C.Init(db)
  local first = deepCopy(db)
  local _, _, _, aside = C.Init(db)
  check(diff(first, db) == nil and aside == 0, "logging in again changes nothing and sets nothing more aside")
end

-- The whole round trip: a newer version's save, this version, the previous
-- version (which knows nothing of the stash and leaves it be), and a version
-- that knows the card again.
if OLD_ROOT then
  local deck = starter()
  deck[20] = "newcard"
  local c = client({ schema = 7, collection = starterCollection({ newcard = 2, kodo = 1 }), holo = { newcard = true },
    decks = { deck }, deck = deck, deckSlot = 1, packs = 0, shards = 0 })
  local old = client(roundTrip(c.db()), OLD_ROOT)
  -- it leaves what's set aside as it is, and adds only this version's new
  -- cards (which it doesn't know)
  local s0, s1 = c.db().stash, old.db().stash
  local onlyNew = true
  for id in pairs(s1.collection) do
    if s0.collection[id] == nil and not (c.ns.Cards.byId[id] and not old.ns.Cards.byId[id]) then onlyNew = false end
  end
  check(s1.collection.newcard == s0.collection.newcard and diff(s0.decks, s1.decks) == nil and diff(s0.holo, s1.holo) == nil
    and onlyNew, "the previous version leaves the stash as it is, adding only the cards it doesn't know")
  local back = client(roundTrip(old.db()), nil, { beforeLoad = knowNewcard })
  local bdb = back.db()
  check(bdb.collection.newcard == 2 and back.C.IsHolo(bdb, "newcard") and #bdb.deck == 20 and bdb.deck[20] == "newcard",
    "after the previous version, a version that knows the card gets it all back")
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
