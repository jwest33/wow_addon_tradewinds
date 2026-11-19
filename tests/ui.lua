-- UI smoke test: loads the whole addon against the WoW mock, then plays full
-- games through the same functions the buttons call, opens packs, edits the
-- deck, takes a flight and checks nothing errors and the numbers add up.
local ROOT = ROOT or "."
dofile(ROOT .. "/tests/wowmock.lua")

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

local ns = {}
for line in io.lines(ROOT .. "/Deckhand.toc") do
  local file = line:match("^%s*([^#].-%.lua)%s*$")
  if file then
    file = file:gsub("\\", "/")
    assert(loadfile(ROOT .. "/" .. file))("Deckhand", ns)
  end
end
local R, Cards, C, UI = ns.Rules, ns.Cards, ns.Collection, ns.UI
local G = UI.Game
math.randomseed(12345)

MOCK.Fire("ADDON_LOADED", "Deckhand")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Fire("PLAYER_ENTERING_WORLD")
MOCK.Advance(3)
local db = DeckhandCharDB
check(db and #db.deck == 20 and db.packs == C.STARTER_PACKS and db.schema == C.SCHEMA, "fresh character set up")
check(DeckhandMinimapButton ~= nil and DeckhandMinimapButton:IsShown(), "minimap button")

-- open the window
SlashCmdList.DECKHAND("")
check(DeckhandFrame and DeckhandFrame:IsShown(), "/deckhand opens the window")
check(UI.tab == "play", "starts on the Play tab")

-- tooltips on every card (also starts portrait lookups)
do
  local probe = CreateFrame("Button", nil, UIParent)
  UI.CardTooltip(probe, "hogger")
  MOCK.Advance(2)
  check(db.settings.portraits == false and (db.displays or {})[448] == nil, "portraits are off by default: nothing looked up")
  db.settings.portraits = true
  for _, c in ipairs(Cards.list) do UI.CardTooltip(probe, c.id) end
  MOCK.Advance(2)
  db.settings.portraits = false
  check(db.displays[448] == 10448, "Hogger's portrait looked up and saved")
  UI.CardTooltip(probe, "hogger")
  check(GameTooltip.lines[1] == "Hogger", "tooltip title")
  local missing = UI.MissingIcons()
  check(#missing == 4, "missing icons reported (" .. #missing .. ")")
end

-- play full games: plan every affordable card each round
local function autoPlan()
  local st = db.match.st
  local hand = st.players[1].hand
  for h = 1, #hand do
    local c = Cards.byId[hand[h]]
    G.ClickHand(h, "LeftButton")
    if c.type == "unit" or c.target == "friend" then
      for l = 1, R.LANES do
        if G.Selected() then G.ClickSlot(1, l, "LeftButton") end
      end
    elseif c.target == "enemy" and G.Selected() then
      G.ClickSlot(2, (h % 4) + 1, "LeftButton")
    end
    if G.Selected() then G.ClickHand(h, "RightButton") end -- found no target: deselect
  end
end

local function playGame(opp, concedeAt)
  G.Start(opp)
  check(db.match and db.match.opp == opp, "game started vs " .. opp)
  local rounds = 0
  while db.match do
    rounds = rounds + 1
    if rounds > 12 then break end
    if concedeAt and rounds == concedeAt then
      G.EndMatch()
      break
    end
    autoPlan()
    G.LockIn()
    MOCK.Advance(0.05)
    if rounds % 3 == 0 then G.Skip() end
    MOCK.Advance(60)
  end
  check(db.match == nil, "game vs " .. opp .. " finished (" .. rounds .. " rounds)")
  G.Continue()
end

-- the ladder: only the first opponent is open
do
  G.Refresh()
  G.Start("sally")
  check(db.match == nil and MOCK.errors[#MOCK.errors]:find("Beat Bluegill first"), "a locked opponent can't be started")
  -- the lobby row's tooltip lists the stars
  local probe = CreateFrame("Button", nil, UIParent)
  UI.CardTooltip(probe, "bangalash")
  local found = false
  for _, line in ipairs(GameTooltip.lines) do
    if tostring(line):find("Signature card") then found = true end
  end
  check(found, "a signature card says where it comes from")
end
-- the rest of this file plays everyone, so open the whole ladder
for _, o in ipairs(ns.Opponents) do
  db.stars[o.id] = db.stars[o.id] or {}
  db.stars[o.id][1] = true
end

local packsBefore = db.packs
for _, o in ipairs(ns.Opponents) do playGame(o.id) end
playGame("dorn", 3)
local s = db.stats
check(s.wins + s.losses + s.draws == #ns.Opponents + 1, "every game recorded")
print(("games: %d won, %d lost, %d drawn; packs %d -> %d, shards %d"):format(s.wins, s.losses, s.draws,
  packsBefore, db.packs, db.shards))
check(s.losses >= 1, "the concession counts as a loss")

-- planning mechanics
do
  G.Start("dorn")
  local st = db.match.st
  st.players[1].hand = { "fireball", "kobold", "bandage" }
  st.players[1].supply = 3
  G.ClickHand(3, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("needs one of your units"), "friend tactic without a unit is refused")
  G.ClickHand(2, "LeftButton")
  G.ClickSlot(2, 1, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("own lanes"), "unit on the enemy row is refused")
  G.ClickSlot(1, 2, "LeftButton")
  G.ClickHand(3, "LeftButton")
  G.ClickSlot(1, 2, "LeftButton")
  G.ClickHand(1, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("Not enough supply"), "over-spending is refused")
  G.ClickSlot(1, 2, "RightButton")     -- take back the kobold: the bandage goes too
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(2, 3, "LeftButton")
  G.LockIn()
  MOCK.Advance(60)
  check(db.match.st ~= st and st.round == 1, "the round is played on a copy of the game")
  st = db.match.st
  check(#st.players[1].grave >= 1 and st.round == 2, "round played with the fireball")
  G.EndMatch()
  G.Continue()
end

-- resume after a reload: the match is in the saved table
do
  G.Start("sally")
  local st = db.match.st
  UI.Hide()
  SlashCmdList.DECKHAND("")
  check(db.match.st == st and DeckhandFrame:IsShown(), "game still there when reopened")
  G.EndMatch(); G.Continue()
end

-- the forecast while planning
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand = { "grunt", "murloc" }
  st.players[1].supply = 4
  R.Summon(st, 2, 2, "murloc").new = nil
  G.Refresh()
  local f = G.Forecast()
  check(f and f.loss[2] == 0 and f.loss[1] == 2, "empty plan: their murloc hits you for 2")
  G.ClickHand(1, "LeftButton"); G.ClickSlot(1, 1, "LeftButton")   -- grunt into an open lane: 3 to Morale
  G.ClickHand(2, "LeftButton"); G.ClickSlot(1, 2, "LeftButton")   -- murloc blocks theirs
  f = G.Forecast()
  check(f.loss[2] == 3 and f.loss[1] == 0, "grunt hits Morale for 3, murloc blocks")
  check(f.dies[2][2] and f.dies[1][2], "murlocs trade: both marked to die")
  check(not f.dies[1][1], "grunt survives")
  check(st.players[2].morale == R.START_MORALE and #st.players[1].hand == 2, "the forecast doesn't touch the real game")
  SlashCmdList.DECKHAND("forecast off")
  G.Refresh()
  check(G.Forecast() == nil, "no forecast when it's off")
  SlashCmdList.DECKHAND("forecast on")
  G.EndMatch(); G.Continue()
end

-- lane markers
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand = { "grunt", "murloc" }
  st.players[1].supply = 4
  R.Summon(st, 2, 2, "murloc").new = nil
  R.Summon(st, 2, 3, "boar").new = nil
  G.Refresh()
  check(G.LaneState(1) == "open" and G.LaneState(4) == "open", "empty lanes are open")
  local s, a = G.LaneState(3)
  check(s == "in" and a == 2, "their boar with nothing across hits you for 2")
  G.ClickHand(1, "LeftButton"); G.ClickSlot(1, 1, "LeftButton")
  G.ClickHand(2, "LeftButton"); G.ClickSlot(1, 2, "LeftButton")
  s, a = G.LaneState(1)
  check(s == "out" and a == 3, "your grunt with nothing across hits them for 3")
  check(G.LaneState(2) == "fight", "murlocs across from each other fight")
  -- guard: their mountaineer next to an empty lane takes the grunt's hit
  st.players[2].board = {}
  R.Summon(st, 2, 2, "mountaineer").new = nil
  G.Refresh()
  check(G.LaneState(1) == "guard", "a Guard from the next lane blocks")
  G.EndMatch(); G.Continue()
end

-- ending a match: the button asks first; works in the middle of a replay
do
  G.Start("sally")
  local losses = db.stats.losses
  MOCK.popup = nil
  G.AskEndMatch()
  check(MOCK.popup and MOCK.popup.name == "DECKHAND_END_MATCH" and MOCK.popup.arg == "Sally Mudwhistle", "End match asks first")
  check(db.match ~= nil, "nothing ends before you confirm")
  autoPlan()
  G.LockIn()
  MOCK.Advance(0.6)                  -- the round is now playing out
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil and db.stats.losses == losses + 1, "confirmed mid-replay: match over, counted as a loss")
  MOCK.Advance(60)                   -- the rest of the replay must not come back
  check(db.match == nil and LayoverFrame == nil and DeckhandFrame:IsShown(), "no leftovers from the replay")
  G.Continue()
  SlashCmdList.DECKHAND("end")
  check(MOCK.chat[#MOCK.chat]:find("not in a match"), "/deckhand end with no match")
  G.Start("dorn")
  SlashCmdList.DECKHAND("end")
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil, "/deckhand end ends it")
  G.Continue()
end

-- an update ends a saved match without counting it
do
  check(ns.VERSION ~= "dev" and ns.VERSION:match("^%d+%.%d+"), "version read from the .toc (" .. tostring(ns.VERSION) .. ")")
  G.Start("pellwick")
  check(db.match.rules == R.RULES_VERSION, "matches remember the rules version they started under")
  local same = { schema = C.SCHEMA, match = db.match, collection = db.collection, deck = db.deck }
  check(C.Init(same, R.RULES_VERSION) == nil and same.match ~= nil, "same rules: the match stays")
  db.match.version = "9.9.9"
  check(C.Init(db, R.RULES_VERSION) == nil and db.match ~= nil, "a new addon version with the same rules keeps the match")
  local stats = { db.stats.wins, db.stats.losses, db.stats.draws, db.packs, db.shards }
  local rec = db.record.pellwick and (db.record.pellwick.w + db.record.pellwick.l + db.record.pellwick.d) or 0
  local ended = C.Init(db, R.RULES_VERSION + 1)
  check(ended == "pellwick" and db.match == nil, "other rules: the match is ended")
  check(db.stats.wins == stats[1] and db.stats.losses == stats[2] and db.stats.draws == stats[3]
    and db.packs == stats[4] and db.shards == stats[5], "and it doesn't count: no win, loss or reward")
  local rec2 = db.record.pellwick and (db.record.pellwick.w + db.record.pellwick.l + db.record.pellwick.d) or 0
  check(rec2 == rec, "nor in the record against that opponent")
  local legacy = { match = { opp = "dorn", st = {} }, collection = db.collection, deck = db.deck }
  check(C.Init(legacy, R.RULES_VERSION) == "dorn" and legacy.match == nil, "a damaged match is ended too")
  G.Refresh()
  check(DeckhandFrame:IsShown(), "the board goes back to the opponent list")
end

-- a game whose last round finished while the replay was cut short (/reload)
do
  G.Start("dorn")
  db.match.st.winner = 2
  G.Refresh()
  check(db.match == nil, "an already-finished game is wrapped up on refresh")
  G.Continue()
end

-- a card that errors in the middle of a round: the match stays as it was
do
  G.Start("dorn")
  local st = db.match.st
  local hand, deck = #st.players[1].hand, #st.players[1].deck
  local combat = R.Combat
  -- only in the real round (it records events); the computer's own what-ifs don't
  R.Combat = function(s) if s.events then error("boom") end return combat(s) end
  autoPlan()
  G.LockIn()
  MOCK.Advance(60)
  R.Combat = combat
  check(db.match and db.match.st == st and st.round == 1 and st.winner == nil, "an error mid-round leaves the saved match alone")
  check(#st.players[1].hand == hand and #st.players[1].deck == deck and next(st.players[1].board) == nil
    and st.players[2].morale == R.START_MORALE, "nothing of the failed round was applied")
  check(MOCK.errors[#MOCK.errors]:find("unchanged") and MOCK.chat[#MOCK.chat]:find("boom"), "the error is reported")
  G.LockIn()
  MOCK.Advance(60)
  check(db.match and db.match.st.round == 2, "and the board isn't locked: the round can be played again")
  -- ending a match early pays nothing
  local shards, packs, losses = db.shards, db.packs, db.stats.losses
  G.EndMatch()
  check(db.match == nil and db.stats.losses == losses + 1 and db.shards == shards and db.packs == packs,
    "conceding counts as a loss and pays nothing")
  G.Continue()
end

-- packs
do
  UI.SelectTab("packs")
  local before = db.packs
  db.packs = math.max(db.packs, 2)
  UI.Packs.Open()
  check(db.packs == math.max(before, 2) - 1, "opening a pack uses it up")
  UI.Packs.RevealAll()
  db.shards = C.PACK_COST + 5
  UI.Refresh()
  check(C.BuyPack(db) and db.shards == 5, "buy a pack")
  UI.Packs.Open(); UI.Packs.Open()
  db.packs = 4
  local chat = #MOCK.chat
  UI.Packs.OpenAll()
  check(db.packs == 0 and #MOCK.chat > chat and MOCK.chat[chat + 1]:find("Opened 4 packs"), "open all opens every pack and says what was in them")
end

-- the tutorial
do
  check(db.settings.seenWelcome == nil and not (db.tutorial and db.tutorial.done), "a new character hasn't seen the tutorial")
  local packs = db.packs
  local s0 = { db.stats.wins, db.stats.losses, db.stats.draws }
  local function handIndex(id)
    for h, x in ipairs(db.match.st.players[1].hand) do if x == id then return h end end
  end
  UI.SelectTab("guide")
  G.StartTutorial()
  local m = db.match
  check(m and m.tutorial and m.opp == "dorn" and UI.tab == "play", "the tutorial starts on the Play tab")
  check(db.settings.seenWelcome and UI.Tutorial.coach:IsShown(), "the coach is talking")
  check(UI.Tutorial.pointer:IsShown(), "the arrow points at the card to play")
  G.ClickHand(handIndex("thug"), "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("Not that one yet"), "the coach refuses other cards")
  G.ClickHand(handIndex("kobold"), "LeftButton")
  G.ClickSlot(1, 1, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("lane 2") and G.Selected(), "and other lanes")
  G.ClickSlot(1, 2, "LeftButton")
  G.LockIn()
  MOCK.Advance(60)
  check(db.match.st.round == 2 and UI.Tutorial.Gate(db.match), "round 1 played; the coach explains it")
  G.ClickHand(handIndex("thug"), "LeftButton")
  check(G.Selected() == nil, "no planning until you click Next")
  UI.Tutorial.Next()
  for r = 2, ns.Tutorial.GUIDED do
    G.LockIn()
    check(MOCK.errors[#MOCK.errors]:find("Dorn:"), "round " .. r .. ": can't lock in before playing what Dorn asked")
    for _, want in ipairs(ns.Tutorial.ROUNDS[r].you) do
      G.ClickHand(handIndex(want.id), "LeftButton")
      local c = Cards.byId[want.id]
      G.ClickSlot((c.type == "tactic" and c.target == "enemy") and 2 or 1, want.lane, "LeftButton")
    end
    G.LockIn()
    MOCK.Advance(60)
    check(db.match.st.round == r + 1, "tutorial round " .. r .. " played")
    UI.Tutorial.Next()
  end
  local _, kind = UI.Tutorial.Gate(db.match)
  check(kind == "free", "then Dorn hands over")
  UI.Tutorial.Next()
  check(UI.Tutorial.Gate(db.match) == nil and not UI.Tutorial.coach:IsShown(), "free play: the coach steps back")
  local rounds = 0
  while db.match and rounds < 10 do
    rounds = rounds + 1
    autoPlan()
    G.LockIn()
    MOCK.Advance(60)
  end
  check(db.match == nil and db.tutorial.done and db.packs == packs + C.TUTORIAL_PACKS, "finishing the tutorial pays a pack")
  check(db.stats.wins == s0[1] and db.stats.losses == s0[2] and db.stats.draws == s0[3], "and doesn't count on the circuit")
  G.Continue()
  G.StartTutorial()
  MOCK.popup = nil
  G.AskEndMatch()
  check(MOCK.popup and MOCK.popup.name == "DECKHAND_END_TUTORIAL", "leaving the tutorial asks first")
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil and db.packs == packs + C.TUTORIAL_PACKS and db.stats.losses == s0[2], "leaving it: no pack, no loss")
  G.Continue()
end

-- first-time keyword tips
do
  db.settings.seenKw = nil
  db.settings.seenLaneTip = true
  G.Start("dorn")
  local st = db.match.st
  st.players[1].hand = { "kobold", "wolf" }
  for p = 1, 2 do st.players[p].board = {} end
  G.Refresh()
  check(G.KeywordTip() == "swift", "a Swift card in hand: the Swift tip")
  G.DismissKeyword()
  check(db.settings.seenKw.swift and G.KeywordTip() == nil, "dismissed, and not shown again")
  R.Summon(st, 2, 1, "mountaineer").new = nil
  G.Refresh()
  check(G.KeywordTip() == "guard", "a Guard on the board: the Guard tip")
  G.DismissKeyword()
  G.EndMatch(); G.Continue()
end

-- the opponent's lines
do
  db.settings.chatter = true
  G.Start("dorn")
  check(G.Bubble() == "hello", "the opponent says hello")
  MOCK.Advance(6)
  check(G.Bubble() == nil, "and the bubble goes away")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {}; st.players[p].hand = {} end
  st.players[2].morale = 3
  G.LockIn()
  for _ = 1, 80 do
    if db.match.shown then break end
    MOCK.Advance(0.25)
  end
  check(db.match.shown and G.Bubble() == "low", "close to losing, they say so")
  check(db.match.log[#db.match.log]:find(ns.OpponentById.dorn.low, 1, true), "the line is in the log")
  MOCK.Advance(6)
  check(G.Bubble() == nil, "the bubble fades")
  G.LockIn()
  MOCK.Advance(60)
  local lows = 0
  for _, line in ipairs(db.match.log) do
    if line:find(ns.OpponentById.dorn.low, 1, true) then lows = lows + 1 end
  end
  check(db.match.said.low == true and lows == 1, "only once a match")
  db.settings.chatter = false
  G.Say("hit")
  check(db.match.said.hit == nil, "chatter off: quiet")
  db.settings.chatter = true
  G.EndMatch(); G.Continue()
end

-- the guide
do
  SlashCmdList.DECKHAND("rules")
  check(UI.tab == "guide", "/deckhand rules opens the Guide")
  for _, key in ipairs({ "basics", "round", "kw1", "kw2", "cards", "winning" }) do
    UI.Guide.Show(key)
    check(UI.Guide.Shown() == key, "guide section " .. key)
  end
  UI.SelectTab("play")
end

-- holographic cards
do
  local plain = function(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local cf = UI.CreateCard(UIParent)
  cf:SetCard("kobold", nil, nil, true)
  check(cf.holo and cf.foil:IsShown() and cf.ring:IsShown(), "a holographic card shows its foil and ring")
  check(UI.HoloTick(0.5), "the shimmer runs")
  cf:ShowTooltip()
  check(plain(GameTooltip.lines[2]) == "Holographic", "its tooltip says so")
  cf:SetCard("kobold")
  check(not cf.holo and not cf.foil:IsShown() and not cf.ring:IsShown(), "the same frame showing a plain card has no foil")
  cf:SetCard("kobold", nil, nil, true)
  cf:SetBack()
  check(not cf.foil:IsShown(), "a card back has no foil")
  check(plain(UI.Packs.Label({ kind = "new", holo = true })) == "NEW! Holographic!"
    and plain(UI.Packs.Label({ kind = "holo", holo = true })) == "Now holographic!", "pack labels for holographic pulls")
  check(not C.IsHolo(db, "ogre") and (db.collection.kobold or 0) > 0, "kobold owned, ogre not holographic")
  db.holo.kobold = true
  check(C.IsHolo(db, "kobold"), "owning a holographic kobold")
  UI.SelectTab("cards")
  UI.Refresh()
  UI.SelectTab("play")
  UI.Refresh()
end

-- options tab
do
  UI.SelectTab("options")
  check(UI.tab == "options", "options tab opens")
  UI.Options.Set("sound", false)
  check(db.settings.sound == false, "options change settings")
  UI.Options.Set("sound", true)
  UI.Options.Set("scale", 1.2)
  check(db.settings.scale == 1.2, "window size")
  UI.Options.Set("scale", 1)
  SlashCmdList.DECKHAND("options")
end

-- the last round is saved with the match: Replay shows it again, and a
-- replay cut short (a /reload) is shown when the board next opens
do
  G.Start("dorn")
  check(db.match.last == nil, "nothing to replay before the first round")
  autoPlan()
  G.LockIn()
  MOCK.Advance(0.2)
  local m = db.match
  check(m.last and #m.last.events > 0 and m.shown == false, "the round is saved while it plays out")
  check(type(m.last.view.hand) == "table" and m.last.view.players[1].handCount == #m.last.view.hand,
    "with your hand as it was")
  MOCK.Advance(60)
  check(m.shown == true and m.stats and m.stats.dealt >= 0 and m.log and #m.log > 0, "afterwards: marked as shown, numbers and log kept")
  local st, round, lines = m.st, m.st.round, #m.log
  G.Replay()
  MOCK.Advance(0.2)
  check(m.shown == true and db.match.st == st, "Replay shows the round again")
  G.LockIn()                         -- ignored while the replay runs
  MOCK.Advance(60)
  check(db.match.st == st and st.round == round and #m.log > lines, "and changes nothing")
  m.shown = false                    -- as if the game was reloaded mid-replay
  G.Refresh()
  check(G.Selected() == nil and db.match.shown == false, "an unseen round starts replaying when the board opens")
  MOCK.Advance(60)
  check(db.match.shown == true and db.match.st == st, "and ends where the game really is")
  local f = G.Forecast()
  check(f and f.maybe and f.dies, "the forecast tells certain deaths from possible ones")
  G.EndMatch(); G.Continue()
end

-- stars, rewards and the daily task through a real match
do
  db.daily = { date = ns.Today(), id = "rounds", n = C.TaskById.rounds.goal - 1, done = false }
  db.stars.dorn = { true }
  db.collection.bangalash = nil
  db.progress.wins = nil
  G.Start("dorn")
  check(db.match.plain == true, "the starter deck is a plain deck")
  local st = db.match.st
  st.players[2].morale = 1
  st.players[2].board = {}
  st.players[1].board = {}
  st.players[1].hand = { "grunt" }
  st.players[2].hand = {}
  st.players[1].supply = 3
  local shards, chat = db.shards, #MOCK.chat
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(1, 1, "LeftButton")
  G.LockIn()
  MOCK.Advance(60)
  check(db.daily.done and db.shards >= shards + C.REWARD.daily, "playing the round finished the daily task")
  local announced = false
  for i = chat + 1, #MOCK.chat do
    if MOCK.chat[i]:find("daily task") then announced = true end
  end
  check(announced, "and said so")
  local _, stars = C.Stars(db, "dorn")
  check(db.match == nil and stars == 3 and db.collection.bangalash == 1, "a decisive win with a plain deck: all three stars and the signature card")
  G.Continue()
  G.RefreshLobby()
end

-- binder / deck editing
do
  UI.SelectTab("cards")
  -- crafting: shift-click asks, then makes the card
  db.collection.kazzak = nil
  db.shards = C.CRAFT_COST.epic - 1
  MOCK.shift = true
  MOCK.popup = nil
  UI.Binder.Click("kazzak", "LeftButton")
  check(MOCK.popup == nil and MOCK.errors[#MOCK.errors]:find("costs 150 shards"), "crafting needs the shards")
  db.shards = C.CRAFT_COST.epic + 3
  UI.Binder.Click("kazzak", "LeftButton")
  check(MOCK.popup and MOCK.popup.name == "DECKHAND_CRAFT" and db.collection.kazzak == nil, "crafting asks first")
  StaticPopupDialogs.DECKHAND_CRAFT.OnAccept()
  check(db.collection.kazzak == 1 and db.shards == 3, "confirmed: the card is made and the shards spent")
  StaticPopupDialogs.DECKHAND_CRAFT.OnAccept()
  check(db.collection.kazzak == 1 and db.shards == 3, "confirming twice makes one card")
  MOCK.shift = false

  -- filters
  local total = #UI.Binder.Shown()
  check(total == #Cards.collectible, "no filters: every card")
  UI.Binder.SetFilter("kind", "murloc")
  local murlocs = UI.Binder.Shown()
  local allMurlocs = #murlocs > 0
  for _, c in ipairs(murlocs) do if c.tribe ~= "murloc" then allMurlocs = false end end
  check(allMurlocs, "filter by tribe (" .. #murlocs .. " Murlocs)")
  UI.Binder.SetFilter("kind", "all")
  UI.Binder.SetFilter("rarity", "legendary")
  check(#UI.Binder.Shown() == 4, "filter by rarity")
  UI.Binder.SetFilter("cost", 1)
  check(#UI.Binder.Shown() == 0, "filters combine (no 1-cost legendaries)")
  UI.Binder.SetFilter("rarity", "all"); UI.Binder.SetFilter("cost", "all")
  UI.Binder.SetFilter("own", "deck")
  local inDeck = {}
  for _, id in ipairs(db.deck) do inDeck[id] = true end
  local kinds = 0
  for _ in pairs(inDeck) do kinds = kinds + 1 end
  check(#UI.Binder.Shown() == kinds, "filter: in your deck")
  UI.Binder.SetFilter("own", "all")

  -- deck slots
  local first = db.deck
  UI.Binder.SelectDeck(2)
  check(db.deckSlot == 2 and db.deck ~= first and #db.deck == 20 and db.decks[1] == first, "a second deck starts as the starter deck")
  UI.Binder.Click("kobold", "RightButton")
  check(#db.deck == 19 and #first == 20, "editing one deck leaves the other alone")
  UI.Binder.SelectDeck(1)
  check(db.deck == first and #db.decks[2] == 19, "and switching back restores it")
  local n = #db.deck
  UI.Binder.Click("kobold", "RightButton")
  check(#db.deck == n - 1, "right-click takes a card out")
  UI.Binder.Click("kobold", "LeftButton")
  check(#db.deck == n, "left-click puts it back")
  UI.Binder.Click("onyxia", "LeftButton")
  check(#db.deck == n, "full or unowned refused")
  db.deck = {}
  UI.Refresh()
  UI.SelectTab("play")
  G.Start("dorn")
  check(db.match == nil and MOCK.errors[#MOCK.errors]:find("Fix it"), "can't start with a broken deck")
  C.ResetDeck(db)
end

-- a flight: toast, flight packs, landing closes the window
do
  UI.Hide()
  local packs = db.packs
  db.progress.travel = 0
  MOCK.onTaxi = true
  MOCK.speed = 30
  MOCK.Fire("PLAYER_CONTROL_LOST")
  MOCK.Advance(1)
  check(DeckhandToast and DeckhandToast:IsShown(), "flight toast")
  SlashCmdList.DECKHAND("")
  MOCK.Advance(C.TRAVEL_PACK_SECONDS + 5)
  check(db.packs == packs + 1, "a pack for 20 minutes in the air")
  MOCK.speed = 7               -- landed, but UnitOnTaxi still says yes (seen on the live client)
  MOCK.Advance(2)
  check(not ns.Travel.IsFlying() and not DeckhandFrame:IsShown(), "landing detected by speed, window closed")
  MOCK.onTaxi = false
end

-- other events and slash commands
do
  local packs = db.packs
  local shards = db.shards
  MOCK.Fire("PLAYER_LEVEL_UP", 23)
  MOCK.Fire("UI_INFO_MESSAGE", 0, "New flight path discovered!")
  check(db.packs == packs and db.shards == shards + C.REWARD.level + C.REWARD.flightPath, "a level and a new flight path give shards")
  MOCK.Fire("PLAYER_LEVEL_UP", 30)
  check(db.packs == packs + 1 and db.shards == shards + 2 * C.REWARD.level + C.REWARD.flightPath, "every tenth level gives a pack too")
  SlashCmdList.DECKHAND("")
  MOCK.Fire("PLAYER_REGEN_DISABLED")
  check(not DeckhandFrame:IsShown(), "combat closes the window")
  for _, cmd in ipairs({ "help", "rules", "icons", "speed 3", "scale 0.9", "reset", "toast off", "minimap off", "minimap on", "packs", "cards", "play" }) do
    SlashCmdList.DECKHAND(cmd)
  end
  check(db.settings.speed == 3 and db.settings.toast == false, "settings commands")
end

-- the addon only creates the globals it means to
do
  local allowed = { DeckhandCharDB = true, Deckhand_Toggle = true, SLASH_DECKHAND1 = true,
    BINDING_HEADER_DECKHAND = true, BINDING_NAME_DECKHAND_TOGGLE = true, DeckhandFrame = true,
    DeckhandToast = true, DeckhandMinimapButton = true }
  local leaked = {}
  for k in pairs(_G) do
    if not globalsBefore[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end
  end
  table.sort(leaked)
  check(#leaked == 0, "no stray globals (" .. table.concat(leaked, ", ") .. ")")
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
