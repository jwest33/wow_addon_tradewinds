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
-- This is for friends and guildmates: plans travel in the open (anti-cheat
-- is not a goal), but the other side's plan is never shown before you have
-- locked in yours.
--
-- Messages are "TYPE;field;field...", well under the 255-byte limit:
--   CH;nonce;proto;rules;cards;version   a challenge
--   CX;nonce                             the challenger withdrew it
--   NO;nonce;reason;version              no: busy | declined | version | timeout | deck
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

local N = {}
ns.Net = N

N.PREFIX = "Deckhand"
N.PROTO = 1
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
local out      -- the challenge you sent: { name, nonce, at }
local inc      -- the one you got: { name, nonce, at, accepted, deck }
local resend = { round = 0 }  -- the plan being resent: round, step, at, acked
N.offline = false -- the opponent's whispers bounce ("No player named ...")

-- The running player-against-player match, if any.
local function match()
  local m = ns.db and ns.db.match
  return (m and m.pvp) and m or nil
end
N.Match = match

function N.Outgoing() return out and short(out.name) or nil end
function N.Incoming() return inc and short(inc.name) or nil end

-- What the board shows for the other player.
local opps = {}
function N.Opponent(name)
  local o = opps[name]
  if not o then
    local s = short(name)
    o = { id = "pvp", name = s, short = s, title = "Another player", level = "pvp", player = name,
      icon = { "Interface\\Icons\\Ability_Warrior_Challange", "Interface\\Icons\\INV_BannerPVP_01" } }
    opps[name] = o
  end
  return o
end

