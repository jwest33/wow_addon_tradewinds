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

-- trading cards -------------------------------------------------------------------------------
do
  local function T(c) return c.ns.Trade end
  local function U(c) return c.ns.UI.Trading end
  local function click(c, id, button, shift)
    c.MOCK.shift = shift
    c.ns.UI.Binder.Click(id, button or "LeftButton")
    c.MOCK.shift = false
  end
  local function owned(c, id) return c.C.Owned(c.db(), id) end
  local function open()
    check(U(A).Ask("Bob"), "Alice asks Bob to trade")
    pump()
    U(B).Answer(true)
    pump()
    return T(A).Current() and T(B).Current() and T(A).Current().tid == T(B).Current().tid
  end
  local Cards = A.ns.Cards
  local rare, epic = A.C.PackPool("rare")[1], A.C.PackPool("epic")[1]
  A.db().collection[rare], A.db().collection[epic] = 1, nil
  B.db().collection[rare], B.db().collection[epic] = nil, 2
  for _, c in ipairs({ A, B }) do
    for _, id in ipairs({ "wolf", "boar", "kobold", "murloc" }) do c.db().collection[id] = 2 end
    c.db().holo = {}
    c.C.ResetDeck(c.db())
  end

  -- asked and declined
  check(U(A).Ask("Bob"), "Alice asks Bob to trade")
  check(not U(A).Ask("Bob") and A.MOCK.errors[#A.MOCK.errors]:find("already waiting"), "one request at a time")
  pump()
  check(B.MOCK.popup and B.MOCK.popup.name == "TRADEWINDS_TRADE" and B.MOCK.popup.arg == "Alice", "Bob is asked, with Alice's name")
  U(B).Answer(false)
  pump()
  check(T(A).Outgoing() == nil and chatHas(A, "Bob declined your trade request"), "declined: Alice is told")
  check(not U(A).Ask("alice") and A.MOCK.errors[#A.MOCK.errors]:find("yourself"), "you can't trade with yourself")

  -- a trade: Alice's rare for two of Bob's epics, then one epic and a wolf
  check(open(), "the trade opens on both sides")
  local va = U(A).View()
  check(A.ns.UI.tab == "cards" and va.shown and va.title == "Trade with Bob", "Alice sees it in the Cards tab")
  check(not va.canAccept and not T(A).Accept(), "nothing to accept while both sides are empty")
  click(A, rare)
  pump()
  local vb = U(B).View()
  check(#T(B).Current().theirs == 1 and vb.get[1] == Cards.byId[rare].name .. " [New]", "Alice offers her rare; Bob sees it, new to him")
  click(A, rare)
  check(#T(A).Current().mine == 1 and A.MOCK.errors[#A.MOCK.errors]:find("every copy"), "she can't offer a copy she hasn't got")
  click(B, epic)
  click(B, epic)
  pump()
  check(U(A).View().get[1] == Cards.byId[epic].name .. " x2 [New]", "Bob offers two epics")
  check(T(A).Accept(), "Alice accepts")
  pump()
  check(U(A).View().me == "You have accepted" and U(B).View().them == "Alice has accepted", "both see that Alice has accepted")
  click(B, epic, "RightButton")
  click(B, "wolf")
  pump()
  check(T(A).Current().accepted == nil and U(A).View().me == "You haven't accepted yet", "Bob's change takes Alice's acceptance back")
  check(U(B).View().note:find("takes 1 card out of your decks", 1, true), "Bob is told the wolf leaves his deck")
  local rows = table.concat(U(A).View().get, " / ")
  check(rows:find("Young Wolf [+1 shard]", 1, true) and rows:find(Cards.byId[epic].name .. " [New]", 1, true),
    "Alice sees one epic, new to her, and a wolf that would be a shard (" .. rows .. ")")
  local shardsA, tid = A.db().shards, T(A).Current().tid
  check(T(B).Accept(), "Bob accepts")
  pump()
  check(U(A).View().them == "Bob has accepted" and U(A).View().note:find("Accept to trade", 1, true), "Alice is told Bob has accepted")
  check(T(A).Accept(), "and accepts too")
  pump()
  check(T(A).Current() == nil and T(B).Current() == nil and not U(A).View().shown, "the trade is done and closes on both sides")
  check(owned(A, rare) == 0 and owned(B, rare) == 1, "the rare changed hands")
  check(owned(A, epic) == 1 and owned(B, epic) == 1, "and one epic")
  check(owned(B, "wolf") == 1 and owned(A, "wolf") == 2 and A.db().shards == shardsA + 1, "the wolf, past Alice's limit, became a shard")
  check(#B.db().deck == 19 and B.C.Count(B.db().deck, "wolf") == 1, "Bob's deck lost the wolf he gave away")
  check(chatHas(A, "Trade with Bob done") and chatHas(B, "Taken out of your decks"), "both are told what happened")
  check(next(A.db().tradePending) == nil and B.db().tradesDone[tid], "nothing left waiting")
  B.C.ResetDeck(B.db())
  B.db().collection.wolf = 2

  -- a holographic copy; the answer to the deal is lost, so it goes again
  A.db().holo.boar = true
  check(open(), "a second trade opens")
  click(A, "boar")
  check(not T(A).Current().mine[1].holo, "a click offers a plain copy first")
  click(A, "boar", nil, true)
  check(T(A).Current().mine[2].holo, "shift-click offers the holographic one")
  click(A, "boar", "RightButton")
  check(#T(A).Current().mine == 1 and T(A).Current().mine[1].holo, "right-click takes the plain one back first")
  pump()
  check(U(B).View().get[1] == "Mottled Boar [Holo]", "Bob is told his boar would turn holographic (" .. tostring(U(B).View().get[1]) .. ")")
  check(T(B).Accept(), "Bob accepts a gift")
  pump()
  drop = function(msg) return msg:find("^TK;") end
  T(A).Accept()
  pump()
  drop = nil
  check(B.C.IsHolo(B.db(), "boar") and owned(B, "boar") == 2 and T(B).Current() == nil, "Bob's boar is holographic now")
  check(owned(A, "boar") == 2 and next(A.db().tradePending) ~= nil, "Alice hasn't heard back, so her side waits")
  check(U(A).View().shown and not U(A).View().canCancel, "her trade shows, and can't be cancelled now")
  local plain, holo = A.C.Spare(A.db(), "boar")
  check(plain == 1 and not holo, "the holographic boar is spoken for meanwhile")
  advance(6)
  check(owned(A, "boar") == 1 and not A.C.IsHolo(A.db(), "boar") and next(A.db().tradePending) == nil,
    "the deal went again, Bob answered again, and Alice's side is done")
  check(owned(B, "boar") == 2 and T(A).Current() == nil, "Bob's side was done only once")

  -- Alice's deal is lost and she reloads: it goes again from her saved data
  check(open(), "a third trade opens")
  click(A, "kobold")
  pump()
  T(B).Accept()
  pump()
  drop = function(msg) return msg:find("^TD;") end
  T(A).Accept()
  pump()
  drop = nil
  local saved = A.db()
  check(next(saved.tradePending) ~= nil and T(B).Current(), "the deal is in Alice's saved data; Bob's trade is still open")
  local shardsB = B.db().shards
  A.offline = true
  A = client("Alice", saved)
  pump()
  check(owned(A, "kobold") == 1 and B.db().shards == shardsB + 1 and T(B).Current() == nil and next(A.db().tradePending) == nil,
    "after the reload the deal went through on both sides")

  -- Bob cancels while the deal is on its way: no cards change hands
  check(open(), "a fourth trade opens")
  click(A, "murloc")
  pump()
  T(B).Accept()
  pump()
  drop = function(msg) return msg:find("^TD;") end
  T(A).Accept()
  pump()
  drop = nil
  check(T(B).Cancel(), "Bob cancels")
  pump()
  check(T(A).Current() and T(A).Current().committing, "Alice waits for the answer to her deal")
  advance(6)
  check(T(A).Current() == nil and next(A.db().tradePending) == nil and owned(A, "murloc") == 2 and owned(B, "murloc") == 2,
    "the deal was refused: nothing changed")
  check(chatHas(A, "side of the trade is gone"), "and Alice is told")

  -- Bob reloads with a trade open: Alice's closes
  check(open(), "a fifth trade opens")
  local savedB = B.db()
  B.offline = true
  B = client("Bob", savedB)
  pump()
  check(T(A).Current() == nil and chatHas(A, "Bob cancelled the trade"), "Bob reloads: Alice's trade closes")

  -- room for eight cards; busy; cancelled
  check(open(), "a sixth trade opens")
  local ids = {}
  for id, n in pairs(A.db().collection) do if n > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  for i = 1, 9 do click(A, ids[i]) end
  check(#T(A).Current().mine == 8 and A.MOCK.errors[#A.MOCK.errors]:find("room for 8"), "at most eight cards a side")
  local Cc = client("Carol")
  check(U(Cc).Ask("Alice"), "Carol asks Alice")
  pump()
  check(chatHas(Cc, "Alice is busy with another trade"), "Alice is busy")
  check(T(A).Cancel(), "Alice cancels")
  pump()
  check(T(B).Current() == nil and chatHas(B, "Alice cancelled the trade") and owned(A, ids[1]) > 0, "Bob's trade closes; nothing moved")

  -- an unanswered request; another version; offline
  check(U(A).Ask("Bob"), "Alice asks again")
  pump()
  advance(T(B).ANSWER_SECONDS + 2)
  check(T(A).Outgoing() == nil and chatHas(A, "Bob didn't answer your trade request") and B.MOCK.popup == nil,
    "an unanswered request declines by itself")
  T(B).PROTO = 99
  U(A).Ask("Bob")
  pump()
  check(T(A).Outgoing() == nil and chatHas(A, "different version") and chatHas(B, "wants to trade cards, but"),
    "a different trade version: both are told")
  T(B).PROTO = 1
  B.offline = true
  U(A).Ask("Bob")
  local hide = false
  for _, fn in ipairs(A.MOCK.filters.CHAT_MSG_SYSTEM or {}) do
    hide = fn(nil, "CHAT_MSG_SYSTEM", A.env.ERR_CHAT_PLAYER_NOT_FOUND_S:format("Bob")) or hide
  end
  check(hide and T(A).Outgoing() == nil and chatHas(A, "Bob isn't online"), "Bob is offline: the bounce is hidden and Alice is told")
  B.offline = false
  A.MOCK.targetName = "Bob"
  A.env.SlashCmdList.TRADEWINDS("trade")
  pump()
  check(T(B).Incoming() == "Alice", "/tradewinds trade uses your target")
  U(B).Answer(false)
  pump()
  A.MOCK.targetName = nil
  clients.Carol = nil
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
