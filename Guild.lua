-- The guild board: guildmates who have Tradewinds tell each other how far
-- they've got, over Net.lua's addon prefix on the guild channel:
--   LB;version;stars;heroic;owned;total;points;pvpWins   my progress
--   LQ                                                  please send yours
-- LB goes out 5-30 s after login, then at most once a minute while one of
-- its numbers changes, and in answer to an LQ. LQ goes out when the guild
-- board is opened, at most once every 5 minutes. With the "Share progress
-- with my guild" option off, Tradewinds sends neither and answers nothing
-- (what others send is still shown). Older versions only listen to
-- whispers, so they never see these.
--
-- What arrives is checked field by field (it comes from other clients) and
-- kept in db.guildBoard by sender, with the time it was seen; names not seen
-- for 30 days are dropped, and the board keeps at most 200.
local _, ns = ...
local N, C = ns.Net, ns.Collection

local Gd = {}
ns.Guild = Gd

Gd.FIRST = { 5, 30 }   -- seconds after login before the first LB
Gd.EVERY = 60          -- at most one LB a minute while numbers change
Gd.ASK_EVERY = 300     -- at most one LQ every 5 minutes
Gd.ANSWER = { 1, 4 }   -- seconds before answering an LQ (so answers don't all arrive at once)
Gd.ANSWER_GAP = 10     -- no answer if an LB went out this recently anyway
Gd.KEEP_DAYS = 30
Gd.MAX = 200
-- the largest number each field may hold
Gd.FIELDS = { { "stars", 999 }, { "heroic", 99 }, { "owned", 9999 }, { "total", 9999 }, { "points", 99999 }, { "pvp", 999999 } }

local first, sentAt, sent, askedAt, answerAt, checkAt

local function now() return GetTime and GetTime() or 0 end
local function clock() return time and time() or 0 end

local function board() return (ns.db and ns.db.guildBoard) or {} end

function Gd.InGuild()
  if not IsInGuild then return false end
  local ok, yes = pcall(IsInGuild)
  return ok and yes and true or false
end

-- Sharing on, and in a guild.
function Gd.Sharing()
  return (ns.db and ns.db.settings.guildShare and Gd.InGuild()) and true or false
end

-- Your own numbers, as LB sends them.
function Gd.Mine(db)
  db = db or ns.db
  local stars, heroic, owned = 0, 0, 0
  for _, o in ipairs(ns.Opponents) do
    stars = stars + select(2, C.Stars(db, o.id))
    if db.heroic[o.id] and db.heroic[o.id].beaten then heroic = heroic + 1 end
  end
  for _, c in ipairs(ns.Cards.collectible) do
    if C.Owned(db, c.id) > 0 then owned = owned + 1 end
  end
  return { v = ns.VERSION, stars = stars, heroic = heroic, owned = owned, total = #ns.Cards.collectible,
    points = (C.AchPoints(db)), pvp = ns.PvPWins(db) }
end

function Gd.Encode(t)
  local out = { "LB", t.v }
  for _, f in ipairs(Gd.FIELDS) do out[#out + 1] = t[f[1]] end
  return table.concat(out, ";")
end

local function sendLB(msg)
  msg = msg or Gd.Encode(Gd.Mine())
  N.SendGuild(msg)
  sent, sentAt = msg, now()
end

-- ---------------------------------------------------------------------------
-- What arrives
-- ---------------------------------------------------------------------------
local function count(s, max)
  if type(s) ~= "string" or not s:match("^%d+$") or #s > 7 then return nil end
  local n = tonumber(s)
  return (n and n <= max) and n or nil
end

-- Drops names not seen for KEEP_DAYS, then the longest unseen past MAX.
function Gd.Prune()
  local b = board()
  local cutoff = clock() - Gd.KEEP_DAYS * 86400
  local names = {}
  for name, e in pairs(b) do
    if type(name) ~= "string" or type(e) ~= "table" or type(e.seen) ~= "number" or e.seen < cutoff then
      b[name] = nil
    else
      names[#names + 1] = name
    end
  end
  if #names > Gd.MAX then
    table.sort(names, function(x, y) return b[x].seen > b[y].seen end)
    for i = Gd.MAX + 1, #names do b[names[i]] = nil end
  end
end

local function changed()
  if ns.UI and ns.UI.Records and ns.UI.Records.Changed then ns.UI.Records.Changed() end
end

function Gd.OnLB(sender, v, ...)
  if type(sender) ~= "string" or #sender > 64 or not sender:match("^[^%s;|]+$") then return end
  if type(v) ~= "string" or #v > 24 or not v:match("^[%w%.%-]+$") then return end
  local e = { v = v }
  local fields = { ... }
  for i, f in ipairs(Gd.FIELDS) do
    local n = count(fields[i], f[2])
    if not n then return end
    e[f[1]] = n
  end
  if e.owned > e.total then return end
  e.seen = clock()
  local b = board()
  local isNew = b[sender] == nil
  b[sender] = e
  if isNew then Gd.Prune() end
  changed()
  if isNew then ns.CheckAchievements() end
end

function Gd.OnLQ()
  if not Gd.Sharing() or answerAt then return end
  if sentAt and now() - sentAt < Gd.ANSWER_GAP then return end
  answerAt = now() + math.random(Gd.ANSWER[1], Gd.ANSWER[2])
end

-- Asks guildmates for their numbers (the guild board was opened), and the
-- game for the guild roster (who's online).
function Gd.Ask()
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
  if not Gd.Sharing() then return false end
  local t = now()
  if askedAt and t - askedAt < Gd.ASK_EVERY then return false end
  askedAt = t
  N.SendGuild("LQ")
  return true
end

-- ---------------------------------------------------------------------------
-- The roster: who's online (nil when the game hasn't said)
-- ---------------------------------------------------------------------------
local roster, rosterAt

local function readRoster()
  local t = now()
  if roster and rosterAt and t - rosterAt < 2 then return roster end
  roster, rosterAt = {}, t
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return roster end
  local ok, total = pcall(GetNumGuildMembers)
  if not ok or type(total) ~= "number" then return roster end
  for i = 1, math.min(total, 1000) do
    local got, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
    if got and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
      roster[N.Short(name):lower()] = online and true or false
    end
  end
  return roster
end

function Gd.Online(name)
  return readRoster()[N.Short(name):lower()]
end

-- The board as rows: { name, short, v, stars, heroic, owned, total, points,
-- pvp, seen, online, you }, you included. sortKey: a field (name by default);
-- desc: highest first.
function Gd.Rows(sortKey, desc)
  Gd.Prune()
  local rows = {}
  local me = UnitName and UnitName("player") or "?"
  for name, e in pairs(board()) do
    if not N.Same(name, me) then
      local r = { name = name, short = (Ambiguate and Ambiguate(name, "guild")) or N.Short(name), online = Gd.Online(name) }
      for k, x in pairs(e) do r[k] = x end
      rows[#rows + 1] = r
    end
  end
  if ns.db then
    local you = Gd.Mine()
    you.name, you.short, you.you, you.online, you.seen = me, me, true, true, clock()
    rows[#rows + 1] = you
  end
  sortKey = sortKey or "name"
  table.sort(rows, function(a, b)
    local x, y = a[sortKey], b[sortKey]
    if sortKey == "name" or sortKey == "short" then x, y = a.short:lower(), b.short:lower() end
    if x ~= y then
      if desc then return x > y end
      return x < y
    end
    return a.short:lower() < b.short:lower()
  end)
  return rows
end

-- Can you start a game or a trade with this row's player now?
function Gd.CanPlay(r)
  return (not r.you and r.online and r.v == ns.VERSION) and true or false
end

-- ---------------------------------------------------------------------------
-- Every second (Net.lua's ticker)
-- ---------------------------------------------------------------------------
function Gd.Tick()
  if not Gd.Sharing() then return end
  local t = now()
  if answerAt and t >= answerAt then
    answerAt = nil
    sendLB()
    return
  end
  if not first or t < first then return end
  if sentAt and t - sentAt < Gd.EVERY then return end
  -- your numbers are worked out every few seconds, not every second
  if checkAt and t < checkAt then return end
  checkAt = t + 5
  local msg = Gd.Encode(Gd.Mine())
  if msg ~= sent then sendLB(msg) end
end

function Gd.Init()
  first = now() + math.random(Gd.FIRST[1], Gd.FIRST[2])
  N.Handle("LB", Gd.OnLB)
  N.Handle("LQ", Gd.OnLQ)
  ns.On("GUILD_ROSTER_UPDATE", function()
    rosterAt = nil
    changed()
  end)
  Gd.Prune()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, Gd.Tick) end
end

-- For the tests: forget what was sent and asked.
function Gd.Reset()
  first, sentAt, sent, askedAt, answerAt, checkAt, roster, rosterAt = nil, nil, nil, nil, nil, nil, nil, nil
end