-- ---------------------------------------------------------------------------
-- Challenges
-- ---------------------------------------------------------------------------
function N.Challenge(name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then return false, "Type a player's name, or target them first." end
  if same(name, UnitName and UnitName("player")) then return false, "You can't challenge yourself." end
  if ns.db.match then return false, "Finish or end the match you're in first." end
  if out then return false, "You're already waiting for " .. short(out.name) .. " to answer." end
  if inc then return false, "Answer " .. short(inc.name) .. "'s challenge first." end
  local ok, why = ns.Collection.CheckDeck(ns.db)
  if not ok then return false, why .. " Fix it in the Cards tab." end
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
  if ns.db.match then return false, "Finish or end the match you're in first." end
  local ok, why = ns.Collection.CheckDeck(ns.db)
  if not ok then
    send(c.name, "NO", c.nonce, "deck", ns.VERSION)
    inc = nil
    refresh()
    return false, why .. " Fix it in the Cards tab."
  end
  c.accepted, c.at, c.deck = true, now(), {}
  for i, id in ipairs(ns.db.deck) do c.deck[i] = id end
  send(c.name, "OK", c.nonce, N.EncodeDeck(c.deck))
  refresh()
  return true
end

local function begin(name, gid, seed, host, mine, theirs)
  local st = ns.Rules.NewGame({ seed = seed, decks = { mine, theirs }, seats = host and { 1, 2 } or { 2, 1 },
    names = { UnitName and UnitName("player") or "You", short(name) } })
  resend = { round = 0 }
  N.offline = false
  game().StartPvP({ name = name, gid = gid, host = host, mine = {}, theirs = {}, sums = {}, theirSums = {} }, st)
end

-- ---------------------------------------------------------------------------
-- Rounds
-- ---------------------------------------------------------------------------
-- You locked in: send the plan, and play the round if theirs is here.
function N.LockIn(plan)
  local m = match()
  if not m then return end
  local r = m.st.round
  local s = N.EncodePlan(plan)
  m.pvp.mine[r] = s
  send(m.pvp.name, "PL", m.pvp.gid, r, s, m.pvp.theirs[r] and "!" or "?")
  resend = { round = r, step = 1, at = now() + N.RESEND[1] }
  N.TryPlay()
end

function N.Waiting()
  local m = match()
  return (m and not m.st.winner and m.pvp.mine[m.st.round] and not m.pvp.theirs[m.st.round]) and true or false
end

function N.TheyLockedIn()
  local m = match()
  return (m and m.pvp.theirs[m.st.round] and not m.pvp.mine[m.st.round]) and true or false
end

-- Both plans in and the board free: play the round.
function N.TryPlay()
  local m = match()
  if not m or m.st.winner then return end
  local r = m.st.round
  local a, b = m.pvp.mine[r], m.pvp.theirs[r]
  if not (a and b) or not game().PvPReady() then return end
  local mine, theirs = N.DecodePlan(m.st, 1, a), N.DecodePlan(m.st, 2, b)
  if not (mine and theirs) then
    N.Abort("Your games went out of step (a plan didn't fit the hand), so the match was ended without a result.")
    return
  end
  game().PlayPvPRound(mine, theirs)
end

local function prune(t, r)
  for k in pairs(t) do
    if k <= r - N.KEEP_ROUNDS then t[k] = nil end
  end
end

local function compare(m, r)
  local a, b = m.pvp.sums[r], m.pvp.theirSums[r]
  if a and b and a ~= b then
    N.Abort("Your games went out of step after round " .. r .. ", so the match was ended without a result. " ..
      "Please report it.")
  end
end

-- After a round has been played (the game has moved on to the next one).
function N.AfterRound(m, r)
  local sum = ns.Rules.Checksum(m.st)
  m.pvp.sums[r] = sum
  send(m.pvp.name, "SU", m.pvp.gid, r, sum)
  for _, t in ipairs({ m.pvp.mine, m.pvp.theirs, m.pvp.sums, m.pvp.theirSums }) do prune(t, r) end
  compare(m, r)
end

-- You ended the match: it's theirs.
function N.Concede(m)
  send(m.pvp.name, "EN", m.pvp.gid, "concede")
end

-- Something is wrong with the match: end it on both sides, with no result.
function N.Abort(why)
  local m = match()
  if not m then return end
  send(m.pvp.name, "EN", m.pvp.gid, "gone")
  game().PvPAbort(why)
end

-- A finished match is remembered until the next one, so that a late resend
-- from the other side still gets its answer.
function N.Finished(m, conceded)
  ns.db.pvpLast = { gid = m.pvp.gid, name = m.pvp.name, mine = m.pvp.mine, conceded = conceded or nil }
end

-- ---------------------------------------------------------------------------
-- Incoming messages
-- ---------------------------------------------------------------------------
local H = {}

local REASONS = {
  busy = "%s is busy: in a match, or answering another challenge.",
  declined = "%s declined your challenge.",
  version = "%s has a different version of Deckhand (%s). You both need the same one.",
  timeout = "%s didn't answer your challenge.",
  deck = "%s's deck isn't ready, so the game can't start.",
}

function H.CH(sender, nonce, proto, rules, cards, version)
  if tonumber(proto) ~= N.PROTO or tonumber(rules) ~= ns.Rules.RULES_VERSION or cards ~= N.CardSum() then
    send(sender, "NO", nonce, "version", ns.VERSION)
    ns.Print("%s challenged you, but you have different versions of Deckhand (theirs %s, yours %s). You both need the same one.",
      short(sender), tostring(version), ns.VERSION)
    return
  end
  if ns.db.match or out or (inc and not same(inc.name, sender)) or (inc and inc.accepted) then
    send(sender, "NO", nonce, "busy", ns.VERSION)
    if ns.db.match and not out and not inc then
      ns.Print("%s challenged you to Deckhand, but you're in a match. End it (/deckhand end) and ask them again.", short(sender))
    end
    return
  end
  inc = { name = sender, nonce = nonce, at = now() }
  game().OnChallenge(short(sender))
end

function H.CX(sender, nonce)
  if inc and same(inc.name, sender) and inc.nonce == nonce then
    inc = nil
    game().OnChallengeGone(short(sender) .. " withdrew the challenge.")
  end
end

function H.NO(sender, nonce, reason, version)
  if out and same(out.name, sender) and out.nonce == nonce then
    out = nil
    ns.Print(REASONS[reason] or "%s can't play right now.", short(sender), tostring(version))
    refresh()
  end
end

function H.OK(sender, nonce, deck)
  if not (out and same(out.name, sender) and out.nonce == nonce) then return end
  out = nil
  local theirs = N.DecodeDeck(deck)
  if not theirs or ns.db.match or not ns.Collection.CheckDeck(ns.db) then
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
  if not (theirs and s) or ns.db.match then
    send(sender, "EN", nonce, "gone")
    refresh()
    return
  end
  begin(sender, nonce, s, false, mine, theirs)
end

-- A message about a game we don't have: answer from the last finished one,
-- or say it's gone.
local function noGame(sender, gid, r)
  local last = ns.db.pvpLast
  if last and last.gid == gid and same(last.name, sender) then
    if last.conceded then send(sender, "EN", gid, "concede") return end
    local s = r and last.mine and last.mine[r]
    if s then send(sender, "PL", gid, r, s, "!") end
    return
  end
  send(sender, "EN", gid, "gone")
end

local function ours(sender, gid)
  local m = match()
  return (m and m.pvp.gid == gid and same(m.pvp.name, sender)) and m or nil
end

function H.PL(sender, gid, round, plan, need)
  local r = tonumber(round)
  local m = ours(sender, gid)
  if not m then
    if need == "?" then noGame(sender, gid, r) end
    return
  end
  if not r then return end
  local st = m.st
  if r < st.round then
    -- they're behind: our plan for that round never reached them
    local s = m.pvp.mine[r]
    if s and need == "?" then send(sender, "PL", gid, r, s, "!") end
    return
  end
  if r > st.round + 1 then return end
  local new = not m.pvp.theirs[r]
  if new then m.pvp.theirs[r] = plan end
  if not m.pvp.mine[r] then send(sender, "AK", gid, r) end
  N.TryPlay()
  refresh()
  -- they're waiting for you and the window is closed: say so
  if new and r == m.st.round and not m.pvp.mine[r] and ns.UI.IsShown and not ns.UI.IsShown() then
    ns.UI.Toast("pvp", short(sender) .. " has locked in. Your move.")
  end
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
  if s then send(sender, "PL", gid, r, s, m.pvp.theirs[r] and "!" or "?") end
end

function H.AK(sender, gid, round)
  local m = ours(sender, gid)
  if m and tonumber(round) == resend.round then resend.acked = true end
  refresh()
end

function H.EN(sender, gid, reason)
  if not ours(sender, gid) then return end
  if reason == "concede" then
    game().PvPConceded()
  else
    game().PvPAbort(short(sender) .. "'s side of the match is gone, so it was ended without a result.")
  end
end

function N.Receive(sender, text)
  if type(text) ~= "string" then return end
  local f = {}
  for part in (text .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
  local h = H[f[1]]
  if not h or same(sender, UnitName and UnitName("player")) then return end
  N.offline = false
  h(sender, unpack(f, 2))
end

-- ---------------------------------------------------------------------------
-- Every second: timeouts and resends
-- ---------------------------------------------------------------------------
function N.Tick()
  local t = now()
  if out and t - out.at > N.ANSWER_SECONDS + 5 then
    ns.Print("%s didn't answer. They need to be online, with the same version of Deckhand.", short(out.name))
    out = nil
    refresh()
  end
  if inc and not inc.accepted and t - inc.at > N.ANSWER_SECONDS then
    send(inc.name, "NO", inc.nonce, "timeout", ns.VERSION)
    inc = nil
    game().OnChallengeGone(nil)
  elseif inc and inc.accepted and t - inc.at > 30 then
    ns.Print("%s didn't start the game.", short(inc.name))
    inc = nil
    refresh()
  end
  local m = match()
  if m and not m.st.winner then
    local r = m.st.round
    if m.pvp.mine[r] and not m.pvp.theirs[r] then
      if resend.round ~= r then resend = { round = r, step = 1, at = t + N.RESEND[1] } end
      if t >= resend.at and not resend.acked then
        send(m.pvp.name, "PL", m.pvp.gid, r, m.pvp.mine[r], "?")
        resend.step = math.min(resend.step + 1, #N.RESEND)
        resend.at = t + N.RESEND[resend.step]
      end
    end
    N.TryPlay()
  end
end

-- "No player named X is currently playing." after whispering the opponent:
-- shown once as a note on the board instead of every resend.
local function filter(_, _, msg)
  local m = match()
  local target = (m and m.pvp.name) or (out and out.name)
  local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
  if not (target and fmt and type(msg) == "string") then return false end
  if msg ~= fmt:format(target) and msg ~= fmt:format(short(target)) then return false end
  if out and not m then
    ns.Print("%s isn't online.", short(out.name))
    out = nil
    refresh()
    return true
  end
  if not N.offline then
    N.offline = true
    refresh()
  end
  return true
end

function N.Init()
  local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  if reg then pcall(reg, N.PREFIX) end
  ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix == N.PREFIX and channel == "WHISPER" then N.Receive(sender, text) end
  end)
  if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter) end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, N.Tick) end
  -- back from a reload or a logout in the middle of a match
  local m = match()
  if m and not m.st.winner then
    local r = m.st.round
    send(m.pvp.name, "HI", m.pvp.gid, r)
    if m.pvp.mine[r] then send(m.pvp.name, "PL", m.pvp.gid, r, m.pvp.mine[r], m.pvp.theirs[r] and "!" or "?") end
  end
end
