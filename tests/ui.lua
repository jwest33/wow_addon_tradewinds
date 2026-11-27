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
for line in io.lines(ROOT .. "/Tradewinds.toc") do
  local file = line:match("^%s*([^#].-%.lua)%s*$")
  if file then
    file = file:gsub("\\", "/")
    assert(loadfile(ROOT .. "/" .. file))("Tradewinds", ns)
  end
end
local R, Cards, C, UI = ns.Rules, ns.Cards, ns.Collection, ns.UI
local G = UI.Game
math.randomseed(12345)

MOCK.Fire("ADDON_LOADED", "Tradewinds")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Fire("PLAYER_ENTERING_WORLD")
MOCK.Advance(3)
local db = TradewindsCharDB
check(db and #db.deck == 20 and db.packs == C.STARTER_PACKS and db.schema == C.SCHEMA, "fresh character set up")
check(TradewindsMinimapButton ~= nil and TradewindsMinimapButton:IsShown(), "minimap button")

-- open the window
SlashCmdList.TRADEWINDS("")
check(TradewindsFrame and TradewindsFrame:IsShown(), "/tradewinds opens the window")
check(UI.tab == "play", "starts on the Play tab")

-- tooltips on every card
do
  local probe = CreateFrame("Button", nil, UIParent)
  for _, c in ipairs(Cards.list) do UI.CardTooltip(probe, c.id) end
  check(db.settings.portraits == nil and db.displays == nil, "the portrait option and its saved lookups are gone")
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

local function playGame(opp, concedeAt, heroic)
  G.Start(opp, heroic)
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
  -- the lobby: portraits, locks, signature cards, the daily task's bar
  local lobby = G.api.lobby()
  check(G.api.lobbyRow(2).lock:IsShown() and not G.api.lobbyRow(1).lock:IsShown(), "a locked opponent's row shows a lock")
  check(G.api.lobbyRow(1).sig.icon:GetAlpha() < 1, "a signature card you don't own is greyed")
  check(lobby.dailyBar.value ~= nil and lobby.dailyCount:GetText():find("/"), "the daily task has a progress bar")
  check(lobby.tutorial:GetText():find("Windfall"), "the tutorial button names the Windfall pack it pays")
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

-- heroic rematches (the whole ladder is open, so they are too)
do
  G.Continue()
  G.SetHeroicView(true)
  check(G.HeroicView(), "the opponent list switches to heroic rematches")
  G.Start("dorn", true)
  local m = db.match
  local theirs, allowed, stray = {}, {}, 0
  for _, id in ipairs(ns.OpponentById.dorn.heroic) do allowed[id] = true end
  for _, id in ipairs(m.st.players[2].deck) do theirs[#theirs + 1] = id end
  for _, id in ipairs(m.st.players[2].hand) do theirs[#theirs + 1] = id end
  for _, id in ipairs(theirs) do if not allowed[id] then stray = stray + 1 end end
  check(m.heroic and #theirs == 20 and stray == 0, "a heroic match uses their heroic deck")
  G.EndMatch()
  G.Continue()
  local wins = s.wins
  playGame("dorn", nil, true)
  local rec = db.heroic.dorn
  check(rec and rec.w + rec.l + rec.d == 2 and s.wins + s.losses + s.draws == #ns.Opponents + 3, "heroic games are recorded apart")
  check(db.record.dorn.w + db.record.dorn.l + db.record.dorn.d == 2, "the circuit record is untouched")
  if s.wins > wins then check(rec.beaten and C.IsHolo(db, "bangalash"), "a heroic win: holographic signature card") end
  G.SetHeroicView(false)
end

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

-- traps: the gift; yours face down, theirs only a count; the forecast and the
-- lane markers can't tell where theirs is; the replay springs them; the end
-- screen turns the rest face up
do
  local function chatHas(text)
    for _, line in ipairs(MOCK.chat) do if line:find(text, 1, true) then return true end end
    return false
  end
  check(db.progress.trapGift and C.Owned(db, "defiasambush") >= 1 and C.Owned(db, "immolation") >= 1,
    "everyone gets a Defias Ambush and an Immolation Trap")
  check(chatHas("Traps are new"), "and chat says so")
  local before = C.Owned(db, "immolation")
  check(C.TrapGift(db) == nil and C.Owned(db, "immolation") == before, "only once")

  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board, st.players[p].traps = {}, {} end
  st.players[1].hand = { "immolation", "grunt" }
  st.players[1].supply = 6
  st.players[2].hand = {}
  R.Summon(st, 2, 2, "grunt").new = nil
  db.settings.seenLaneTip = true
  db.settings.seenKw = db.settings.seenKw or {}
  db.settings.seenKw.trap = nil
  G.Refresh()
  check(G.KeywordTip() == "trap", "the first trap in your hand gets a tip")
  G.DismissKeyword()
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(2, 1, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("Traps go face down"), "a trap can't go on their row")
  G.ClickSlot(1, 2, "LeftButton")
  local slot = G.api.slot(1, 2)
  check(slot.card:IsShown() and slot.card.back:IsShown() and slot.card.hiddenId == "immolation" and not slot.card.cardId,
    "your planned trap shows face down")
  slot.card:ShowTooltip()
  check(GameTooltip.lines[1] == Cards.byId.immolation.name, "pointing at it says which trap it is")
  check(G.LaneState(2) == "trap", "the lane marker: their Grunt springs it")
  check(G.Forecast().loss[1] == 0, "the forecast: the strike stops at the trap")
  G.ClickHand(2, "LeftButton")
  G.ClickSlot(1, 2, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("trap in that lane"), "a unit can't go where your trap is")
  G.ClickHand(2, "RightButton")
  G.LockIn()
  MOCK.Advance(60)
  st = db.match.st
  local grunt = st.players[2].board[2]
  check(not R.TrapAt(st, 1, 2) and grunt and grunt.hp == 1, "the trap sprang: 3 damage to their Grunt")
  local logged = false
  for _, line in ipairs(db.match.log) do
    if line:find(Cards.byId.immolation.name, 1, true) and line:find("sprang") then logged = true end
  end
  check(logged, "the log says who sprang what")
  check(C.Life(db, "trapsSet") == 1 and C.Life(db, "trapsSprung") == 1 and C.Life(db, "trapKills") == 0,
    "the trap counters (the auto-played games before set none of yours)")
  check(db.ach.trapset and db.ach.spring1, "and the first trap achievements")

  -- theirs: a count by their Morale, nothing in their lane, and nothing the
  -- forecast or the markers let slip
  st.players[1].hand = { "grunt" }
  st.players[1].supply = 6
  st.players[2].board[2] = nil
  G.Refresh()
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(1, 3, "LeftButton")
  local loss, state = G.Forecast().loss[2], G.LaneState(3)
  check(not G.api.trapMark():IsShown(), "no trap of theirs: no count")
  local sprungOn = C.Life(db, "sprungOn")
  R.SetTrap(st, 2, 3, "landmine")
  G.Refresh()
  local mark = G.api.trapMark()
  check(mark:IsShown() and mark.count:GetText() == "x1", "their trap: a count by their Morale")
  check(not G.api.slot(2, 3).card:IsShown(), "and nothing in their lane")
  local loss2 = G.Forecast().loss[2]
  local state2, _, lines2 = G.LaneState(3)
  check(loss2 == loss and loss == 3 and state2 == state and state == "out",
    "the forecast and the marker are the same with or without their trap")
  check(table.concat(lines2 or {}, " "):find("1 trap set"), "the marker only says they have one, somewhere")
  st.players[2].hand = {}
  G.LockIn()
  MOCK.Advance(60)
  st = db.match.st
  check(not R.TrapAt(st, 2, 3) and not st.players[1].board[3] and st.players[2].morale == R.START_MORALE,
    "your Grunt sprang their Goblin Land Mine, and died")
  check(C.Life(db, "sprungOn") == sprungOn + 1 and db.ach.sprungon, "watch your step")

  -- the replay of their trap being set: a count, never a lane or a name
  local m = db.match
  local saved = m.last
  m.last = { view = { round = st.round, init = 1, supply = 1, hand = {}, players = {
      { board = {}, morale = 12, handCount = 0, deckCount = 10, traps = {} },
      { board = {}, morale = 12, handCount = 1, deckCount = 10, trapCount = 0 } } },
    events = { { t = "phase", name = "reveal" }, { t = "trap", p = 2, lane = 4, id = "snaketrap" }, { t = "beat" } } }
  local logBefore = #m.log
  G.Replay()
  MOCK.Advance(0.5)
  check(G.api.trapMark():IsShown() and G.api.trapMark().count:GetText() == "x1" and not G.api.slot(2, 4).card:IsShown(),
    "replayed: their trap shows as a count, not in its lane")
  MOCK.Advance(10)
  local said = table.concat(m.log, "\n", logBefore + 1)
  check(said:find("set a trap") and not said:find(Cards.byId.snaketrap.name, 1, true) and not said:find("lane 4"),
    "and the log says neither which nor where")
  m.last = saved

  -- the end: traps nobody sprang turn face up
  R.SetTrap(st, 2, 1, "snaketrap")
  R.SetTrap(st, 1, 4, "consecrate")
  st.players[2].morale = 1
  st.players[1].hand = { "fireball" }
  st.players[1].supply = 6
  st.players[2].hand = {}
  G.Refresh()
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(2, 2, "LeftButton")
  G.LockIn()
  MOCK.Advance(60)
  local facts = G.GameOverFacts() or ""
  check(db.match == nil and facts:find("Traps that never sprang"), "the end screen turns unsprung traps face up")
  check(facts:find(Cards.byId.snaketrap.name, 1, true) and facts:find(Cards.byId.consecrate.name, 1, true), "both sides'")
  local s1 = G.api.slot(2, 1)
  check(s1.card:IsShown() and s1.card.cardId == "snaketrap", "and on the board")
  check(not G.api.trapMark():IsShown(), "the count is gone once they're face up")
  G.Continue()

  -- the Guide has a page on them
  UI.Guide.Show("traps")
  check(UI.Guide.Shown() == "traps", "the Guide's Traps page")
  UI.Guide.Show("basics")
end

-- resume after a reload: the match is in the saved table
do
  G.Start("sally")
  local st = db.match.st
  UI.Hide()
  SlashCmdList.TRADEWINDS("")
  check(db.match.st == st and TradewindsFrame:IsShown(), "game still there when reopened")
  G.EndMatch(); G.Continue()
end

-- the plan you're making is saved with the match (only saved data survives
-- a /reload or a logout), so the cards you've placed, and the Supply they
-- use, are still there when you come back to the game
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand = { "kobold", "murloc", "thug" }
  st.players[1].supply = 3
  G.Refresh()
  G.ClickHand(1, "LeftButton"); G.ClickSlot(1, 1, "LeftButton")
  G.ClickHand(3, "LeftButton"); G.ClickSlot(1, 3, "LeftButton")
  local d = db.match.draft
  check(d and d.round == st.round and #d.acts == 2, "the plan is saved with the match")
  G.Back()
  G.Open("ai")
  check(G.LaneState(1) == "out" and G.LaneState(3) == "out", "back in the game: the placed cards are still placed")
  G.ClickHand(2, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("Not enough supply"), "and the Supply they use is still spent")
  db.match.draft.round = st.round + 1
  G.Back(); G.Open("ai")
  check(G.LaneState(1) == "open" and db.match.draft == nil, "a saved plan that doesn't fit the game is dropped")
  G.ClickHand(1, "LeftButton"); G.ClickSlot(1, 1, "LeftButton")
  G.LockIn()
  MOCK.Advance(60)
  check(db.match.st.round == 2 and db.match.draft == nil, "a played round leaves no saved plan")
  G.EndMatch(); G.Continue()
end

-- pointing at a tribal card lights up the units it counts
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  R.Summon(st, 1, 1, "wolf")          -- your Beast
  R.Summon(st, 1, 2, "kobold")        -- your Humanoid
  R.Summon(st, 1, 3, "packleader")    -- your Beast, and the card that counts Beasts
  R.Summon(st, 2, 4, "boar")          -- their Beast
  st.players[1].hand = { "callwild" }
  G.Refresh()
  G.CardHover({ cardId = "callwild" }, true)
  check(G.KinLit(1, 1) and G.KinLit(1, 3) and not G.KinLit(1, 2) and not G.KinLit(2, 4),
    "a card in hand that counts Beasts lights up your Beasts, not the rest or theirs")
  G.CardHover({ cardId = "callwild" }, false)
  check(not G.KinLit(1, 1) and not G.KinLit(1, 3), "and they go dark again")
  G.CardHover({ cardId = "packleader", unit = st.players[1].board[3] }, true)
  check(G.KinLit(1, 1) and not G.KinLit(1, 3), "a unit on the board lights up the others, not itself")
  G.CardHover({ cardId = "packleader", unit = st.players[1].board[3] }, false)
  G.CardHover({ cardId = "wolf" }, true)
  check(not G.KinLit(1, 1) and not G.KinLit(1, 3), "a card that counts nothing lights up nothing")
  G.CardHover({ cardId = "wolf" }, false)
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
  SlashCmdList.TRADEWINDS("forecast off")
  G.Refresh()
  check(G.Forecast() == nil, "no forecast when it's off")
  SlashCmdList.TRADEWINDS("forecast on")
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

-- a unit that only arrives during the round (Hogger's Riverpaw Runts) isn't
-- in its lane while you plan. Its lane marker once hit a Lua error on the
-- missing name, which stopped the board redrawing: planned cards stayed in
-- the hand, could be played twice, and Lock In said "That card isn't in
-- your hand."
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand = { "kobold", "hogger" }
  st.players[1].supply = 6
  G.Refresh()
  G.ClickHand(2, "LeftButton")
  local ok, err = pcall(G.ClickSlot, 1, 2, "LeftButton")
  check(ok, "planning Hogger beside empty lanes doesn't error (" .. tostring(err) .. ")")
  local s, a, lines = G.LaneState(1)
  check(s == "out" and a == 1 and lines and lines[1]:find("Riverpaw Runt", 1, true),
    "the lane marker names the runt Hogger brings")
  G.ClickHand(1, "LeftButton"); G.ClickSlot(1, 4, "LeftButton")
  G.ClickHand(1, "LeftButton")         -- the kobold again, as a stale hand button would
  check(G.Selected() == nil, "a planned card can't be picked a second time")
  local n = #MOCK.errors
  G.LockIn()
  check(#MOCK.errors == n, "Lock In takes the plan")
  MOCK.Advance(60)
  check(db.match and db.match.st.round == 2, "the round was played")
  G.EndMatch(); G.Continue()
end

-- an enemy tactic can't be aimed at a unit with Stealth, where it would do
-- nothing; one that also hits the lanes beside it still can
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  R.Summon(st, 2, 2, "footpad").new = nil
  R.Summon(st, 2, 3, "kobold").new = nil
  st.players[1].hand = { "evisc", "chain" }
  st.players[1].supply = 6
  G.Refresh()
  G.ClickHand(1, "LeftButton")
  G.ClickSlot(2, 2, "LeftButton")
  check(MOCK.errors[#MOCK.errors]:find("has Stealth", 1, true) and G.Selected() == 1,
    "Eviscerate can't be aimed at a unit with Stealth")
  G.ClickSlot(2, 3, "LeftButton")
  check(G.Selected() == nil, "but can at the unit beside it")
  G.ClickHand(2, "LeftButton")
  G.ClickSlot(2, 2, "LeftButton")
  check(G.Selected() == nil and #db.match.draft.acts == 2, "Chain Lightning can: it hits the lanes beside too")
  G.EndMatch(); G.Continue()
end

-- the replay shows damage being undone or finding nothing, rather than
-- leaving a gap: Regenerate healing at the end of the round, a Fallen effect
-- with nothing across, a tactic that can't target a unit with Stealth
do
  G.Start("dorn")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand, st.players[2].hand = {}, {}
  R.Summon(st, 1, 1, "troll").new = nil           -- 3/3 Regenerate: hurt by the thug, then healed
  R.Summon(st, 2, 1, "thug").new = nil
  R.Summon(st, 1, 3, "watcher").new = nil         -- trades with the grunt: nothing left across
  st.players[1].board[3].hp = 3
  R.Summon(st, 2, 3, "grunt").new = nil
  st.players[2].board[3].hp = 2
  -- the forecast's word goes under the unit's state, not over it
  st.players[2].board[1].frozen = true
  st.players[2].board[1].hp = 1
  G.Refresh()
  local tag = G.api.slot(2, 1).card.tag:GetText() or ""
  check(tag:find("Frozen", 1, true) and tag:find("dies", 1, true), "a frozen unit marked to die says both (" .. tag .. ")")
  st.players[2].board[1].frozen = nil
  st.players[2].board[1].hp = 3
  G.LockIn()
  MOCK.Advance(60)
  local m = db.match
  local function logHas(s)
    for _, line in ipairs(m.log or {}) do if line:find(s, 1, true) then return true end end
  end
  check(logHas("regenerated to full health"), "the log says the troll regenerated")
  check(logHas("found no target"), "and that the watcher's Fallen effect found no target")
  local callouts = UI.FX.counts.callout or 0
  m.last.events[#m.last.events + 1] = { t = "fizzle", why = "stealth", p = 2, lane = 4, id = "footpad", tactic = "fireball" }
  G.Replay()
  MOCK.Advance(60)
  check(logHas("has Stealth, so"), "a tactic that couldn't target a unit with Stealth says why")
  check((UI.FX.counts.callout or 0) - callouts >= 3, "each one calls itself out on the board")
  G.EndMatch(); G.Continue()
end

-- ending a match: the button asks first; works in the middle of a replay
do
  G.Start("sally")
  local losses = db.stats.losses
  MOCK.popup = nil
  G.AskEndMatch()
  check(MOCK.popup and MOCK.popup.name == "TRADEWINDS_END_MATCH" and MOCK.popup.arg == "Sally Mudwhistle", "End match asks first")
  check(db.match ~= nil, "nothing ends before you confirm")
  autoPlan()
  G.LockIn()
  MOCK.Advance(0.6)                  -- the round is now playing out
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil and db.stats.losses == losses + 1, "confirmed mid-replay: match over, counted as a loss")
  MOCK.Advance(60)                   -- the rest of the replay must not come back
  check(db.match == nil and LayoverFrame == nil and TradewindsFrame:IsShown(), "no leftovers from the replay")
  G.Continue()
  SlashCmdList.TRADEWINDS("end")
  check(MOCK.chat[#MOCK.chat]:find("Open the game you want to end first"), "/tradewinds end with no match on the board")
  G.Start("dorn")
  SlashCmdList.TRADEWINDS("end")
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil, "/tradewinds end ends it")
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
  check(TradewindsFrame:IsShown(), "the board goes back to the opponent list")
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
  db.packs, db.specialPacks = 4, 0
  local chat = #MOCK.chat
  UI.Packs.OpenAll()
  check(db.packs == 0 and #MOCK.chat > chat and MOCK.chat[chat + 1]:find("Opened 4 packs"), "open all opens every pack and says what was in them")
end

-- packs: the ceremony. Cards turn over; a rare or better glows first; an
-- epic, a legendary or a holographic card charges up before it turns;
-- "Reveal all" turns them one after another, the best last
do
  local FX, P = UI.FX, UI.Packs
  UI.SelectTab("packs")
  db.settings.speed = 1
  local function of(rarity)
    for _, c in ipairs(Cards.collectible) do
      if c.rarity == rarity and C.InPacks(c.id) then return c.id end
    end
  end
  local common, rare, epic, legend = of("common"), of("rare"), of("epic"), of("legendary")
  local open = C.OpenPack
  local nextPack
  C.OpenPack = function() return nextPack end
  nextPack = { { id = common, kind = "copy", shards = 0 }, { id = epic, kind = "new", shards = 0 },
    { id = legend, kind = "new", shards = 0, holo = true } }
  P.Open()
  local charges = FX.counts.charge or 0
  P.Reveal(1)
  check(P.Opened().shown[1] and not P.Opened().up[1] and P.Slot(1).card.flipper:IsShown(), "a common starts turning over")
  MOCK.Advance(0.3)
  check(P.Opened().up[1] and P.Slot(1).card.cardId == common and P.Slot(1).card:GetAlpha() == 1
    and not P.Slot(1).card.flipper:IsShown(), "and is face up a moment later")
  check((FX.counts.charge or 0) == charges, "a common doesn't charge")
  P.Reveal(2)
  check((FX.counts.charge or 0) == charges + 1, "an epic charges first")
  MOCK.Advance(0.4)
  check(not P.Opened().up[2] and P.Slot(2).card.flipper.aura:IsShown(), "it glows while it charges")
  MOCK.Advance(0.6)
  check(P.Opened().up[2] and P.Slot(2).card.cardId == epic, "then turns")
  check(P.SummaryShown() == nil, "no summary while a card is still face down")
  P.Reveal(3)
  MOCK.Advance(1.2)
  check(P.Opened().up[3] and P.Slot(3).card.holo, "the holographic legendary turns, shining")
  check((P.SummaryShown() or ""):find("2 new cards"), "the summary once they're all up")
  local line = P.ShareText() or ""
  check(line:find(Cards.byId[legend].name, 1, true) and line:find("holographic") and line:find("card pack") and not line:find("|c"),
    "Share: the best card of the pack, in plain text")
  MOCK.chatBox = nil
  UI.Share(line)
  check(MOCK.chatBox == line, "goes into the chat box")
  MOCK.chatBox = nil
  check(P.Summary({ { kind = "new" }, { kind = "shards", shards = 3 }, { kind = "copy" } }):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    == "1 new card, +3 shards", "the summary line")
  -- Reveal all: the rest in turn, the best one last
  nextPack = { { id = legend, kind = "new", shards = 0 }, { id = common, kind = "shards", shards = 1 },
    { id = rare, kind = "copy", shards = 0 } }
  P.Open()
  P.RevealAll()
  local o = P.Opened()
  check(o.shown[2] and not o.shown[3] and not o.shown[1], "Reveal all starts with the plainest card")
  MOCK.Advance(0.42)
  check(o.up[2] and o.up[3] and not o.up[1], "the legendary comes last")
  MOCK.Advance(1)
  check(o.up[1] and o.up[2] and o.up[3], "and every card ends face up")
  -- opening the next pack in the middle of a flip leaves nothing half turned
  nextPack = { { id = common, kind = "copy", shards = 0 }, { id = epic, kind = "new", shards = 0 },
    { id = rare, kind = "copy", shards = 0 } }
  P.Open()
  P.Reveal(2)
  MOCK.Advance(0.1)
  P.Open()
  local s2 = P.Slot(2)
  check(not P.Opened().shown[2] and s2.card:GetAlpha() == 1 and not s2.card.flipper:IsShown() and s2.card.back:IsShown(),
    "a new pack mid-flip: the old card finished, the new one face down")
  -- closing the window finishes a flip
  P.Reveal(2)
  MOCK.Advance(0.1)
  UI.Hide()
  check(P.Opened().up[2] and s2.card:GetAlpha() == 1, "closing the window finishes a flip at once")
  check(select(4, FX.PoolSizes()) == 0, "and leaves no effect running")
  SlashCmdList.TRADEWINDS("packs")
  check(not P.Opened().shown[1], "a card nobody clicked stays face down")
  C.OpenPack = open
  db.packs = 2
  P.Open()
  P.Reveal(1)
  P.OpenAll()
  check(db.packs == 0 and P.Opened().up[1] and P.Opened().up[2] and P.Opened().up[3], "Open all mid-flip: everything face up")
end

-- the tutorial
do
  check(db.settings.seenWelcome == nil and not (db.tutorial and db.tutorial.done), "a new character hasn't seen the tutorial")
  local packs, special = db.packs, db.specialPacks
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
  check(db.match == nil and db.tutorial.done and db.packs == packs and db.specialPacks == special + C.TUTORIAL_PACKS,
    "finishing the tutorial pays a Windfall pack")
  local ov = G.api.over()
  check((G.GameOverFacts() or ""):find("Tutorial complete") and ov.nextOpp:IsShown() and ov.nextOpp:GetText():find("Dorn")
    and not ov.rematch:IsShown(), "the tutorial's end screen points to Dorn")
  check(db.stats.wins == s0[1] and db.stats.losses == s0[2] and db.stats.draws == s0[3], "and doesn't count on the circuit")
  G.Continue()
  G.StartTutorial()
  MOCK.popup = nil
  G.AskEndMatch()
  check(MOCK.popup and MOCK.popup.name == "TRADEWINDS_END_TUTORIAL", "leaving the tutorial asks first")
  StaticPopupDialogs[MOCK.popup.name].OnAccept()
  check(db.match == nil and db.specialPacks == special + C.TUTORIAL_PACKS and db.stats.losses == s0[2], "leaving it: no pack, no loss")
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
  SlashCmdList.TRADEWINDS("rules")
  check(UI.tab == "guide", "/tradewinds rules opens the Guide")
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

-- the card face: its type on every card, a different frame for tactics
do
  local plain = function(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local cf = UI.CreateCard(UIParent)
  cf:SetCard("watcher")
  check(cf.typeText:GetText() == "Unit" and cf.base:GetTexture():find("CardUnit$"), "a unit says so and has a unit's frame")
  cf:SetCard("kobold")
  check(cf.typeText:GetText() == "Humanoid unit", "a Humanoid says so")
  check(cf.atk:IsShown() and cf.hp:IsShown() and cf.gem:IsShown(), "with its attack, health and rarity gem")
  check(cf.text:GetText() == "\"You no take candle!\"", "a unit with no rules shows its flavour line")
  cf:SetCard("giants")
  check(cf.typeText:GetText() == "Item: your unit" and cf.base:GetTexture():find("CardItem$"), "an item has its own type line and frame")
  cf:SetCard("potion")
  check(cf.typeText:GetText() == "Item" and cf.base:GetTexture():find("CardItem$"), "Healing Potion is an item now")
  cf:SetCard("cub")
  check(cf.typeText:GetText() == "Beast unit", "a tribe's unit names the tribe")
  cf:SetCard("fireball")
  check(cf.typeText:GetText() == "Tactic: enemy lane" and cf.base:GetTexture():find("CardTactic$"),
    "a tactic says what it targets and has a tactic's frame")
  check(not cf.atk:IsShown() and not cf.hpBg:IsShown(), "and no attack or health")
  check(plain(cf.text:GetText()) == Cards.byId.fireball.short, "its rules text is on the card")
  cf:SetCard("footpad")
  check(cf.atk:IsShown() and cf.base:GetTexture():find("CardUnit$"), "back to a unit: the stats come back")
  check(plain(cf.text:GetText()):find("Stealth"), "keywords are on the card")
  cf:SetTag("dies", 1, 0.3, 0.3)
  check(cf.tagBg:IsShown(), "a tag has a dark bar behind it")
  cf:SetCard("footpad")
  check(not cf.tagBg:IsShown() and cf.tag:GetText() == "", "and a new card clears it")
  cf:SetSelected(true)
  check(cf.sel:IsShown(), "a selected card glows")
  cf:SetSelected(false)
  cf:SetDim(true)
  check(cf.shade:IsShown() and not cf.sel:IsShown(), "an unplayable card is shaded")
  cf:SetBaseScale(0.9)
  check(cf.baseScale == 0.9, "a page can set the card's size")
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
  SlashCmdList.TRADEWINDS("options")
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

-- combat effects: a projectile for every strike, a ghost for every death,
-- nothing left running afterwards, and skipping finishes them at once
do
  local FX = UI.FX
  G.Start("dorn")
  local st = db.match.st
  local function put(p, lane, id)
    local u = R.Summon(st, p, lane, id)
    u.new = nil
    return u
  end
  for p = 1, 2 do st.players[p].board = {} end
  put(1, 1, "bear"); put(1, 3, "axe"); put(1, 4, "gryphon")
  put(2, 1, "bat"); put(2, 2, "grunt"); put(2, 3, "ogre"); put(2, 4, "kobold")
  st.players[1].hand = {}
  st.players[2].hand = {}
  local before = {}
  for k, v in pairs(FX.counts) do before[k] = v end
  local function made(kind) return (FX.counts[kind] or 0) - (before[kind] or 0) end
  G.LockIn()
  MOCK.Advance(1.2)
  local m = db.match
  local ev = m.last.events
  local strikes, deaths, drains, tactics = 0, 0, 0, 0
  for _, e in ipairs(ev) do
    if e.t == "strike" then strikes = strikes + 1
    elseif e.t == "die" then deaths = deaths + 1
    elseif e.t == "fx" and e.kind == "drain" then drains = drains + #e.lanes
    elseif e.t == "tactic" and e.lane then tactics = tactics + 1 end
  end
  check(FX.Busy(), "effects play while the round does")
  MOCK.Advance(60)
  check(m.shown == true and not FX.Busy(), "and are all finished when it's over")
  check(strikes >= 6 and made("projectile") == strikes + drains + tactics,
    ("a projectile for every strike (%d strikes, %d projectiles)"):format(strikes, made("projectile")))
  check(deaths >= 1 and made("death") == deaths, ("a ghost for every death (%d)"):format(deaths))
  check(made("banner") >= 2 and made("callout") >= 4 and made("number") >= strikes, "banners, callouts and numbers")
  -- frozen and stealthed units look it
  st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  local ice = put(1, 1, "grunt")
  ice.frozen = true
  put(1, 2, "footpad")
  G.Refresh()
  local s1, s2 = G.api.slot(1, 1).card, G.api.slot(1, 2).card
  check(s1.frost:IsShown() and not s1.veil:IsShown(), "a frozen unit is iced over")
  check(s2.veil:IsShown() and not s2.frost:IsShown(), "a stealthed unit is veiled")
  ice.frozen = nil
  G.Refresh()
  check(not s1.frost:IsShown(), "and the ice goes when it thaws")
  -- the hand: full size when it fits, a little smaller when even the whole
  -- page is too narrow
  do
    local hand = st.players[1].hand
    local saved = {}
    for i, id in ipairs(hand) do saved[i] = id end
    for i = #hand, 1, -1 do hand[i] = nil end
    for i = 1, 7 do hand[i] = i == 1 and "kobold" or "fireball" end
    G.Refresh()
    local k = G.api.handFrame("kobold")
    check(k and k.baseScale < 1 and k.baseScale > 0.95, ("seven cards fit the page (scale %.3f)"):format(k and k.baseScale or 0))
    for i = 7, 4, -1 do hand[i] = nil end
    G.Refresh()
    check(G.api.handFrame("kobold").baseScale == 1, "three are full size")
    for i = #hand, 1, -1 do hand[i] = nil end
    for i, id in ipairs(saved) do hand[i] = id end
    G.Refresh()
  end
  -- a fresh round counts down first; the Replay button doesn't
  check((FX.counts.countdown or 0) - (before.countdown or 0) == 1, "a new round counts down: 3, 2, 1, Reveal!")
  local cd0 = FX.counts.countdown
  G.Replay()
  MOCK.Advance(60)
  check(FX.counts.countdown == cd0, "the Replay button doesn't count down again")
  -- the lanes: lights flow the way the damage goes
  st = db.match.st
  for p = 1, 2 do st.players[p].board = {} end
  st.players[1].hand, st.players[2].hand = {}, {}
  put(1, 1, "grunt")                 -- hits their Morale
  put(2, 2, "grunt")                 -- hits yours
  put(1, 3, "grunt"); put(2, 3, "grunt")   -- a fight
  G.Refresh()
  local function shownPips(l, up)
    local n = 0
    for _, pip in ipairs(G.api.marker(l).pips) do
      if pip:IsShown() and pip.up == up then n = n + 1 end
    end
    return n
  end
  local m1, m2, m3, m4 = G.api.marker(1), G.api.marker(2), G.api.marker(3), G.api.marker(4)
  check(m1.state == "out" and shownPips(1, true) == 4 and shownPips(1, false) == 0 and not m1.clash:IsShown(),
    "lane 1 (you hit their Morale): lights flow up")
  check(m2.state == "in" and shownPips(2, false) == 4 and shownPips(2, true) == 0, "lane 2 (they hit you): lights flow down")
  check(m3.state == "fight" and shownPips(3, true) == 4 and shownPips(3, false) == 4 and m3.clash:IsShown(),
    "lane 3 (a fight): in from both sides to a clash")
  check(shownPips(4, true) + shownPips(4, false) == 0 and not m4.clash:IsShown(), "lane 4 (empty): still")
  MOCK.Advance(0.5)                  -- the lights move without errors
  check(G.api.marker(1).state == "out", "and keep flowing")
  -- rounds left
  st.round = R.MAX_ROUNDS - 1
  G.Refresh()
  check(G.api.roundText():find("1 round left"), "the round counter says how many are left")
  check(G.api.roundNumber() == ("%d/%d"):format(R.MAX_ROUNDS - 1, R.MAX_ROUNDS), "and the big counter shows the round")
  st.round = R.MAX_ROUNDS
  G.Refresh()
  check(G.api.roundText() == "Final round", "and calls the last one")
  st.round = 2
  -- skipping
  st.players[2].board = {}
  put(2, 1, "grunt"); put(2, 3, "grunt")
  G.LockIn()
  MOCK.Advance(1.2)
  check(FX.Busy(), "effects running")
  G.Skip()
  check(not FX.Busy(), "skipping finishes them at once")
  MOCK.Advance(60)
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

-- the end screen: stars stamp in, shards and packs count up, the cards won
-- turn over; Rematch, Next opponent and Back
do
  local ov = G.api.over()
  db.stars.graves, db.stars.prestor, db.record.graves, db.record.prestor = nil, nil, nil, nil
  db.collection.rivendare = nil
  db.stars.pellwick = { true }
  G.Start("graves")
  local st = db.match.st
  for p = 1, 2 do st.players[p].board = {}; st.players[p].hand = {} end
  st.players[2].morale = 0
  G.LockIn()
  for _ = 1, 400 do
    if not db.match then break end
    MOCK.Advance(0.05)
  end
  check(db.match == nil and ov:IsShown(), "the game is over")
  check(ov.stars[1]:GetAlpha() < 1, "a star earned now stamps in, a moment later")
  MOCK.Advance(3)
  check(ov.stars[1]:GetAlpha() == 1 and ov.stars[2]:GetAlpha() == 1, "the stars earned are lit")
  local facts = G.GameOverFacts()
  check(facts:find("Star earned") and facts:find("Rivendare"), "the facts list the stars and the card")
  check(ov.cards[1]:IsShown() and ov.cards[1].card.cardId == "rivendare" and ov.cards[1].card:GetAlpha() == 1,
    "the signature card is shown face up")
  check(ov.gains[1]:IsShown() and ov.gains[1].num:GetText():find("shard"), "the shards won are counted up")
  check(ov.rematch:IsShown() and ov.nextOpp:IsShown() and ov.nextOpp:GetText():find("Prestor"),
    "Rematch, and the opponent just unlocked")
  check(ov.share:IsShown() and (G.ShareText() or ""):find("star against Graves"), "Share: a line about the star")
  MOCK.chatBox = nil
  ov.share:Click()
  check(MOCK.chatBox and MOCK.chatBox:find("star against Graves") and not MOCK.chatBox:find("|c"),
    "the Share button puts it in the chat box, in plain text")
  MOCK.chatBox = nil
  check(G.NextOpponent() and db.match.opp == "prestor", "Next opponent starts them at once")
  G.EndMatch()
  check(ov.rematch:IsShown() and not ov.nextOpp:IsShown(), "after a loss: Rematch, no next opponent")
  check(not ov.share:IsShown() and G.ShareText() == nil, "nothing to share after a loss")
  check(G.Rematch() and db.match.opp == "prestor", "Rematch starts the same opponent at once")
  G.EndMatch(); G.Continue()
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
  check(MOCK.popup and MOCK.popup.name == "TRADEWINDS_CRAFT" and db.collection.kazzak == nil, "crafting asks first")
  StaticPopupDialogs.TRADEWINDS_CRAFT.OnAccept()
  check(db.collection.kazzak == 1 and db.shards == 3, "confirmed: the card is made and the shards spent")
  StaticPopupDialogs.TRADEWINDS_CRAFT.OnAccept()
  check(db.collection.kazzak == 1 and db.shards == 3, "confirming twice makes one card")
  MOCK.shift = false

  -- filters
  local total = #UI.Binder.Shown()
  check(total == #Cards.collectible, "no filters: every card")
  UI.Binder.SetFilter("tribe", "murloc")
  local murlocs = UI.Binder.Shown()
  local allMurlocs = #murlocs > 0
  for _, c in ipairs(murlocs) do if c.tribe ~= "murloc" then allMurlocs = false end end
  check(allMurlocs, "filter by tribe (" .. #murlocs .. " Murlocs)")
  check(UI.Binder.Progress():find("Murloc: collected %d+ of " .. #C.TribeCards("murloc")), "and the header counts the tribe")
  UI.Binder.SetFilter("tribe", "all")
  UI.Binder.SetFilter("kind", "item")
  local items = UI.Binder.Shown()
  local allItems = #items > 0
  for _, c in ipairs(items) do if not c.item then allItems = false end end
  check(allItems and #items == 18, "filter by type: items (" .. #items .. ")")
  UI.Binder.SetFilter("kind", "tactic")
  local noItems = true
  for _, c in ipairs(UI.Binder.Shown()) do if c.item or c.type ~= "tactic" then noItems = false end end
  check(noItems, "and tactics without them")
  UI.Binder.SetFilter("kind", "trap")
  local traps = UI.Binder.Shown()
  local allTraps = #traps == 8
  for _, c in ipairs(traps) do if c.type ~= "trap" then allTraps = false end end
  check(allTraps, "filter by type: traps (" .. #traps .. ")")
  UI.Binder.SetFilter("kind", "all")
  UI.Binder.SetFilter("rarity", "legendary")
  check(#UI.Binder.Shown() == #Cards.byRarity.legendary, "filter by rarity")
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

  -- scrolling: the wheel moves a row, the arrows a page, and it stops at the end
  check(UI.Binder.TopRow() == 0, "the list starts at the top")
  UI.Binder.Scroll(1)
  check(UI.Binder.TopRow() == 1, "a notch of the wheel scrolls one row")
  UI.Binder.Scroll(-5)
  check(UI.Binder.TopRow() == 0, "and not above the top")
  UI.Binder.Scroll(1000)
  local rows = math.ceil(#Cards.collectible / 5)
  check(UI.Binder.TopRow() == rows - 3, ("and not past the last row (%d of %d)"):format(UI.Binder.TopRow(), rows))
  UI.Binder.SetFilter("own", "all")
  check(UI.Binder.TopRow() == 0, "a new filter goes back to the top")

  -- the deck panel shows a strip per card, the curve and whether it's ready
  UI.Binder.Refresh()
  local dv = UI.Binder.DeckView()
  local distinct, nu = {}, 0
  for _, id in ipairs(db.deck) do
    distinct[id] = true
    if Cards.byId[id].type == "unit" then nu = nu + 1 end
  end
  local nd = 0
  for _ in pairs(distinct) do nd = nd + 1 end
  check(dv.count == "20/20" and dv.note == "Ready to play.", "a full deck is ready: " .. tostring(dv.note))
  check(dv.rows == nd, ("a strip per different card (%d)"):format(dv.rows))
  check(dv.units == ("%d units"):format(nu) and dv.tactics == ("%d tactics"):format(20 - nu), "units and tactics counted")

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
  check(TradewindsToast and TradewindsToast:IsShown(), "flight toast")
  SlashCmdList.TRADEWINDS("")
  -- the board's look follows how you travel, picked when a game goes on it
  db.settings.board = "auto"
  G.Start("dorn")
  check(G.BoardSkin() == "sky", "on a flight the board is the evening sky")
  G.EndMatch(); G.Continue()
  MOCK.Advance(C.TRAVEL_PACK_SECONDS + 5)
  check(db.packs == packs + 1, "a pack for 20 minutes in the air")
  MOCK.speed = 7               -- landed, but UnitOnTaxi still says yes (seen on the live client)
  MOCK.Advance(2)
  check(not ns.Travel.IsFlying() and not TradewindsFrame:IsShown(), "landing detected by speed, window closed")
  MOCK.onTaxi = false
end

-- a boat: standing still while being carried along; the ride ends at the dock
do
  local T = ns.Travel
  UI.Hide()
  local packs = db.packs
  db.progress.travel = 0
  MOCK.speed = 0
  MOCK.posX, MOCK.posY, MOCK.inst = 100, 100, 0
  local function sail(sec, dx)
    for _ = 1, sec do
      MOCK.posX = MOCK.posX + dx
      MOCK.Advance(1)
    end
  end
  sail(4, 0)
  check(not T.IsRiding(), "standing still isn't a ride")
  MOCK.speed = 7
  sail(T.RIDE_START + 2, 7)
  check(not T.IsRiding(), "walking isn't a ride")
  MOCK.speed = 0
  sail(T.RIDE_START + 1, 8)
  check(T.IsRiding() and TradewindsToast:IsShown(), "carried along while standing still: a ride, and the toast")
  G.Start("dorn")
  check(G.BoardSkin() == "ship", "on a boat the board is a ship's deck")
  G.EndMatch(); G.Continue()
  UI.Options.Set("board", "sky")
  check(G.BoardSkin() == "sky", "a board picked in Options applies at once")
  UI.Options.Set("board", "auto")
  -- A loading screen between continents. The client closes the windows in
  -- UISpecialFrames when you arrive (closeAt = "arrive"), or possibly as you
  -- leave, before our handler sees the event (closeAt = "leave").
  local function closeSpecialFrames()
    for _, name in ipairs(UISpecialFrames) do
      if _G[name] then _G[name]:Hide() end
    end
  end
  local function loadingScreen(closeAt)
    if closeAt == "leave" then closeSpecialFrames() end
    MOCK.Fire("PLAYER_LEAVING_WORLD")
    MOCK.posX, MOCK.inst = MOCK.posX + 5000, (MOCK.inst or 0) + 1
    if closeAt == "arrive" then closeSpecialFrames() end
    MOCK.Fire("PLAYER_ENTERING_WORLD")
  end
  UI.Show()
  loadingScreen("arrive")
  check(not TradewindsFrame:IsShown(), "(the client closed the window on arrival)")
  MOCK.Advance(1)
  sail(3, 8)
  check(T.IsRiding(), "the ride carries on after a loading screen")
  check(TradewindsFrame:IsShown(), "and the window opens again on the far side")
  loadingScreen("leave")
  MOCK.Advance(1)
  sail(2, 8)
  check(TradewindsFrame:IsShown(), "also when the client closes it as you leave")
  loadingScreen("arrive")
  MOCK.Advance(1)
  sail(T.RIDE_STOP + 2, 0)
  check(T.IsRiding() and TradewindsFrame:IsShown(), "standing still just after a loading screen isn't docking")
  sail(T.LOAD_GRACE, 8)
  UI.Hide()
  MOCK.Advance(2)
  loadingScreen("arrive")
  MOCK.Advance(2)
  check(not TradewindsFrame:IsShown(), "a window you closed yourself stays closed")
  SlashCmdList.TRADEWINDS("")
  sail(C.TRAVEL_PACK_SECONDS, 8)
  check(db.packs == packs + 1, "a pack for 20 minutes on board")
  sail(T.RIDE_STOP + 1, 0)
  check(not T.IsRiding() and not TradewindsFrame:IsShown(), "docked: the ride ends and the window closes")
  SlashCmdList.TRADEWINDS("travel log")
  MOCK.chat = {}
  MOCK.Advance(2)
  check(#MOCK.chat == 2 and MOCK.chat[1]:find("travel: speed 0.0, moved 0.0 yd"), "the travel log prints a line a second")
  SlashCmdList.TRADEWINDS("travel log")
  SlashCmdList.TRADEWINDS("travel")
  check(MOCK.chat[#MOCK.chat]:find("not travelling"), "/tradewinds travel")
  MOCK.posX = nil
end

-- /tradewinds probe: a line per question, and it never errors
do
  MOCK.chat = {}
  SlashCmdList.TRADEWINDS("probe")
  local lines = 0
  for _, l in ipairs(MOCK.chat) do
    if l:find("probe") then lines = lines + 1 end
  end
  check(lines >= 9, "the probe prints a line per question (" .. lines .. ")")
  check(MOCK.chat[#MOCK.chat]:find("not tried: you're not in a guild"), "not in a guild: no guild message")
  MOCK.guild = { { name = "Tester-Realm", online = true } }
  MOCK.sent = {}
  SlashCmdList.TRADEWINDS("probe")
  local sent = MOCK.sent[#MOCK.sent]
  check(sent and sent.chatType == "GUILD" and sent.msg:find("^PB;%d+$"), "in a guild: it sends a guild addon message")
  MOCK.Advance(0.5)
  MOCK.Fire("CHAT_MSG_ADDON", "Tradewinds", sent.msg, "GUILD", "Tester-Realm")
  check(MOCK.chat[#MOCK.chat]:find("arrived after") and MOCK.chat[#MOCK.chat]:find("is you"), "and says when it comes back")
  SlashCmdList.TRADEWINDS("probe")
  MOCK.Advance(ns.Probe.GUILD_WAIT + 1)
  check(MOCK.chat[#MOCK.chat]:find("did NOT come back"), "or that it didn't")
  MOCK.guild = nil
end

-- other events and slash commands
do
  local packs, special = db.packs, db.specialPacks
  local shards = db.shards
  MOCK.Fire("PLAYER_LEVEL_UP", 23)
  MOCK.Fire("UI_INFO_MESSAGE", 0, "New flight path discovered!")
  check(db.packs == packs and db.shards == shards + C.REWARD.level + C.REWARD.flightPath, "a level and a new flight path give shards")
  check(db.ach.flightpath ~= nil, "and the flight path earns its achievement straight away")
  MOCK.Fire("PLAYER_LEVEL_UP", 30)
  check(db.packs == packs and db.specialPacks == special + 1 and db.shards == shards + 2 * C.REWARD.level + C.REWARD.flightPath,
    "every tenth level gives a Windfall pack too")
  SlashCmdList.TRADEWINDS("")
  MOCK.Fire("PLAYER_REGEN_DISABLED")
  check(not TradewindsFrame:IsShown(), "combat closes the window")
  for _, cmd in ipairs({ "help", "rules", "icons", "speed 3", "scale 0.9", "reset", "toast off", "minimap off", "minimap on", "packs", "cards", "play" }) do
    SlashCmdList.TRADEWINDS(cmd)
  end
  check(db.settings.speed == 3 and db.settings.toast == false, "settings commands")
end

-- Records: achievements by group, a toast for each one earned, sharing
do
  local Rec = UI.Records
  SlashCmdList.TRADEWINDS("records")
  check(UI.tab == "records" and Rec.View() == "ach", "/tradewinds records opens the Records tab")
  db.ach.morale100, db.ach.kills100, db.ach.morale1000 = nil, nil, nil
  db.life.morale, db.life.kills = 40, 20
  Rec.ShowGroup("play")
  check(Rec.Group() == "play" and (Rec.RowText(1) or ""):find("Pressure") and Rec.RowText(1):find("40 / 100"),
    "a group's achievements, with progress toward each")
  for _ = 1, 80 do   -- the toasts of everything earned so far
    if not UI.AchievementShown() then break end
    MOCK.Advance(UI.ACH_SECONDS + 0.1)
  end
  check(UI.AchievementShown() == nil, "earlier toasts have all been shown")
  MOCK.chat = {}
  db.life.morale, db.life.kills = 150, 150
  ns.CheckAchievements()
  local a, waiting, toast = UI.AchievementShown()
  check(a and a.id == "morale100" and waiting == 1 and toast:IsShown(), "a toast for each achievement, one at a time")
  check(#MOCK.chat == 2 and MOCK.chat[1]:find("Achievement earned") and MOCK.chat[1]:find("Pressure"), "and a line in chat for each")
  check(db.ach.morale100 == "2026-11-19" and (Rec.RowText(1) or ""):find("Earned 2026%-11%-19"), "the Records tab shows the date")
  MOCK.chatBox = nil
  toast.share:Click()
  check((MOCK.chatBox or ""):find("Achievement earned: Pressure"), "the toast's Share button")
  MOCK.chatBox = nil
  MOCK.Advance(UI.ACH_SECONDS + 0.1)
  a = UI.AchievementShown()
  check(a and a.id == "kills100", "then the next one")
  UI.SelectTab("cards")
  toast:Click()
  check(UI.tab == "records" and Rec.Group() == "play" and not toast:IsShown(), "clicking a toast opens its group")
  check(UI.AchievementShown() == nil, "the queue is empty")
  -- a character from before achievements: one line, no toasts
  db.ach.morale100, db.ach.kills100 = nil, nil
  db.progress.achQuiet = true
  MOCK.chat = {}
  ns.CheckAchievements()
  check(#MOCK.chat == 1 and MOCK.chat[1]:find("you already have 2 achievements") and UI.AchievementShown() == nil,
    "what an existing character already has comes in one line")
  -- every group fits the tab
  for _, g in ipairs(ns.ACH_GROUPS) do
    Rec.ShowGroup(g.key)
    local n = 0
    for _, x in ipairs(ns.Achievements) do if x.group == g.key then n = n + 1 end end
    check(Rec.RowText(n) ~= nil and Rec.RowText(n + 1) == nil, "every achievement of " .. g.key .. " has a row")
  end
  -- sharing without a chat box to fill: a box to copy from
  local saved = { ChatFrame_OpenChat, ChatFrameUtil, ChatEdit_GetActiveWindow }
  ChatFrame_OpenChat, ChatFrameUtil, ChatEdit_GetActiveWindow = nil, nil, nil
  UI.Share("copy me")
  check(MOCK.popup and MOCK.popup.name == "TRADEWINDS_COPY" and UI.Copying() == "copy me", "no chat box: a box to copy the line from")
  ChatFrame_OpenChat, ChatFrameUtil, ChatEdit_GetActiveWindow = saved[1], saved[2], saved[3]
  StaticPopup_Hide("TRADEWINDS_COPY")
  MOCK.chatBox = "hello"
  UI.Share(" there")
  check(MOCK.chatBox == "hello there", "a chat box already open gets the line added")
  MOCK.chatBox = nil
end

-- deck codes: the deck as text, and a code loaded back
do
  local B, N = UI.Binder, ns.Net
  UI.SelectTab("cards")
  C.ResetDeck(db)
  local code = B.DeckCode()
  check(code and code:match("^TW1:%w+$") and #code == 4 + 40 + 2, "a deck code: TW1: and the cards (" .. tostring(code) .. ")")
  local list = N.ReadDeckCode(code)
  local same = list and #list == 20
  for i, id in ipairs(list or {}) do if id ~= db.deck[i] then same = false end end
  check(same, "it reads back as the same deck")
  check(N.ReadDeckCode("  " .. code:lower() .. " ") ~= nil, "spaces and lower case don't matter")
  local _, why = N.ReadDeckCode(code:sub(1, -2) .. (code:sub(-1) == "0" and "1" or "0"))
  check(why == "version", "a code that fails its check is from another version")
  _, why = N.ReadDeckCode("hello there")
  check(why == "code", "and text that isn't a code says so")
  B.ShowCode()
  check(MOCK.popup and MOCK.popup.name == "TRADEWINDS_DECKCODE" and MOCK.popup.arg == db.deckSlot, "the Code button opens the code box")
  -- someone else's deck, with cards you don't have
  local theirs = {}
  for i, id in ipairs(C.STARTER) do theirs[i] = id end
  local missingId
  for _, c in ipairs(Cards.collectible) do
    if c.rarity == "epic" and C.Owned(db, c.id) == 0 then missingId = c.id; break end
  end
  theirs[20] = missingId
  MOCK.chat = {}
  local errors = #MOCK.errors
  check(B.LoadCode("garbage") == false and #MOCK.errors == errors + 1, "a bad code: an error, and the deck is left alone")
  local ok, missing = B.LoadCode(N.DeckCode(theirs))
  check(ok and #db.deck == 19 and #missing == 1 and missing[1].id == missingId, "loading a code: the cards you own go in")
  local said = table.concat(MOCK.chat, "\n")
  check(said:find("without 1 card") and said:find(Cards.byId[missingId].name, 1, true) and said:find("shards to craft")
    and said:find("Not ready to play yet"), "the missing card is listed with its crafting cost, and the deck says it isn't ready")
  C.ResetDeck(db)
  B.Refresh()
end

-- the guild board, on one client (tests/pvp.lua has two talking)
do
  local Gd, N, Rec = ns.Guild, ns.Net, UI.Records
  MOCK.guild = { { name = "Tester-Realm", online = true }, { name = "Gwen-Realm", online = true }, { name = "Hal-Realm", online = false } }
  local ver = ns.VERSION
  N.Receive("Gwen-Realm", ("LB;%s;12;1;80;%d;150;3"):format(ver, #Cards.collectible), "GUILD")
  N.Receive("Hal-Realm", ("LB;0.16.0;24;8;90;%d;400;9"):format(#Cards.collectible), "GUILD")
  check(db.guildBoard["Gwen-Realm"] and db.guildBoard["Gwen-Realm"].points == 150 and db.guildBoard["Hal-Realm"],
    "guildmates' progress is kept")
  N.Receive("Ivy-Realm", ("LB;%s;12;1;80;%d;150;3"):format(ver, #Cards.collectible), "WHISPER")
  N.Receive("Ivy-Realm", "LB;" .. ver .. ";1;1;999;10;5;0", "GUILD")
  N.Receive("Ivy-Realm", "LB;" .. ver .. ";1;1;1", "GUILD")
  N.Receive("Ivy-Realm", "LB;" .. ver .. ";-1;1;1;10;5;0", "GUILD")
  N.Receive("Ivy-Realm", "LB;0.1|cff;1;1;1;10;5;0", "GUILD")
  N.Receive("Ivy-Realm", "LB;" .. ver .. ";1;1;1;10;5;99999999999", "GUILD")
  check(db.guildBoard["Ivy-Realm"] == nil, "a progress line by whisper, or with a bad field, is ignored")
  MOCK.sent = {}
  UI.SelectTab("records")
  Rec.SetView("guild")
  local guildSent = 0
  for _, m in ipairs(MOCK.sent) do if m.chatType == "GUILD" and m.msg == "LQ" then guildSent = guildSent + 1 end end
  check(guildSent == 1 and (MOCK.rosterAsked or 0) > 0, "opening the guild board asks the guild, and the roster")
  Rec.SetView("ach"); Rec.SetView("guild")
  guildSent = 0
  for _, m in ipairs(MOCK.sent) do if m.chatType == "GUILD" and m.msg == "LQ" then guildSent = guildSent + 1 end end
  check(guildSent == 1, "at most once every 5 minutes")
  local rows = Rec.BoardRows()
  check(#rows == 3 and rows[1].points >= rows[2].points, "the board: you and two guildmates, most points first")
  local gwen, hal
  for _, r in ipairs(rows) do
    if r.short == "Gwen" then gwen = r elseif r.short == "Hal" then hal = r end
  end
  check(gwen and Gd.CanPlay(gwen) and hal and not Gd.CanPlay(hal), "Challenge and Trade: online and on your version only")
  Rec.SortBy("name")
  rows = Rec.BoardRows()
  check(rows[1].short == "Gwen" and rows[2].short == "Hal" and rows[3].you, "sorted by name")
  Rec.SortBy("name")
  check(Rec.BoardRows()[1].you, "click again: the other way round")
  -- an old entry goes after 30 days
  db.guildBoard["Hal-Realm"].seen = time() - 31 * 86400
  check(#Rec.BoardRows() == 2 and db.guildBoard["Hal-Realm"] == nil, "a guildmate not heard from for 30 days is dropped")
  -- sharing off: nothing goes out
  db.settings.guildShare = false
  MOCK.sent = {}
  Gd.Reset()
  Gd.OnLQ()
  MOCK.Advance(120)
  local any = false
  for _, m in ipairs(MOCK.sent) do if m.chatType == "GUILD" then any = true end end
  check(not any, "with sharing off, nothing is sent to the guild")
  db.settings.guildShare = true
  Rec.SetView("ach")
  MOCK.guild = nil
end

-- a long session: many more matches don't grow the effect pools, the log
-- or the saved data, and a board refresh stays cheap
do
  local FX = UI.FX
  db.settings.speed = 1
  SlashCmdList.TRADEWINDS("play")
  playGame("dorn")
  local tex, text, ghost = FX.PoolSizes()
  for _ = 1, 6 do playGame("bluegill") end
  local tex2, text2, ghost2, running = FX.PoolSizes()
  check(tex2 <= tex + 40 and text2 <= text + 20 and ghost2 <= ghost + 8,
    ("effect pools stay bounded (%d/%d/%d -> %d/%d/%d)"):format(tex, text, ghost, tex2, text2, ghost2))
  check(running == 0, "no effects left running between matches")
  G.Start("dorn")
  for _ = 1, 3 do
    autoPlan(); G.LockIn(); MOCK.Advance(60)
  end
  check(#(db.match.log or {}) <= 80, "the saved log is capped")
  local t0 = os.clock()
  for _ = 1, 200 do G.Refresh() end
  local ms = (os.clock() - t0) / 200 * 1000
  check(ms < 5, ("a board refresh takes %.2f ms in the test (under 5)"):format(ms))
  G.EndMatch()
  G.Continue()
end

-- the addon only creates the globals it means to
do
  local allowed = { TradewindsCharDB = true, Tradewinds_Toggle = true, SLASH_TRADEWINDS1 = true,
    BINDING_HEADER_TRADEWINDS = true, BINDING_NAME_TRADEWINDS_TOGGLE = true, TradewindsFrame = true,
    TradewindsToast = true, TradewindsMinimapButton = true }
  local leaked = {}
  for k in pairs(_G) do
    if not globalsBefore[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end
  end
  table.sort(leaked)
  check(#leaked == 0, "no stray globals (" .. table.concat(leaked, ", ") .. ")")
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
