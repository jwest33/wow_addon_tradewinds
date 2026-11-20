-- Player against player, over addon whispers.
--
-- Both clients run the same game: the rules engine is deterministic and each
-- side plays as its own player 1 (see R.Seats). The challenger picks the seed,
-- each side sends its plan when it locks in, and a client plays the round as
-- soon as it has both plans. After every round both send a checksum of the
-- game, to catch the two copies drifting apart. A plan that hasn't been
-- answered is sent again, less and less often, so a /reload or a short
-- disconnect on either side doesn't lose it.
--
-- Several games can run at once (one per opponent, beside your match against
-- the computer), each at its own pace: a round plays out whenever both plans
-- have arrived, on screen or not.
--
-- This is for friends and guildmates: plans travel in the open (anti-cheat
-- is not a goal), but the other side's plan is never shown before you have
-- locked in yours.
--
-- Messages are "TYPE;field;field...", well under the 255-byte limit:
--   CH;nonce;proto;rules;cards;version   a challenge
--   CX;nonce                             the challenger withdrew it
--   NO;nonce;reason;version              no: busy | declined | version | timeout |
--                                        deck | already | full
--   OK;nonce;deck                        yes, with the accepting side's deck
--   GO;nonce;seed;deck                   the game starts (the challenger's deck)
--   PL;game;round;plan;need              a locked-in plan; need is "?" if the
--                                        sender still needs yours for that
--                                        round (only those are answered, so
--                                        two clients never echo each other)
--   AK;game;round                        got your plan (stop resending it)
--   SU;game;round;checksum               the game after that round
--   HI;game;round                        back after a reload: please resend
--   EN;game;reason                       concede | gone (no such game here)
local _, ns = ...
local L = ns.L

local N = {}
ns.Net = N

N.PREFIX = "Tradewinds"
N.PROTO = 2
N.ANSWER_SECONDS = 60         -- how long a challenge waits for an answer
N.RESEND = { 5, 15, 45, 120 } -- seconds between resends of an unanswered plan
N.KEEP_ROUNDS = 3             -- plans and checksums kept for resending

local function refresh()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function game() return ns.UI and ns.UI.Game end

local function now() return GetTime and GetTime() or 0 end

-- Names arrive as "Name-Realm"; players type "Name".
local function short(name)
  return (type(name) == "string" and name:match("^[^%-]+")) or tostring(name or "?")
end
N.Short = short

local function same(a, b)
  return type(a) == "string" and type(b) == "string" and short(a):lower() == short(b):lower()
end
N.Same = same

local function send(target, ...)
  local msg = table.concat({ ... }, ";")
  local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if api then pcall(api, N.PREFIX, msg, "WHISPER", target) end
end

-- ---------------------------------------------------------------------------
-- Cards and plans on the wire
-- ---------------------------------------------------------------------------
-- A card is two base-36 characters: its place in the sorted list of
-- collectible ids. Both sides need the same cards, which the challenge checks
-- (N.CardSum).
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local codeOf, idOf

local function codes()
  if codeOf then return end
  local ids = {}
  for _, c in ipairs(ns.Cards.collectible) do ids[#ids + 1] = c.id end
  table.sort(ids)
  codeOf, idOf = {}, {}
  for i, id in ipairs(ids) do
    local a, b = math.floor((i - 1) / 36) + 1, (i - 1) % 36 + 1
    local code = DIGITS:sub(a, a) .. DIGITS:sub(b, b)
    codeOf[id], idOf[code] = code, id
  end
end

function N.EncodeDeck(list)
  codes()
  local out = {}
  for i, id in ipairs(list) do out[i] = codeOf[id] or "??" end
  return table.concat(out)
end

-- The deck, or nil unless it's exactly a deck's worth of known cards.
function N.DecodeDeck(s)
  codes()
  if type(s) ~= "string" or #s ~= ns.Rules.DECK_SIZE * 2 then return nil end
  local out = {}
  for i = 1, #s, 2 do
    local id = idOf[s:sub(i, i + 1)]
    if not id then return nil end
    out[#out + 1] = id
  end
  return out
end

-- A fingerprint of the card list.
function N.CardSum()
  codes()
  local ids = {}
  for id in pairs(codeOf) do ids[#ids + 1] = id end
  table.sort(ids)
  local s = table.concat(ids, ",")
  local h = 7
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return ("%x"):format(h)
end

-- "hand.lane,hand.lane" (lane 0: no target), "-" for a plan with no cards.
function N.EncodePlan(plan)
  if #plan == 0 then return "-" end
  local out = {}
  for i, a in ipairs(plan) do out[i] = a.h .. "." .. (a.lane or 0) end
  return table.concat(out, ",")
end

-- The plan for player p, or nil if it isn't a legal plan for their hand.
function N.DecodePlan(st, p, s)
  if s == "-" then return {} end
  if type(s) ~= "string" then return nil end
  local plan = {}
  for part in s:gmatch("[^,]+") do
    local h, l = part:match("^(%d+)%.(%d+)$")
    h, l = tonumber(h), tonumber(l)
    local id = h and st.players[p].hand[h]
    if not id then return nil end
    plan[#plan + 1] = { h = h, id = id, lane = (l and l > 0) and l or nil }
  end
  if not ns.Rules.CheckPlan(st, p, plan) then return nil end
  return plan
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
-- Games live in ns.db.games, by game id (one per opponent, at most
-- Collection.MAX_GAMES); your match against the computer is separate.
local out      -- the challenge you sent: { name, nonce, at }
local inc      -- the one you got: { name, nonce, at, accepted, deck }
local resends = {}  -- per game id: the plan being resent { round, step, at, acked }
local offline = {}  -- per opponent (lower-case short name): their whispers bounce

local function games() return (ns.db and ns.db.games) or {} end

local function count()
  local n = 0
  for _ in pairs(games()) do n = n + 1 end
  return n
end

-- Your game with that player, if any.
function N.GameWith(name)
  for _, m in pairs(games()) do
    if same(m.pvp.name, name) then return m end
  end
end

function N.Outgoing() return out and short(out.name) or nil end
function N.Incoming() return inc and short(inc.name) or nil end

function N.IsOffline(m)
  return (m and offline[short(m.pvp.name):lower()]) and true or false
end

-- What the board shows for the other player.
local opps = {}
function N.Opponent(name)
  local o = opps[name]
  if not o then
    local s = short(name)
    o = { id = "pvp", name = s, short = s, title = L["Another player"], level = "pvp", player = name,
      icon = { "Interface\\Icons\\Ability_Warrior_Challange", "Interface\\Icons\\INV_BannerPVP_01" } }
    opps[name] = o
  end
  return o
end

-- Can a game with `name` start? Returns false and why not.
local function room(name)
  if N.GameWith(name) then return false, L["You already have a game going with %s."]:format(short(name)) end
  if count() >= ns.Collection.MAX_GAMES then
    return false, (L["You have %d games going against players. Finish one first."]):format(ns.Collection.MAX_GAMES)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Challenges
-- ---------------------------------------------------------------------------
function N.Challenge(name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then return false, L["Type a player's name, or target them first."] end
  if same(name, UnitName and UnitName("player")) then return false, L["You can't challenge yourself."] end
  local ok, why = room(name)
  if not ok then return false, why end
  if out then return false, L["You're already waiting for %s to answer."]:format(short(out.name)) end
  if inc then return false, L["Answer %s's challenge first."]:format(short(inc.name)) end
  ok, why = ns.Collection.CheckDeck(ns.db)
  if not ok then return false, L["%s Fix it in the Cards tab."]:format(why) end
  out = { name = name, nonce = tostring(math.random(100000000, 999999999)), at = now() }
  send(name, "CH", out.nonce, N.PROTO, ns.Rules.RULES_VERSION, N.CardSum(), ns.VERSION)
  refresh()
  return true
end

function N.Cancel()
  if not out then return end
  send(out.name, "CX", out.nonce)
  out = nil
  refresh()
end

-- Your answer to the challenge you got. Returns false and a reason if you
-- can't accept it.
function N.Answer(accept)
  local c = inc
  if not c or c.accepted then return false end
  if not accept then
    send(c.name, "NO", c.nonce, "declined", ns.VERSION)
    inc = nil
    refresh()
    return true
  end
  local ok, why = room(c.name)
  if ok then ok, why = ns.Collection.CheckDeck(ns.db) end
  if not ok then
    send(c.name, "NO", c.nonce, "deck", ns.VERSION)
    inc = nil
    refresh()
    return false, why
  end
  c.accepted, c.at, c.deck = true, now(), {}
  for i, id in ipairs(ns.db.deck) do c.deck[i] = id end
  send(c.name, "OK", c.nonce, N.EncodeDeck(c.deck))
  refresh()
  return true
end

local function begin(name, gid, seed, host, mine, theirs)
  local st = ns.Rules.NewGame({ seed = seed, decks = { mine, theirs }, seats = host and { 1, 2 } or { 2, 1 },
    names = { UnitName and UnitName("player") or L["You"], short(name) } })
  resends[gid] = nil
  offline[short(name):lower()] = nil
  game().StartPvP({ name = name, gid = gid, host = host, mine = {}, theirs = {}, sums = {}, theirSums = {} }, st)
end

-- ---------------------------------------------------------------------------
-- Rounds
-- ---------------------------------------------------------------------------
local function need(m, r) return m.pvp.theirs[r] and "!" or "?" end

-- You locked in your plan for game m: send it, and play the round if theirs
-- is here.
function N.LockIn(m, plan)
  local r = m.st.round
  local s = N.EncodePlan(plan)
  m.pvp.mine[r] = s
  send(m.pvp.name, "PL", m.pvp.gid, r, s, need(m, r))
  resends[m.pvp.gid] = { round = r, step = 1, at = now() + N.RESEND[1] }
  N.TryPlay(m)
end

-- You've locked in and wait for them.
function N.Waiting(m)
  return (m and m.pvp and not m.st.winner and m.pvp.mine[m.st.round] and not m.pvp.theirs[m.st.round]) and true or false
end

-- They've locked in and wait for you.
function N.TheyLockedIn(m)
  return (m and m.pvp and not m.st.winner and m.pvp.theirs[m.st.round] and not m.pvp.mine[m.st.round]) and true or false
end

-- Both plans in (and the board free, if the game is on it): play the round.
function N.TryPlay(m)
  if not m or not m.pvp or m.st.winner or ns.db.games[m.pvp.gid] ~= m then return end
  local r = m.st.round
  local a, b = m.pvp.mine[r], m.pvp.theirs[r]
  if not (a and b) or not game().PvPReady(m) then return end
  local mine, theirs = N.DecodePlan(m.st, 1, a), N.DecodePlan(m.st, 2, b)
  if not (mine and theirs) then
    N.Abort(m, L["Your game with %s went out of step (a plan didn't fit the hand), so it was ended without a result."]:format(
      short(m.pvp.name)))
    return
  end
  game().PlayPvPRound(m, mine, theirs)
end

local function prune(t, r)
  for k in pairs(t) do
    if k <= r - N.KEEP_ROUNDS then t[k] = nil end
  end
end

local function compare(m, r)
  local a, b = m.pvp.sums[r], m.pvp.theirSums[r]
  if a and b and a ~= b then
    N.Abort(m, L["Your game with %s went out of step after round %d, so it was ended without a result. Please report it."]:format(
      short(m.pvp.name), r))
  end
end

-- After a round of game m has been played (it has moved on to the next one).
function N.AfterRound(m, r)
  local sum = ns.Rules.Checksum(m.st)
  m.pvp.sums[r] = sum
  send(m.pvp.name, "SU", m.pvp.gid, r, sum)
  for _, t in ipairs({ m.pvp.mine, m.pvp.theirs, m.pvp.sums, m.pvp.theirSums }) do prune(t, r) end
  compare(m, r)
end

-- You ended game m: it's theirs.
function N.Concede(m)
  send(m.pvp.name, "EN", m.pvp.gid, "concede")
end

-- Something is wrong with game m: end it on both sides, with no result.
function N.Abort(m, why)
  if not (m and ns.db.games[m.pvp.gid] == m) then return end
  send(m.pvp.name, "EN", m.pvp.gid, "gone")
  game().PvPAbort(m, why)
end

-- Finished games are remembered for a while (the last 10), so that a late
-- resend from the other side still gets its answer.
N.KEEP_FINISHED = 10
function N.Finished(m, conceded)
  local done = ns.db.pvpDone or {}
  ns.db.pvpDone = done
  done[m.pvp.gid] = { name = m.pvp.name, mine = m.pvp.mine, conceded = conceded or nil, at = time and time() or 0 }
  local ids = {}
  for gid in pairs(done) do ids[#ids + 1] = gid end
  if #ids > N.KEEP_FINISHED then
    table.sort(ids, function(a, b) return (done[a].at or 0) < (done[b].at or 0) end)
    for i = 1, #ids - N.KEEP_FINISHED do done[ids[i]] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Incoming messages
-- ---------------------------------------------------------------------------
local H = {}

local REASONS = {
  busy = L["%s is busy answering another challenge. Try again in a minute."],
  declined = L["%s declined your challenge."],
  version = L["%s has a different version of Tradewinds (%s). You both need the same one."],
  timeout = L["%s didn't answer your challenge."],
  deck = L["%s can't start a game right now (their deck isn't ready, or they have too many games going)."],
  already = L["You already have a game going with %s."],
  full = L["%s has too many games going. They need to finish one first."],
}

function H.CH(sender, nonce, proto, rules, cards, version)
  if tonumber(proto) ~= N.PROTO or tonumber(rules) ~= ns.Rules.RULES_VERSION or cards ~= N.CardSum() then
    send(sender, "NO", nonce, "version", ns.VERSION)
    ns.Print(L["%s challenged you, but you have different versions of Tradewinds (theirs %s, yours %s). You both need the same one."],
      short(sender), tostring(version), ns.VERSION)
    return
  end
  if N.GameWith(sender) then send(sender, "NO", nonce, "already", ns.VERSION) return end
  if count() >= ns.Collection.MAX_GAMES then
    send(sender, "NO", nonce, "full", ns.VERSION)
    ns.Print(L["%s challenged you to Tradewinds, but you have %d games going against players. Finish one first."],
      short(sender), ns.Collection.MAX_GAMES)
    return
  end
  if out or (inc and not same(inc.name, sender)) or (inc and inc.accepted) then
    send(sender, "NO", nonce, "busy", ns.VERSION)
    return
  end
  inc = { name = sender, nonce = nonce, at = now() }
  game().OnChallenge(short(sender))
end

function H.CX(sender, nonce)
  if inc and same(inc.name, sender) and inc.nonce == nonce then
    inc = nil
    game().OnChallengeGone(L["%s withdrew the challenge."]:format(short(sender)))
  end
end

function H.NO(sender, nonce, reason, version)
  if out and same(out.name, sender) and out.nonce == nonce then
    out = nil
    ns.Print(REASONS[reason] or L["%s can't play right now."], short(sender), tostring(version))
    refresh()
  end
end

function H.OK(sender, nonce, deck)
  if not (out and same(out.name, sender) and out.nonce == nonce) then return end
  out = nil
  local theirs = N.DecodeDeck(deck)
  if not theirs or not room(sender) or not ns.Collection.CheckDeck(ns.db) then
    send(sender, "NO", nonce, theirs and "busy" or "version", ns.VERSION)
    refresh()
    return
  end
  local seed = math.random(1, 2147483646)
  local mine = {}
  for i, id in ipairs(ns.db.deck) do mine[i] = id end
  send(sender, "GO", nonce, seed, N.EncodeDeck(mine))
  begin(sender, nonce, seed, true, mine, theirs)
end

function H.GO(sender, nonce, seed, deck)
  if not (inc and inc.accepted and same(inc.name, sender) and inc.nonce == nonce) then return end
  local mine = inc.deck
  inc = nil
  local theirs, s = N.DecodeDeck(deck), tonumber(seed)
  if not (theirs and s) or not room(sender) then
    send(sender, "EN", nonce, "gone")
    refresh()
    return
  end
  begin(sender, nonce, s, false, mine, theirs)
end

-- A message about a game we don't have: answer from a finished one, or say
-- it's gone.
local function noGame(sender, gid, r)
  local last = ns.db.pvpDone and ns.db.pvpDone[gid]
  if last and same(last.name, sender) then
    if last.conceded then send(sender, "EN", gid, "concede") return end
    local s = r and last.mine and last.mine[r]
    if s then send(sender, "PL", gid, r, s, "!") end
    return
  end
  send(sender, "EN", gid, "gone")
end

local function ours(sender, gid)
  local m = games()[gid]
  return (m and same(m.pvp.name, sender)) and m or nil
end

function H.PL(sender, gid, round, plan, needs)
  local r = tonumber(round)
  local m = ours(sender, gid)
  if not m then
    if needs == "?" then noGame(sender, gid, r) end
    return
  end
  if not r then return end
  local st = m.st
  if r < st.round then
    -- they're behind: our plan for that round never reached them
    local s = m.pvp.mine[r]
    if s and needs == "?" then send(sender, "PL", gid, r, s, "!") end
    return
  end
  if r > st.round + 1 then return end
  local new = not m.pvp.theirs[r]
  if new then m.pvp.theirs[r] = plan end
  if not m.pvp.mine[r] then send(sender, "AK", gid, r) end
  N.TryPlay(m)
  refresh()
  -- they're waiting for you, and this game isn't in front of you: say so
  if new and r == m.st.round and not m.pvp.mine[r] then
    local shown = ns.UI.IsShown and ns.UI.IsShown() and game().Match() == m
    if not shown then
      if ns.UI.IsShown and not ns.UI.IsShown() then
        ns.UI.Toast("pvp", L["%s has locked in. Your move."]:format(short(sender)))
      else
        ns.Print(L["%s has locked in. Your move (the Your games list)."], short(sender))
      end
    end
  end
end

function H.AK(sender, gid, round)
  local m = ours(sender, gid)
  local rs = resends[gid]
  if m and rs and tonumber(round) == rs.round then rs.acked = true end
  refresh()
end

function H.SU(sender, gid, round, sum)
  local m = ours(sender, gid)
  local r = tonumber(round)
  if not (m and r) then return end
  m.pvp.theirSums[r] = sum
  compare(m, r)
end

function H.HI(sender, gid, round)
  local r = tonumber(round)
  local m = ours(sender, gid)
  if not m then noGame(sender, gid, r) return end
  local s = r and m.pvp.mine[r]
  if s then send(sender, "PL", gid, r, s, need(m, r)) end
end

function H.EN(sender, gid, reason)
  local m = ours(sender, gid)
  if not m then return end
  if reason == "concede" then
    game().PvPConceded(m)
  else
    game().PvPAbort(m, (L["%s's side of your game is gone, so it was ended without a result."]):format(short(sender)))
  end
end

function N.Receive(sender, text)
  if type(text) ~= "string" then return end
  local f = {}
  for part in (text .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
  local h = H[f[1]]
  if not h or same(sender, UnitName and UnitName("player")) then return end
  offline[short(sender):lower()] = nil
  h(sender, unpack(f, 2))
end

-- ---------------------------------------------------------------------------
-- Every second: timeouts, resends, rounds ready to play
-- ---------------------------------------------------------------------------
function N.Tick()
  local t = now()
  if out and t - out.at > N.ANSWER_SECONDS + 5 then
    ns.Print(L["%s didn't answer. They need to be online, with the same version of Tradewinds."], short(out.name))
    out = nil
    refresh()
  end
  if inc and not inc.accepted and t - inc.at > N.ANSWER_SECONDS then
    send(inc.name, "NO", inc.nonce, "timeout", ns.VERSION)
    inc = nil
    game().OnChallengeGone(nil)
  elseif inc and inc.accepted and t - inc.at > 30 then
    ns.Print(L["%s didn't start the game."], short(inc.name))
    inc = nil
    refresh()
  end
  for gid, m in pairs(games()) do
    if not m.st.winner then
      local r = m.st.round
      if m.pvp.mine[r] and not m.pvp.theirs[r] then
        local rs = resends[gid]
        if not rs or rs.round ~= r then
          rs = { round = r, step = 1, at = t + N.RESEND[1] }
          resends[gid] = rs
        end
        if t >= rs.at and not rs.acked then
          send(m.pvp.name, "PL", gid, r, m.pvp.mine[r], "?")
          rs.step = math.min(rs.step + 1, #N.RESEND)
          rs.at = t + N.RESEND[rs.step]
        end
      end
    end
  end
  for _, m in ipairs(ns.Collection.Games(ns.db)) do N.TryPlay(m) end
end

-- "No player named X is currently playing." after whispering an opponent:
-- noted on their game instead of shown on every resend.
local function filter(_, _, msg)
  local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
  if not (fmt and type(msg) == "string") then return false end
  local function bounced(name) return msg == fmt:format(name) or msg == fmt:format(short(name)) end
  if out and bounced(out.name) then
    ns.Print(L["%s isn't online."], short(out.name))
    out = nil
    refresh()
    return true
  end
  for _, m in pairs(games()) do
    if bounced(m.pvp.name) then
      local key = short(m.pvp.name):lower()
      if not offline[key] then
        offline[key] = true
        refresh()
      end
      return true
    end
  end
  return false
end

function N.Init()
  local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  if reg then pcall(reg, N.PREFIX) end
  ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix == N.PREFIX and channel == "WHISPER" then N.Receive(sender, text) end
  end)
  if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter) end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, N.Tick) end
  -- back from a reload or a logout: ask each opponent for what we missed
  for gid, m in pairs(games()) do
    if not m.st.winner then
      local r = m.st.round
      send(m.pvp.name, "HI", gid, r)
      if m.pvp.mine[r] then send(m.pvp.name, "PL", gid, r, m.pvp.mine[r], need(m, r)) end
    end
  end
end
