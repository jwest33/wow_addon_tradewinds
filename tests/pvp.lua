-- Player against player: two complete clients (each with its own WoW mock,
-- saved data and copy of the addon) in one Lua state, joined by a pretend
-- network that delivers whispers between them. The test plays whole matches
-- through the same functions the buttons call, loses messages, reloads a
-- client in the middle of a match, and checks that both copies of the game
-- stay identical.
local ROOT = ROOT or "."

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

math.randomseed(4242)

local network = {}   -- messages in flight: { to = name, from = full name, prefix, msg }
local clients = {}   -- by name
local drop = nil     -- function(msg, from, to) -> true to lose a message

-- A client: fresh mock and addon in their own global table. saved: the
-- TradewindsCharDB to start from (a /reload), or nil for a new character.
local function client(name, saved, locale)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  if locale then env.GetLocale = function() return locale end end
  local function run(path, ...)
    local f = assert(loadfile(ROOT .. "/" .. path))
    setfenv(f, env)
    return f(...)
  end
  run("tests/wowmock.lua")
  local M = env.MOCK
  M.playerName = name
  M.now = clients[name] and clients[name].MOCK.now or M.now
  env.TradewindsCharDB = saved
  local ns = {}
  for line in io.lines(ROOT .. "/Tradewinds.toc") do
    local file = line:match("^%s*([^#].-%.lua)%s*$")
    if file then run((file:gsub("\\", "/")), "Tradewinds", ns) end
  end
  M.onSend = function(prefix, msg, chatType, target)
    if chatType ~= "WHISPER" then return end
    if drop and drop(msg, name, target) then return end
    network[#network + 1] = { to = target:match("^[^%-]+"), from = name .. "-Realm", prefix = prefix, msg = msg }
  end
  M.Fire("ADDON_LOADED", "Tradewinds")
  M.Fire("PLAYER_LOGIN")
  M.Fire("PLAYER_ENTERING_WORLD")
  local c = { name = name, env = env, MOCK = M, ns = ns, G = ns.UI.Game, R = ns.Rules, C = ns.Collection }
  c.db = function() return env.TradewindsCharDB end
  clients[name] = c
  return c
end

-- Delivers what's in flight (and what that sets off) to whoever is online.
local function pump()
  for _ = 1, 50 do
    if #network == 0 then return end
    local batch = network
    network = {}
    for _, m in ipairs(batch) do
      local c = clients[m.to]
      if c and not c.offline then c.MOCK.Fire("CHAT_MSG_ADDON", m.prefix, m.msg, "WHISPER", m.from) end
    end
  end
end

-- Time passes on every client.
local function advance(sec, step)
  step = step or 0.5
  local t = 0
  while t < sec do
    for _, c in pairs(clients) do
      if not c.offline then c.MOCK.Advance(step) end
    end
    pump()
    t = t + step
  end
end

-- Plans every affordable card, by clicking, like tests/ui.lua does.
local function autoPlan(c)
  local G, st = c.G, c.G.Match().st
  local hand = st.players[1].hand
  for h = 1, #hand do
    local card = c.ns.Cards.byId[hand[h]]
    G.ClickHand(h, "LeftButton")
    if card.type == "unit" or card.target == "friend" then
      for l = 1, c.R.LANES do
        if G.Selected() then G.ClickSlot(1, l, "LeftButton") end
      end
    elseif card.target == "enemy" and G.Selected() then
      G.ClickSlot(2, (h % 4) + 1, "LeftButton")
    end
    if G.Selected() then G.ClickHand(h, "RightButton") end
  end
end

local function sum(c) return c.R.Checksum(c.G.Match().st) end
local function noGames(c) return c.G.Match() == nil and next(c.db().games) == nil end
local function lastChat(c) return c.MOCK.chat[#c.MOCK.chat] or "" end
local function chatHas(c, text)
  for _, line in ipairs(c.MOCK.chat) do if line:find(text, 1, true) then return true end end
  return false
end

local A, B = client("Alice"), client("Bob")
check(A.MOCK.prefix == "Tradewinds" and B.MOCK.prefix == "Tradewinds", "both clients register the addon message prefix")

-- a challenge declined -------------------------------------------------------------
do
  check(A.G.Challenge("Bob"), "Alice challenges Bob")
  check(not A.G.Challenge("Bob"), "only one challenge at a time")
  pump()
  check(B.MOCK.popup and B.MOCK.popup.name == "TRADEWINDS_CHALLENGE" and B.MOCK.popup.arg == "Alice",
    "Bob is asked, with Alice's name")
  B.G.AnswerChallenge(false)
  pump()
  check(A.ns.Net.Outgoing() == nil and chatHas(A, "Bob declined"), "declined: Alice is told")
end

-- withdrawn, and unanswered -----------------------------------------------------------
do
  A.G.Challenge("Bob")
  pump()
  A.ns.Net.Cancel()
  pump()
  check(B.ns.Net.Incoming() == nil and B.MOCK.popup == nil and chatHas(B, "withdrew"), "a withdrawn challenge closes Bob's popup")
  A.G.Challenge("Carol")   -- nobody by that name runs Tradewinds here
  advance(A.ns.Net.ANSWER_SECONDS + 6)
  check(A.ns.Net.Outgoing() == nil and chatHas(A, "Carol didn't answer"), "no answer: the challenge times out")
  A.G.Challenge("Bob")
  pump()
  advance(B.ns.Net.ANSWER_SECONDS + 2)
  check(B.ns.Net.Incoming() == nil and A.ns.Net.Outgoing() == nil and chatHas(A, "Bob didn't answer"),
    "an unanswered popup declines by itself")
  check(not A.G.Challenge("alice") and A.MOCK.errors[#A.MOCK.errors]:find("yourself"), "you can't challenge yourself")
end

-- a match against the computer is no reason to say no; a different version is
do
  B.G.Start("dorn")
  A.G.Challenge("Bob")
  pump()
  check(B.ns.Net.Incoming() == "Alice", "Bob, in a match against the computer, can still be challenged")
  B.G.AnswerChallenge(false)
  pump()
  B.G.EndMatch()
  B.G.Continue()
  local real = B.R.RULES_VERSION
  B.R.RULES_VERSION = real + 1
  A.G.Challenge("Bob")
  pump()
  check(A.ns.Net.Outgoing() == nil and chatHas(A, "different version") and chatHas(B, "different versions"),
    "different rules: both are told")
  B.R.RULES_VERSION = real
end

-- a match ---------------------------------------------------------------------------
local function startMatch(challenger, other)
  check(challenger.G.Challenge(other.name), challenger.name .. " challenges " .. other.name)
  pump()
  check(other.G.AnswerChallenge(true), other.name .. " accepts")
  pump()
  local ma, mb = challenger.G.Match(), other.G.Match()
  check(ma and mb and ma.pvp and mb.pvp and ma.pvp.gid == mb.pvp.gid, "the match starts on both sides")
  check(ma.pvp.host and not mb.pvp.host, "the challenger hosts")
  check(sum(challenger) == sum(other), "both copies of the game are identical at the start")
  return ma, mb
end

do
  local ma, mb = startMatch(A, B)
  local deckA = {}
  for _, id in ipairs(ma.st.players[1].deck) do deckA[#deckA + 1] = id end
  for _, id in ipairs(ma.st.players[1].hand) do deckA[#deckA + 1] = id end
  table.sort(deckA)
  local own = {}
  for i, id in ipairs(A.db().deck) do own[i] = id end
  table.sort(own)
  check(table.concat(deckA, ",") == table.concat(own, ","), "Alice plays her own deck")
  check(A.G.HeroicView() == false and A.ns.Net.Opponent(ma.pvp.name).short == "Bob", "the board shows Bob by name")

  local rounds, drifted = 0, 0
  while A.G.Match() and B.G.Match() and rounds < 12 do
    rounds = rounds + 1
    local r = A.G.Match().st.round
    if r == 3 then
      -- Alice's plan is lost on the way; she sends it again
      local lost = false
      drop = function(msg) if msg:find("^PL;") and not lost then lost = true; return true end end
    end
    autoPlan(A)
    A.G.LockIn()
    drop = nil
    check(A.G.Match().pvp.mine[r] ~= nil, "round " .. r .. ": Alice locked in")
    if r == 2 then
      check(A.ns.Net.Waiting(A.G.Match()), "Alice waits for Bob")
      A.G.LockIn()   -- nothing happens: already locked in
    end
    pump()
    if r == 3 then
      check(B.G.Match().pvp.theirs[r] == nil, "round 3: Alice's plan was lost")
      advance(6)
      check(B.G.Match().pvp.theirs[r] ~= nil, "round 3: and arrived when she sent it again")
    end
    if r ~= 3 then check(B.ns.Net.TheyLockedIn(B.G.Match()), "round " .. r .. ": Bob sees that Alice has locked in") end
    autoPlan(B)
    B.G.LockIn()
    pump()
    advance(40)   -- both replays play out
    if A.G.Match() and B.G.Match() then
      if sum(A) ~= sum(B) then drifted = drifted + 1 end
    end
    if r == 4 then
      -- Bob reloads in the middle of round 5, after locking in
      autoPlan(B)
      B.G.LockIn()
      pump()
      local saved = B.db()
      B.offline = true
      advance(2)
      autoPlan(A)
      A.G.LockIn()     -- Bob is offline: lost
      pump()
      B = client("Bob", saved)
      advance(1)
      check(B.G.Match() and B.G.Match().st.round == 6, "Bob, back from the reload, has played round 5")
      check(B.G.Match().shown == false, "with the window closed, round 5 waits to be shown")
      B.env.SlashCmdList.TRADEWINDS("")
      advance(40)
      check(B.G.Match() == nil or B.G.Match().shown == true, "and is shown when Bob opens the window")
      rounds = rounds + 1
      if A.G.Match() and B.G.Match() and sum(A) ~= sum(B) then drifted = drifted + 1 end
    end
  end
  check(drifted == 0, "both copies stayed identical after every round")
  check(noGames(A) and noGames(B), "the match ended on both sides (" .. rounds .. " rounds)")
  local ra, rb = A.db().pvpRecord.Bob, B.db().pvpRecord.Alice
  check(ra and rb and ra.w == rb.l and ra.l == rb.w and ra.d == rb.d and ra.w + ra.l + ra.d == 1,
    "the result is recorded on both sides, and they agree")
  local winner = ra.w == 1 and A or rb.w == 1 and B or nil
  if winner then
    check(winner.db().stats.wins == 1, "a win against a player counts")
  end
  A.G.Continue()
  B.G.Continue()
end

-- a concession -------------------------------------------------------------------------
do
  local shardsA = A.db().shards
  startMatch(B, A)
  local gid = A.G.Match().pvp.gid
  autoPlan(A)
  A.G.LockIn()
  autoPlan(B)
  B.G.LockIn()
  pump()
  advance(40)
  A.G.EndMatch()
  pump()
  check(noGames(A) and noGames(B), "Alice concedes: the match ends on both sides")
  check(A.db().pvpRecord.Bob.l >= 1 and B.db().pvpRecord.Alice.w >= 1, "a loss for Alice, a win for Bob")
  check(A.db().shards == shardsA, "conceding pays nothing")
  check(B.MOCK.chat and chatHas(B, "Victory"), "Bob is told he won")
  A.G.Continue()
  B.G.Continue()
  -- a resend that arrives after the end gets the concession again
  A.ns.Net.Receive("Bob-Realm", "PL;" .. gid .. ";2;-;?")
  check(A.MOCK.sent[#A.MOCK.sent].msg:find("^EN;.*;concede$"), "a late message about a conceded match is answered")
end

-- the copies drift apart ----------------------------------------------------------------
do
  startMatch(A, B)
  B.G.Match().st.players[1].morale = B.G.Match().st.players[1].morale - 1   -- Bob's copy goes wrong
  autoPlan(A)
  A.G.LockIn()
  autoPlan(B)
  B.G.LockIn()
  pump()
  advance(40)
  check(noGames(A) and noGames(B), "a checksum mismatch ends the match on both sides")
  check(chatHas(A, "out of step") or chatHas(B, "out of step"), "and says why")
end

-- the other side is offline --------------------------------------------------------------
do
  local before = #A.MOCK.sent
  local total = 0
  for _, s in ipairs(A.MOCK.sent) do if s.msg:find("^PL;") then total = total + 1 end end
  check(total < 40, "no plan echoing back and forth so far (" .. total .. " plans sent by Alice in all)")
  startMatch(A, B)
  autoPlan(A)
  A.G.LockIn()
  B.offline = true
  local hide = false
  for _, fn in ipairs(A.MOCK.filters.CHAT_MSG_SYSTEM or {}) do
    hide = fn(nil, "CHAT_MSG_SYSTEM", A.env.ERR_CHAT_PLAYER_NOT_FOUND_S:format("Bob-Realm")) or hide
  end
  check(hide and A.ns.Net.IsOffline(A.G.Match()), "\"No player named Bob\" is hidden and noted")
  check(A.G.GameStatus(A.G.Match()) == "Bob seems to be offline", "and the games list says so")
  A.G.Refresh()
  advance(200)
  local resends = 0
  for i = before + 1, #A.MOCK.sent do if A.MOCK.sent[i].msg:find("^PL;") then resends = resends + 1 end end
  check(resends >= 4 and resends <= 6, "over 200 seconds the plan is sent 5 times, less and less often (" .. resends .. ")")
  B.offline = false
  B.MOCK.now = A.MOCK.now
  advance(130)
  check(B.G.Match().pvp.theirs[1] ~= nil and not A.ns.Net.IsOffline(A.G.Match()), "Bob gets it once he's back, and says so")
  local after = #A.MOCK.sent
  advance(300)
  local more = 0
  for i = after + 1, #A.MOCK.sent do if A.MOCK.sent[i].msg:find("^PL;") then more = more + 1 end end
  check(more == 0, "once Bob has it, Alice stops resending")
  autoPlan(B)
  B.G.LockIn()
  pump()
  advance(40)
  check(A.G.Match().st.round == 2 and B.G.Match().st.round == 2 and sum(A) == sum(B), "and the round is played")
  B.G.EndMatch()
  pump()
  A.G.Continue()
  B.G.Continue()
end

-- several games at once, beside a match against the computer ------------------------------
do
  local Cc = client("Carol")
  startMatch(A, B)
  local gB = A.G.Match().pvp.gid
  startMatch(A, Cc)
  local gC = A.G.Match().pvp.gid
  check(#A.C.Games(A.db()) == 2 and gB ~= gC, "Alice has two games going")
  check(A.G.Match().pvp.gid == gC, "the new game goes on the board")
  check(not A.G.Challenge("Bob") and A.MOCK.errors[#A.MOCK.errors]:find("already have a game going with Bob"),
    "one game per player")
  local max = A.C.MAX_GAMES
  A.C.MAX_GAMES = 2
  check(not A.G.Challenge("Dave") and A.MOCK.errors[#A.MOCK.errors]:find("2 games going"), "and a limit on how many")
  A.C.MAX_GAMES = max

  -- Alice moves in the Carol game, then in the Bob game
  autoPlan(A)
  A.G.LockIn()
  check(A.G.GameStatus(A.db().games[gC]) == "Waiting for Carol", "the Carol game waits for Carol")
  check(A.G.Open(gB) and A.G.Match().pvp.gid == gB, "Alice opens the Bob game")
  check(#A.G.Match().log >= 1, "with its own log")
  autoPlan(A)
  A.G.LockIn()
  -- Carol locks in while Alice looks at the Bob game: that round plays off the board
  autoPlan(Cc)
  Cc.G.LockIn()
  pump()
  local mc = A.db().games[gC]
  check(mc.st.round == 2 and mc.shown == false, "the game off the board played its round, to be shown later")
  check(A.G.GameStatus(mc) == "A new round to watch" and A.G.Match().pvp.gid == gB, "and the board didn't move")
  check(A.R.Checksum(mc.st) == sum(Cc), "Alice's Carol game matches Carol's")
  autoPlan(B)
  B.G.LockIn()
  pump()
  advance(40)
  check(A.G.Match().st.round == 2 and A.G.Match().shown == true and sum(A) == sum(B), "the Bob game on the board played out")
  check(A.G.YourMoves() == 2, "both games wait for Alice")

  -- a match against the computer in between
  A.G.Back()
  check(A.G.Match() == nil and A.G.LobbyView() == "games", "All games: back to the list")
  A.G.ShowGames(false)
  A.G.Start("dorn")
  check(A.G.Match() == A.db().match and A.db().match.opp == "dorn" and #A.C.Games(A.db()) == 2,
    "a match against the computer starts beside them")
  autoPlan(A)
  A.G.LockIn()
  advance(40)
  check(A.db().match.st.round == 2, "and plays")
  -- Carol locks in round 2 meanwhile
  A.MOCK.chat = {}
  autoPlan(Cc)
  Cc.G.LockIn()
  pump()
  check(chatHas(A, "Carol has locked in. Your move"), "Alice is told Carol is waiting for her")
  A.G.Back()
  A.G.Start("sally")
  check(A.G.Match() == nil and A.MOCK.errors[#A.MOCK.errors]:find("Finish or end your match against Dorn"),
    "one match against the computer at a time")
  A.G.Start("dorn")
  check(A.G.Match() == A.db().match, "picking the same opponent carries on with it")

  -- the Carol game: the round Alice missed is shown when she opens it
  A.G.Open(gC)
  advance(40)
  check(mc.shown == true and mc.st.round == 2, "opening the Carol game shows the round she missed")
  check(A.ns.Net.TheyLockedIn(mc), "and Carol has locked in")
  autoPlan(A)
  A.G.LockIn()
  pump()
  advance(40)
  check(mc.st.round == 3 and A.R.Checksum(mc.st) == sum(Cc), "Carol game round 2 played")

  -- Carol concedes while Alice looks at the Bob game
  A.G.Open(gB)
  Cc.G.EndMatch()
  pump()
  check(A.db().games[gC] == nil and A.G.Match().pvp.gid == gB and A.db().pvpRecord.Carol.w == 1,
    "a concession off the board: recorded, the board stays")
  check(chatHas(A, "Carol conceded your game"), "and Alice is told")
  Cc.G.Continue()
  -- tidy up
  A.G.EndMatch()
  pump()
  A.G.Continue()
  B.G.Continue()
  A.G.Open("ai")
  A.G.EndMatch()
  A.G.Continue()
  check(noGames(A) and A.db().match == nil, "all of Alice's games are over")
  clients.Carol = nil
end

-- /tradewinds challenge with a target -------------------------------------------------------
do
  A.MOCK.targetName = "Bob"
  A.env.SlashCmdList.TRADEWINDS("challenge")
  pump()
  check(B.ns.Net.Incoming() == "Alice", "/tradewinds challenge uses your target")
  B.G.AnswerChallenge(false)
  pump()
end

-- two clients in different languages: nothing translated goes over the wire,
-- so they play the same game
do
  local H, W = client("Hans", nil, "deDE"), client("Mei", nil, "zhCN")
  check(H.ns.LOCALE == "deDE" and W.ns.LOCALE == "zhCN", "a German and a Chinese client")
  startMatch(H, W)
  local rounds, drifted = 0, 0
  while H.G.Match() and W.G.Match() and rounds < 12 do
    rounds = rounds + 1
    autoPlan(H); H.G.LockIn(); pump()
    autoPlan(W); W.G.LockIn(); pump()
    advance(40)
    if H.G.Match() and W.G.Match() and sum(H) ~= sum(W) then drifted = drifted + 1 end
  end
  check(drifted == 0, "the German and Chinese copies never differ")
  check(noGames(H) and noGames(W), "their match ends on both sides (" .. rounds .. " rounds)")
  local rh, rw = H.db().pvpRecord["Mei"], W.db().pvpRecord["Hans"]
  check(rh and rw and rh.w == rw.l and rh.l == rw.w, "both record the same result")
  H.offline, W.offline = true, true
end

-- every message fits, and a full deck does with room to spare
do
  local longest, bad = 0, 0
  for _, c in pairs(clients) do
    for _, s in ipairs(c.MOCK.sent) do
      longest = math.max(longest, #s.msg)
      if #s.msg > 255 or s.prefix ~= "Tradewinds" or s.msg:find("|", 1, true) then bad = bad + 1 end
    end
  end
  check(bad == 0, ("every message is under 255 bytes, with no | in it (longest %d)"):format(longest))
  local Net = A.ns.Net
  local ids = {}
  for _, c in ipairs(A.ns.Cards.collectible) do ids[#ids + 1] = c.id end
  table.sort(ids, function(x, y) return #x > #y end)
  local worst = {}
  for i = 1, 20 do worst[i] = ids[i] end
  local enc = Net.EncodeDeck(worst)
  local back = Net.DecodeDeck(enc)
  check(#enc == 40 and back and table.concat(back, ",") == table.concat(worst, ","), "a deck encodes in 40 characters and back")
  check(Net.DecodeDeck("zz" .. enc:sub(3)) == nil and Net.DecodeDeck(enc:sub(3)) == nil, "a damaged deck is refused")
  local st = A.R.NewGame({ seed = 3, decks = { A.C.STARTER, A.C.STARTER } })
  check(Net.DecodePlan(st, 1, "9.1") == nil and Net.DecodePlan(st, 1, "x") == nil and #Net.DecodePlan(st, 1, "-") == 0,
    "plans that don't fit the hand are refused")
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
