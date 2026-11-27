-- Achievements: points only, nothing that changes the collection pace.
--
-- Each has an id (saved in db.ach: never rename one), a group, points, a
-- name, a line of text, icons (the first this client has wins) and a
-- progress function: progress(db) returns how far along you are and the
-- goal; it's earned when the first reaches the second. Most read what the
-- save already holds (stars, cards, records); the rest read the lifetime
-- counters in db.life (Collection.AddLife), which started at zero in 0.18.0.
-- scale: the bar shows the numbers divided by this (travel: minutes).
local _, ns = ...
local L = ns.L

local I = "Interface\\Icons\\"

ns.ACH_GROUPS = {
  { key = "circuit", name = L["Circuit"], icon = { I .. "Achievement_BG_winWSG", I .. "INV_Misc_Ticket_Darkmoon_01" } },
  { key = "collection", name = L["Collection"], icon = { I .. "INV_Misc_Book_09", I .. "INV_Misc_Book_11" } },
  { key = "play", name = L["Battles"], icon = { I .. "Ability_Warrior_BattleShout", I .. "INV_Sword_04" } },
  { key = "travel", name = L["Travel"], icon = { I .. "Ability_Mount_Gryphon_01", I .. "INV_Misc_Map_01" } },
  { key = "players", name = L["Players"], icon = { I .. "Achievement_Arena_2v2_1", I .. "Ability_Warrior_Challange" } },
  { key = "traps", name = L["Traps"], icon = { I .. "Spell_Fire_FlameShock", I .. "INV_Misc_Bomb_04" } },
  { key = "oddities", name = L["Oddities"], icon = { I .. "INV_Misc_Dice_01", I .. "INV_Misc_QuestionMark" } },
}

local function C() return ns.Collection end

local function life(key, goal)
  return function(db) return C().Life(db, key), goal end
end

-- opponents with at least star i; and every star
local function withStar(i)
  return function(db)
    local n = 0
    for _, o in ipairs(ns.Opponents) do
      if db.stars[o.id] and db.stars[o.id][i] then n = n + 1 end
    end
    return n
  end
end

local function stars(db)
  local n = 0
  for _, o in ipairs(ns.Opponents) do n = n + select(2, C().Stars(db, o.id)) end
  return n
end

local function heroics(db)
  local n = 0
  for _, o in ipairs(ns.Opponents) do
    if db.heroic[o.id] and db.heroic[o.id].beaten then n = n + 1 end
  end
  return n
end

local function owned(db)
  local n = 0
  for _, c in ipairs(ns.Cards.collectible) do
    if C().Owned(db, c.id) > 0 then n = n + 1 end
  end
  return n
end

local function holos(db)
  local n = 0
  for _, c in ipairs(ns.Cards.collectible) do
    if C().IsHolo(db, c.id) then n = n + 1 end
  end
  return n
end

local function pvpWins(db)
  local n = 0
  for _, rec in pairs(db.pvpRecord or {}) do
    if type(rec) == "table" then n = n + (tonumber(rec.w) or 0) end
  end
  return n
end
ns.PvPWins = pvpWins

local function played(db)
  local s = db.stats
  return (s.wins or 0) + (s.losses or 0) + (s.draws or 0)
end

local function flag(fn)
  return function(db) return fn(db) and 1 or 0, 1 end
end

local nOpp = #ns.Opponents
local half = math.floor(nOpp / 2)

ns.Achievements = {
  -- the tavern circuit
  { id = "tutorial", group = "circuit", points = 5, name = L["Pull up a stool"], text = L["Finish the tutorial."],
    icon = { I .. "INV_Misc_Note_01" }, progress = flag(function(db) return db.tutorial and db.tutorial.done end) },
  { id = "firstwin", group = "circuit", points = 5, name = L["First round's on me"], text = L["Beat an opponent on the circuit."],
    icon = { I .. "INV_Drink_05" }, progress = function(db) return math.min(1, withStar(1)(db)), 1 end },
  { id = "halfway", group = "circuit", points = 10, name = L["Halfway round the room"],
    text = L["Beat %d opponents on the circuit."]:format(half),
    icon = { I .. "INV_Misc_Ticket_Tarot_Portal", I .. "INV_Misc_Ticket_Darkmoon_01" },
    progress = function(db) return withStar(1)(db), half end },
  { id = "circuit", group = "circuit", points = 20, name = L["Cleared the tables"], text = L["Beat every opponent on the circuit."],
    icon = { I .. "Achievement_BG_winWSG", I .. "INV_Misc_Trophy_01" }, progress = function(db) return withStar(1)(db), nOpp end },
  { id = "decisive", group = "circuit", points = 10, name = L["No contest"], text = L["Earn a Decisive star."],
    icon = { I .. "Ability_Warrior_Decisivestrike", I .. "Ability_Warrior_Rampage" },
    progress = function(db) return math.min(1, withStar(2)(db)), 1 end },
  { id = "plain", group = "circuit", points = 10, name = L["Common touch"], text = L["Earn a Rank and file star."],
    icon = { I .. "INV_Misc_Coin_02" }, progress = function(db) return math.min(1, withStar(3)(db)), 1 end },
  { id = "stars15", group = "circuit", points = 20, name = L["Constellation"], text = L["Earn 15 stars."],
    icon = { I .. "Spell_Arcane_StarFire", I .. "Spell_Nature_StarFall" }, progress = function(db) return stars(db), 15 end },
  { id = "allstars", group = "circuit", points = 50, name = L["Star of the tavern"], text = L["Earn every star on the circuit."],
    icon = { I .. "Spell_Nature_StarFall", I .. "Spell_Arcane_StarFire" }, progress = function(db) return stars(db), 3 * nOpp end },
  { id = "heroic", group = "circuit", points = 10, name = L["Heroic"], text = L["Win a heroic rematch."],
    icon = { I .. "Achievement_Dungeon_Heroic_GloryoftheRaider", I .. "INV_Shield_06" },
    progress = function(db) return math.min(1, heroics(db)), 1 end },
  { id = "allheroic", group = "circuit", points = 50, name = L["Legend of the tavern"], text = L["Win every heroic rematch."],
    icon = { I .. "INV_Misc_Crown_01", I .. "INV_Crown_01" }, progress = function(db) return heroics(db), nOpp end },

  -- the collection
  { id = "cards50", group = "collection", points = 10, name = L["Binder"], text = L["Own 50 different cards."],
    icon = { I .. "INV_Misc_Book_09" }, progress = function(db) return owned(db), 50 end },
  { id = "cards100", group = "collection", points = 20, name = L["Archivist"], text = L["Own 100 different cards."],
    icon = { I .. "INV_Misc_Book_11" }, progress = function(db) return owned(db), 100 end },
  { id = "cardsall", group = "collection", points = 50, name = L["Complete set"], text = L["Own one of every card."],
    icon = { I .. "INV_Misc_Book_06" }, progress = function(db) return owned(db), #ns.Cards.collectible end },
  { id = "legendary", group = "collection", points = 10, name = L["Legendary"], text = L["Own a legendary card."],
    icon = { I .. "INV_Misc_Gem_Pearl_04", I .. "INV_Jewelry_Talisman_07" },
    progress = flag(function(db)
      for _, c in ipairs(ns.Cards.collectible) do
        if c.rarity == "legendary" and C().Owned(db, c.id) > 0 then return true end
      end
    end) },
  { id = "holo", group = "collection", points = 10, name = L["Shiny"], text = L["Own a holographic card."],
    icon = { I .. "INV_Misc_Gem_Diamond_01", I .. "INV_Misc_Gem_Pearl_04" }, progress = function(db) return math.min(1, holos(db)), 1 end },
  { id = "holo10", group = "collection", points = 25, name = L["Hall of mirrors"], text = L["Own 10 holographic cards."],
    icon = { I .. "INV_Misc_Gem_Diamond_02", I .. "INV_Misc_Gem_Diamond_01" }, progress = function(db) return holos(db), 10 end },
  { id = "tribe", group = "collection", points = 20, name = L["Kin"], text = L["Own every card of one tribe."],
    icon = { I .. "INV_Misc_Head_Dragon_01", I .. "INV_Misc_Head_Murloc_01" },
    progress = function(db)
      local best, goal = 0, 1
      for _, t in ipairs(ns.Cards.TRIBE_ORDER) do
        local have, total = C().TribeProgress(db, t)
        if total > 0 and (have / total > best / goal) then best, goal = have, total end
      end
      return best, goal
    end },
  { id = "packs25", group = "collection", points = 10, name = L["Pack rat"], text = L["Open 25 packs."],
    icon = { I .. "INV_Misc_Bag_10" }, progress = function(db) return C().Life(db, "packs") + C().Life(db, "special"), 25 end },
  { id = "packs100", group = "collection", points = 25, name = L["Pack mule"], text = L["Open 100 packs."],
    icon = { I .. "INV_Misc_Bag_EnchantedMageweave", I .. "INV_Misc_Bag_10" },
    progress = function(db) return C().Life(db, "packs") + C().Life(db, "special"), 100 end },
  { id = "windfall", group = "collection", points = 5, name = L["Lucky break"], text = L["Open a Windfall pack."],
    icon = { I .. "INV_Misc_Ticket_Darkmoon_01" }, progress = life("special", 1) },
  { id = "craft", group = "collection", points = 5, name = L["Handiwork"], text = L["Craft a card."],
    icon = { I .. "INV_Enchant_ShardBrilliantSmall", I .. "Trade_Engraving" }, progress = life("crafted", 1) },

  -- battles
  { id = "morale100", group = "play", points = 10, name = L["Pressure"], text = L["Deal 100 Morale damage."],
    icon = { I .. "Ability_Warrior_Rampage", I .. "INV_Sword_04" }, progress = life("morale", 100) },
  { id = "morale1000", group = "play", points = 25, name = L["Siege"], text = L["Deal 1,000 Morale damage."],
    icon = { I .. "INV_Hammer_10", I .. "INV_Sword_04" }, progress = life("morale", 1000) },
  { id = "kills100", group = "play", points = 10, name = L["Cleanup crew"], text = L["Destroy 100 enemy units."],
    icon = { I .. "Ability_Rogue_Eviscerate", I .. "INV_Sword_04" }, progress = life("kills", 100) },
  { id = "kills1000", group = "play", points = 25, name = L["Gravedigger"], text = L["Destroy 1,000 enemy units."],
    icon = { I .. "INV_Misc_Bone_HumanSkull_01", I .. "INV_Misc_Bone_01" }, progress = life("kills", 1000) },
  { id = "units250", group = "play", points = 10, name = L["Muster"], text = L["Play 250 units."],
    icon = { I .. "Ability_Warrior_BattleShout" }, progress = life("units", 250) },
  { id = "tactics100", group = "play", points = 10, name = L["Bag of tricks"], text = L["Cast 100 tactics."],
    icon = { I .. "INV_Misc_Bag_07", I .. "Spell_Holy_MagicalSentry" }, progress = life("tactics", 100) },
  { id = "matches50", group = "play", points = 10, name = L["Familiar face"], text = L["Play 50 matches."],
    icon = { I .. "INV_Misc_Ticket_Tarot_Stack_01", I .. "INV_Misc_Ticket_Darkmoon_01" }, progress = function(db) return played(db), 50 end },
  { id = "wins100", group = "play", points = 25, name = L["Card shark"], text = L["Win 100 matches."],
    icon = { I .. "INV_Misc_Fish_14", I .. "INV_Misc_Coin_01" }, progress = function(db) return db.stats.wins or 0, 100 end },
  { id = "daily10", group = "play", points = 10, name = L["Daily bread"], text = L["Finish 10 daily tasks."],
    icon = { I .. "INV_Misc_Food_11", I .. "INV_Misc_Note_01" }, progress = life("dailies", 10) },

  -- travel
  { id = "travel1h", group = "travel", points = 5, name = L["Frequent flyer"], text = L["Travel for an hour with Tradewinds loaded."],
    icon = { I .. "Ability_Mount_Gryphon_01" }, progress = life("travel", 3600), scale = 60 },
  { id = "travel10h", group = "travel", points = 25, name = L["Wanderlust"], text = L["Travel for 10 hours with Tradewinds loaded."],
    icon = { I .. "INV_Misc_Map_01" }, progress = life("travel", 36000), scale = 60 },
  { id = "air10", group = "travel", points = 10, name = L["In-flight entertainment"],
    text = L["Play 10 rounds during a flight, boat or zeppelin ride."],
    icon = { I .. "Ability_Hunter_Pet_WindSerpent", I .. "Ability_Mount_Gryphon_01" }, progress = life("travelRounds", 10) },
  { id = "air100", group = "travel", points = 25, name = L["Mile-high table"], text = L["Play 100 rounds while travelling."],
    icon = { I .. "Ability_Druid_FlightForm", I .. "Ability_Mount_Gryphon_01" }, progress = life("travelRounds", 100) },
  { id = "flightpath", group = "travel", points = 5, name = L["New horizons"], text = L["Discover a flight path with Tradewinds loaded."],
    icon = { I .. "INV_Misc_Map02", I .. "INV_Misc_Map_01" }, progress = life("flightPaths", 1) },

  -- other players
  { id = "pvp1", group = "players", points = 10, name = L["Worthy opponent"], text = L["Finish a game against another player."],
    icon = { I .. "Ability_Warrior_Challange" }, progress = life("pvp", 1) },
  { id = "pvpwin", group = "players", points = 10, name = L["Bragging rights"], text = L["Win a game against another player."],
    icon = { I .. "Achievement_Arena_2v2_1", I .. "INV_BannerPVP_01" }, progress = function(db) return math.min(1, pvpWins(db)), 1 end },
  { id = "pvp10", group = "players", points = 25, name = L["Duellist"], text = L["Win 10 games against other players."],
    icon = { I .. "INV_BannerPVP_01", I .. "Ability_Warrior_Challange" }, progress = function(db) return pvpWins(db), 10 end },
  { id = "rival", group = "players", points = 10, name = L["Rivals"], text = L["Play 5 games against the same player."],
    icon = { I .. "Ability_Warrior_Disarm", I .. "Ability_Warrior_Challange" },
    progress = function(db)
      local best = 0
      for _, rec in pairs(db.pvpRecord or {}) do
        if type(rec) == "table" then
          best = math.max(best, (tonumber(rec.w) or 0) + (tonumber(rec.l) or 0) + (tonumber(rec.d) or 0))
        end
      end
      return best, 5
    end },
  { id = "trade1", group = "players", points = 10, name = L["Fair trade"], text = L["Complete a trade."],
    icon = { I .. "INV_Misc_Coin_01" }, progress = life("trades", 1) },
  { id = "trade10", group = "players", points = 25, name = L["Merchant prince"], text = L["Complete 10 trades."],
    icon = { I .. "INV_Misc_Coin_17", I .. "INV_Misc_Coin_01" }, progress = life("trades", 10) },
  { id = "guild3", group = "players", points = 10, name = L["The more the merrier"],
    text = L["Have 3 guildmates on your guild board."],
    icon = { I .. "INV_Misc_TabardSummer01", I .. "INV_Shirt_GuildTabard_01" },
    progress = function(db)
      local n = 0
      for _ in pairs(db.guildBoard or {}) do n = n + 1 end
      return n, 3
    end },

  -- traps
  { id = "trapset", group = "traps", points = 5, name = L["Lying in wait"], text = L["Set a trap."],
    icon = { I .. "Ability_Ensnare", I .. "Spell_Fire_FlameShock" }, progress = life("trapsSet", 1) },
  { id = "trapset50", group = "traps", points = 10, name = L["Minefield"], text = L["Set 50 traps."],
    icon = { I .. "INV_Misc_Bomb_04", I .. "INV_Misc_Bomb_02" }, progress = life("trapsSet", 50) },
  { id = "spring1", group = "traps", points = 5, name = L["Gotcha!"], text = L["Have one of your traps spring."],
    icon = { I .. "Spell_Fire_FlameShock", I .. "Spell_Fire_Immolation" }, progress = life("trapsSprung", 1) },
  { id = "spring25", group = "traps", points = 10, name = L["Trapper"], text = L["Have 25 of your traps spring."],
    icon = { I .. "Spell_Frost_ChainsOfIce", I .. "Spell_Frost_FrostNova" }, progress = life("trapsSprung", 25) },
  { id = "spring100", group = "traps", points = 25, name = L["Master trapper"], text = L["Have 100 of your traps spring."],
    icon = { I .. "Ability_Hunter_SnakeTrap", I .. "INV_Misc_Bomb_06" }, progress = life("trapsSprung", 100) },
  { id = "trapkill", group = "traps", points = 10, name = L["Snap!"],
    text = L["A unit that springs one of your traps dies that round."],
    icon = { I .. "INV_Misc_Bone_HumanSkull_01", I .. "Spell_Shadow_DeathScream" }, progress = life("trapKills", 1) },
  { id = "trapkill25", group = "traps", points = 25, name = L["Nobody gets through"],
    text = L["25 units that sprang one of your traps die that round."],
    icon = { I .. "INV_Shield_06", I .. "Ability_Warrior_ShieldWall" }, progress = life("trapKills", 25) },
  { id = "trapdouble", group = "traps", points = 10, name = L["Double trouble"], text = L["Have two of your traps spring in one round."],
    icon = { I .. "INV_Misc_Bomb_06", I .. "Spell_Fire_SelfDestruct" }, progress = life("trapDouble", 1) },
  { id = "sprungon", group = "traps", points = 5, name = L["Watch your step"], text = L["Spring one of your opponent's traps."],
    icon = { I .. "Ability_Rogue_Trip", I .. "Ability_Ensnare" }, progress = life("sprungOn", 1) },
  { id = "trapcards", group = "traps", points = 10, name = L["Tricks of the trade"], text = L["Own one of every trap."],
    icon = { I .. "INV_Misc_Bag_10", I .. "INV_Misc_Bag_07" },
    progress = function(db)
      local n, all = 0, 0
      for _, c in ipairs(ns.Cards.collectible) do
        if c.type == "trap" then
          all = all + 1
          if C().Owned(db, c.id) > 0 then n = n + 1 end
        end
      end
      return n, all
    end },

  -- oddities
  { id = "draw", group = "oddities", points = 5, name = L["Honours even"], text = L["Draw a match."],
    icon = { I .. "INV_Misc_Dice_01" }, progress = function(db) return math.min(1, db.stats.draws or 0), 1 end },
  { id = "close", group = "oddities", points = 10, name = L["By a hair"], text = L["Win with exactly 1 Morale left."],
    icon = { I .. "Spell_Shadow_DeathScream", I .. "INV_Misc_Dice_02" }, progress = life("close", 1) },
  { id = "comeback", group = "oddities", points = 25, name = L["Comeback"], text = L["Win after falling to 3 Morale or less."],
    icon = { I .. "Spell_Holy_Resurrection", I .. "Spell_Holy_HolyBolt" }, progress = life("comeback", 1) },
  { id = "flawless", group = "oddities", points = 25, name = L["Untouched"], text = L["Win without losing any Morale."],
    icon = { I .. "Spell_Holy_DivineIntervention", I .. "INV_Shield_06" }, progress = life("flawless", 1) },
  { id = "tiebreak", group = "oddities", points = 10, name = L["Photo finish"], text = L["Win a match on the tiebreak."],
    icon = { I .. "INV_Misc_PocketWatch_01", I .. "INV_Misc_Dice_02" }, progress = life("tiebreak", 1) },
  { id = "quick", group = "oddities", points = 10, name = L["Short hop"], text = L["Win a match by round 5."],
    icon = { I .. "Ability_Rogue_Sprint", I .. "Ability_Hunter_Pet_WindSerpent" }, progress = life("quick", 1) },
}

ns.AchievementById = {}
for i, a in ipairs(ns.Achievements) do
  a.index = i
  ns.AchievementById[a.id] = a
end
