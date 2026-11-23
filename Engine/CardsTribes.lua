-- "Tribes of Azeroth" (SETS_PLAN.md, Wave 1): every unit has a tribe, new
-- cards that share a stat line with a card of another tribe, more tribal
-- synergy, and items. Same fields as Engine/Cards.lua and CardsRoads.lua,
-- plus:
--   item = true      a tactic that's an item (a potion, a weapon): it plays
--                    exactly like any other tactic; only its frame and type
--                    line ("Item: your unit") differ
--   synergy = tribe  the tribe the card's effect counts, so the board can
--                    light those units up while you point at the card
--   twin = id        a plain card that shares its cost, stats and keywords
--                    with that card of another tribe (tests/engine.lua checks)
-- This is the last card file: it calls Cards.Finish().
local _, ns = ...
local R = ns.Rules
local Cards = ns.Cards
local icons, neighbours = Cards.Icons, Cards.Neighbours
local others, perOther = Cards.Others, Cards.PerOther

local function add(c)
  c.set = "tribes"
  Cards.Add(c)
end

local function enemyBoard(st, u)
  return st.players[3 - u.owner].board
end

-- ---------------------------------------------------------------------------
-- Every unit has a tribe: the ones that had none are Humanoids. (Harvest
-- Watcher, Venture Co. Shredder, Lord Kazzak and Ragnaros wait for the tribes
-- of a later wave: Mechanical, Demon, Elemental.) No card counted Humanoids
-- before, so this changes no rules.
-- ---------------------------------------------------------------------------
for _, id in ipairs({ "kobold", "gnoll", "mountaineer", "axe", "grunt", "crusader", "ogre", "tinker", "troll", "apprentice",
  "bruiser", "gryphon", "demo", "medic", "warmaster", "hogger", "runt", "tamer", "necro", "peon", "chaplain", "sapper",
  "brave", "archer", "seahorn", "technician" }) do
  Cards.byId[id].tribe = "humanoid"
end

-- What the older synergy cards count.
for tribe, ids in pairs({
  beast = { "cub", "packleader", "gorilla", "bangalash", "callwild" },
  murloc = { "coastrunner", "oracle", "warrior", "murkeye" },
  undead = { "rivendare" },
  defias = { "smuggler", "taskmaster" },
  dragonkin = { "technician", "drakkisath" },
}) do
  for _, id in ipairs(ids) do Cards.byId[id].synergy = tribe end
end

-- The items among the older tactics.
Cards.byId.potion.item = true
Cards.byId.bandage.item = true

-- ---------------------------------------------------------------------------
-- Shared stat lines: the same cost, stats and keywords as a plain card of
-- another tribe. On their own they play the same; their tribe decides which
-- synergies they feed.
-- ---------------------------------------------------------------------------
local function twin(of, c)
  local base = Cards.byId[of]
  c.twin, c.type, c.rarity = of, "unit", "common"
  c.cost, c.atk, c.hp = base.cost, base.atk, base.hp
  if next(base.kw) then
    c.kw = {}
    for k, v in pairs(base.kw) do c.kw[k] = v end
  end
  add(c)
end

-- Beasts
twin("kobold", { id = "crawler", name = "Shore Crawler", tribe = "beast",
  flavor = "Westfall's beaches belong to it. Ask anyone.", icon = icons("Ability_Hunter_Pet_Crab", "Ability_Hunter_Pet_Turtle") })
twin("murloc", { id = "hyena", name = "Hecklefang Hyena", tribe = "beast",
  flavor = "It laughs first. Then it bites.", icon = icons("Ability_Hunter_Pet_Hyena") })
twin("thug", { id = "cougar", name = "Mountain Cougar", tribe = "beast",
  flavor = "Mulgore's other welcoming committee.", icon = icons("Ability_Hunter_Pet_Cat") })
twin("gnoll", { id = "panther", name = "Shadowmaw Panther", tribe = "beast",
  flavor = "Stranglethorn's shadows have teeth.", icon = icons("Ability_Mount_BlackPanther", "Ability_Hunter_Pet_Cat") })
twin("mountaineer", { id = "elderstrider", name = "Elder Plainstrider", tribe = "beast",
  flavor = "Older, slower, and very much in the way.", icon = icons("Ability_Hunter_Pet_TallStrider") })
twin("grunt", { id = "ashbear", name = "Ashenvale Bear", tribe = "beast",
  flavor = "The forest's quiet giant, until it isn't.", icon = icons("Ability_Druid_Maul", "Ability_Hunter_Pet_Bear") })
twin("patchwork", { id = "tiger", name = "Stranglethorn Tiger", tribe = "beast",
  flavor = "Hunters come here for its pelt. Some leave.", icon = icons("Ability_Mount_JungleTiger", "Ability_Mount_WhiteTiger") })
twin("brave", { id = "corehound", name = "Ancient Core Hound", tribe = "beast",
  flavor = "Two heads. Neither of them is friendly.", icon = icons("Ability_Hunter_Pet_CoreHound", "Ability_Hunter_Pet_Wolf") })

-- Humanoids
twin("thug", { id = "footman", name = "Stormwind Footman", tribe = "humanoid",
  flavor = "Ready for anything. Mostly guard duty.", icon = icons("INV_Misc_Head_Human_01", "INV_Sword_27") })
twin("raptor", { id = "sentinel", name = "Silverwing Sentinel", tribe = "humanoid",
  flavor = "Warsong Gulch taught her to run.", icon = icons("INV_Misc_Head_Elf_02", "Ability_Marksmanship") })
twin("bear", { id = "defender", name = "Ironforge Defender", tribe = "humanoid",
  flavor = "The gates never fell on his watch.", icon = icons("INV_Shield_09", "INV_Misc_Head_Dwarf_01") })
twin("patchwork", { id = "veteran", name = "Kor'kron Veteran", tribe = "humanoid",
  flavor = "Orgrimmar's elite, and he'll tell you so.", icon = icons("INV_Misc_Head_Orc_02", "INV_Misc_Head_Orc_01") })

-- Murlocs
twin("kobold", { id = "streamrunner", name = "Murloc Streamrunner", tribe = "murloc",
  flavor = "Mrrgl? Mrrgl.", icon = icons("INV_Misc_Fish_09", "INV_Misc_Fish_04") })
twin("grunt", { id = "tidewarrior", name = "Murloc Tidewarrior", tribe = "murloc",
  flavor = "Bigger than the rest, and twice as loud.", icon = icons("INV_Spear_04", "INV_Spear_05") })
twin("axe", { id = "harpooner", name = "Murloc Harpooner", tribe = "murloc",
  flavor = "Throws first. Asks never.", icon = icons("INV_Spear_06", "INV_Spear_05") })

-- Undead
twin("murloc", { id = "zombie", name = "Tirisfal Zombie", tribe = "undead",
  flavor = "Slow, hungry, and in no hurry.", icon = icons("Ability_Creature_Disease_02", "Spell_Shadow_RaiseDead") })
twin("thug", { id = "deathguard", name = "Deathguard Lookout", tribe = "undead",
  flavor = "Brill's night watch. And day watch.", icon = icons("Spell_Shadow_Possession", "Spell_Shadow_RaiseDead") })
twin("gnoll", { id = "hungryghoul", name = "Hungering Ghoul", tribe = "undead",
  flavor = "Always hungry. Never full.", icon = icons("Ability_Creature_Disease_03", "Spell_Shadow_RaiseDead") })
twin("mountaineer", { id = "warder", name = "Skeletal Warder", tribe = "undead",
  flavor = "Stands its post. It has nothing better to do.", icon = icons("INV_Misc_Bone_Skull_02", "INV_Misc_Bone_HumanSkull_01") })
twin("grunt", { id = "footsoldier", name = "Scourge Footsoldier", tribe = "undead",
  flavor = "The Plaguelands' endless infantry.", icon = icons("INV_Misc_Bone_TaurenSkull_01", "Spell_Shadow_RaiseDead") })
twin("bear", { id = "abomination", name = "Hulking Abomination", tribe = "undead",
  flavor = "Three of everything, stitched together.", icon = icons("Spell_Shadow_AbominationExplosion") })

-- Defias
twin("kobold", { id = "lookout", name = "Defias Lookout", tribe = "defias",
  flavor = "Sees you coming. Tells everyone.", icon = icons("INV_Misc_Spyglass_01", "INV_Misc_Spyglass_02") })
twin("murloc", { id = "cutpurse", name = "Defias Cutpurse", tribe = "defias",
  flavor = "Your coin purse feels lighter already.", icon = icons("INV_Misc_Bag_11", "INV_Misc_Bag_10") })
twin("gnoll", { id = "highwayman", name = "Defias Highwayman", tribe = "defias",
  flavor = "The road to Sentinel Hill has a toll.", icon = icons("Ability_Gouge", "INV_Misc_Bandana_01") })
twin("raptor", { id = "nightrunner", name = "Defias Night Runner", tribe = "defias",
  flavor = "Westfall's nights belong to the Brotherhood.", icon = icons("Ability_Rogue_Sprint", "Ability_Stealth") })
twin("axe", { id = "pathstalker", name = "Defias Pathstalker", tribe = "defias",
  flavor = "Watches the Moonbrook road from the hills.", icon = icons("INV_Weapon_Crossbow_01", "Ability_Marksmanship") })

-- Dragonkin
twin("gnoll", { id = "azurewhelp", name = "Azure Whelp", tribe = "dragonkin",
  flavor = "Bites first. Sneezes frost later.", icon = icons("INV_Misc_Head_Dragon_Blue") })
twin("grunt", { id = "drakonid", name = "Black Drakonid", tribe = "dragonkin",
  flavor = "Bred in Blackwing Lair for one job.", icon = icons("INV_Misc_Head_Dragon_Black") })
twin("raptor", { id = "drakeling", name = "Emerald Drakeling", tribe = "dragonkin",
  flavor = "Dreams fast, wakes faster.", icon = icons("INV_Misc_Head_Dragon_Green", "INV_Misc_Head_Dragon_01") })
twin("axe", { id = "broodling", name = "Black Broodling", tribe = "dragonkin",
  flavor = "Spits fire before it can fly.", icon = icons("Spell_Fire_FireBolt02", "Spell_Fire_FlameBolt") })
twin("bear", { id = "wyrmguard", name = "Bronze Wyrmguard", tribe = "dragonkin",
  flavor = "Guards the sands of time. And you, for now.", icon = icons("INV_Misc_Head_Dragon_Bronze") })
twin("patchwork", { id = "reddragonspawn", name = "Red Dragonspawn", tribe = "dragonkin",
  flavor = "Grim Batol's warden, on leave.", icon = icons("INV_Misc_Head_Dragon_Red") })
twin("brave", { id = "greendrake", name = "Green Drake", tribe = "dragonkin",
  flavor = "Asleep until woken. Then very awake.", icon = icons("INV_Misc_Head_Dragon_Green", "INV_Misc_Head_Dragon_01") })
twin("ogre", { id = "seether", name = "Death Talon Seether", tribe = "dragonkin",
  flavor = "Blackwing Lair's hall monitor.", icon = icons("INV_Misc_MonsterScales_05", "INV_Misc_Head_Dragon_Black") })

-- ---------------------------------------------------------------------------
-- Beasts
-- ---------------------------------------------------------------------------
add { id = "trackinghound", name = "Tracking Hound", cost = 2, type = "unit", rarity = "uncommon", atk = 2, hp = 2,
  tribe = "beast", synergy = "beast", text = "Arrive: draw a card if you have another Beast.",
  flavor = "Already knows where you're going.", icon = icons("Ability_Tracking", "Ability_Hunter_Pet_Wolf"),
  arrive = function(st, u) if #others(st, u, "beast") > 0 then R.Draw(st, u.owner, 1) end end }

add { id = "patriarch", name = "Silverback Patriarch", cost = 5, type = "unit", rarity = "rare", atk = 4, hp = 6,
  tribe = "beast", synergy = "beast", text = "Arrive: your other Beasts get +1/+1.",
  flavor = "The troop follows the grey.", icon = icons("Ability_Hunter_Pet_Gorilla"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "beast")) do R.Buff(st, x, 1, 1) end
  end }

-- ---------------------------------------------------------------------------
-- Humanoids. The biggest tribe, so its cards ask for more, or reach only the
-- neighbouring lanes.
-- ---------------------------------------------------------------------------
add { id = "crier", name = "Town Crier", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 3,
  tribe = "humanoid", synergy = "humanoid", text = "Arrive: draw a card if you have 2 other Humanoids.",
  flavor = "Hear ye! Wanted: Hogger. Again.", icon = icons("INV_Misc_Note_02", "Ability_Warrior_BattleShout"),
  arrive = function(st, u) if #others(st, u, "humanoid") >= 2 then R.Draw(st, u.owner, 1) end end }

add { id = "sergeant", name = "Militia Sergeant", cost = 3, type = "unit", rarity = "common", atk = 2, hp = 4,
  tribe = "humanoid", synergy = "humanoid", text = "Arrive: your other Humanoids get +1 health.",
  flavor = "Goldshire's finest. Goldshire's only.", icon = icons("INV_Helmet_08", "Ability_Warrior_ShieldWall"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "humanoid")) do R.Buff(st, x, 0, 1) end
  end }

add { id = "captain", name = "Stormwind Captain", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 4,
  tribe = "humanoid", synergy = "humanoid", text = "Arrive: your Humanoids in the neighbouring lanes get +1/+1.",
  flavor = "Leads from the front. Mostly.", icon = icons("INV_BannerPVP_02", "INV_BannerPVP_01"),
  arrive = function(st, u)
    local board = st.players[u.owner].board
    for _, l in ipairs(neighbours(u.lane)) do
      local x = board[l]
      if x and R.Card(x.id).tribe == "humanoid" then R.Buff(st, x, 1, 1) end
    end
  end }

add { id = "bolvar", name = "Bolvar Fordragon", cost = 5, type = "unit", rarity = "legendary", atk = 4, hp = 6,
  tribe = "humanoid", synergy = "humanoid", kw = { rally = true }, text = "Arrive: your other Humanoids get +1/+1.",
  flavor = "Regent of Stormwind, and nobody's pushover.", icon = icons("Spell_Holy_DevotionAura", "Spell_Holy_SealOfMight"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "humanoid")) do R.Buff(st, x, 1, 1) end
  end }

-- ---------------------------------------------------------------------------
-- Murlocs
-- ---------------------------------------------------------------------------
add { id = "raider", name = "Murloc Raider", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2,
  tribe = "murloc", synergy = "murloc", text = "Arrive: +1 attack if you have another Murloc.",
  flavor = "Never raids alone. Wouldn't know how.", icon = icons("INV_Misc_Fish_05", "INV_Spear_05"),
  arrive = function(st, u) if #others(st, u, "murloc") > 0 then R.Buff(st, u, 1, 0) end end }

add { id = "flopper", name = "Murloc Flopper", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2,
  tribe = "murloc", text = "Fallen: summon a 1/1 Murloc Scout in its lane.",
  flavor = "Flops in. Flops out. Leaves a friend.", icon = icons("INV_Misc_Fish_14", "INV_Misc_Fish_04"),
  fallen = function(st, u) R.Summon(st, u.owner, u.lane, "scout") end }

add { id = "tidecaller", name = "Murloc Tidecaller", cost = 3, type = "unit", rarity = "uncommon", atk = 1, hp = 2,
  tribe = "murloc", text = "Arrive: summon a 1/1 Murloc Scout in each of your empty neighbouring lanes.",
  flavor = "It calls. They come. Every time.", icon = icons("Spell_Nature_Tranquility", "Spell_Frost_SummonWaterElemental"),
  arrive = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Summon(st, u.owner, l, "scout") end
  end }

add { id = "netmaster", name = "Murloc Netmaster", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 3,
  tribe = "murloc", synergy = "murloc", text = "Arrive: freeze the enemy units across from your other Murlocs.",
  flavor = "One net, many murlocs, no way out.", icon = icons("INV_Misc_Net_01", "Trade_Fishing"),
  arrive = function(st, u)
    local eb = enemyBoard(st, u)
    for _, x in ipairs(others(st, u, "murloc")) do R.Freeze(st, eb[x.lane]) end
  end }

add { id = "hightide", name = "High Tide", cost = 2, type = "tactic", rarity = "uncommon", target = "none",
  synergy = "murloc", text = "Your Murlocs get +1/+1.", flavor = "Everything floats. Especially murlocs.",
  icon = icons("Spell_Frost_SummonWaterElemental_2", "Spell_Nature_HealingWaveGreater"),
  play = function(st, p)
    for _, u in ipairs(R.Units(st, p)) do
      if R.Card(u.id).tribe == "murloc" then R.Buff(st, u, 1, 1) end
    end
  end }

add { id = "muckdweller", name = "Murloc Muckdweller", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 4,
  tribe = "murloc", synergy = "murloc", text = "Whenever another of your Murlocs dies, gains +1/+1.",
  flavor = "Grows fat on the tide's leftovers.", icon = icons("INV_Misc_Fish_19", "INV_Misc_Fish_04"),
  onDeath = function(st, u, dead)
    if dead.owner == u.owner and R.Card(dead.id).tribe == "murloc" then R.Buff(st, u, 1, 1) end
  end }

add { id = "murkdeep", name = "Murkdeep", cost = 5, type = "unit", rarity = "epic", atk = 4, hp = 5,
  tribe = "murloc", synergy = "murloc", aura = { tribe = "murloc", atk = 1 },
  text = "Arrive: summon a 1/1 Murloc Scout in each of your empty neighbouring lanes. Your other Murlocs have +1 attack.",
  flavor = "Darkshore's coast has one king, and he's wet.", icon = icons("INV_Misc_Head_Murloc_01"),
  arrive = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Summon(st, u.owner, l, "scout") end
  end }

-- ---------------------------------------------------------------------------
-- Undead
-- ---------------------------------------------------------------------------
add { id = "squire", name = "Rotting Squire", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 2,
  tribe = "undead", synergy = "undead", text = "Arrive: +1 attack if you have another Undead.",
  flavor = "Still serving. Still squiring.", icon = icons("INV_Misc_Bone_ElfSkull_01", "INV_Misc_Bone_HumanSkull_01"),
  arrive = function(st, u) if #others(st, u, "undead") > 0 then R.Buff(st, u, 1, 0) end end }

add { id = "bonecaller", name = "Bonecaller", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 3,
  tribe = "undead", synergy = "undead", text = "Fallen: your other Undead get +1 attack.",
  flavor = "Its last word is always 'rise'.", icon = icons("Spell_Shadow_DeathPact", "Spell_Shadow_Requiem"),
  fallen = function(st, u)
    local any = false
    for _, x in ipairs(R.Units(st, u.owner)) do
      if R.Card(x.id).tribe == "undead" then R.Buff(st, x, 1, 0); any = true end
    end
    if not any then R.Fizzle(st, u, "notarget") end
  end }

add { id = "plagueeater", name = "Plague Eater", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 4,
  tribe = "undead", synergy = "undead", text = "Whenever another of your Undead dies, gains +1/+1.",
  flavor = "Nothing goes to waste in the Plaguelands.", icon = icons("Ability_Creature_Disease_05", "Spell_Shadow_AnimateDead"),
  onDeath = function(st, u, dead)
    if dead.owner == u.owner and R.Card(dead.id).tribe == "undead" then R.Buff(st, u, 1, 1) end
  end }

add { id = "bloated", name = "Bloated Zombie", cost = 3, type = "unit", rarity = "uncommon", atk = 3, hp = 2,
  tribe = "undead", text = "Fallen: deal 1 damage to every enemy unit.", flavor = "Do not poke.",
  icon = icons("Ability_Creature_Disease_04", "Spell_Shadow_AbominationExplosion"),
  fallen = function(st, u)
    local list = R.Units(st, 3 - u.owner)
    if #list == 0 then R.Fizzle(st, u, "notarget") end
    for _, x in ipairs(list) do R.Damage(st, x, 1) end
  end }

add { id = "armydead", name = "Army of the Dead", cost = 3, type = "tactic", rarity = "uncommon", target = "none",
  text = "Summon a 1/1 Skeleton in each of your empty lanes.", flavor = "They were already here. They just stood up.",
  icon = icons("Spell_DeathKnight_ArmyOfTheDead", "Spell_Shadow_AnimateDead"),
  play = function(st, p)
    for l = 1, R.LANES do R.Summon(st, p, l, "bones") end
  end }

add { id = "commander", name = "Scourge Commander", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 4,
  tribe = "undead", synergy = "undead", aura = { tribe = "undead", atk = 1 }, text = "Your other Undead have +1 attack.",
  flavor = "Orders from Naxxramas, delivered in person.", icon = icons("Spell_Shadow_ScourgeBuild", "Spell_Shadow_UnholyStrength") }

add { id = "gandling", name = "Darkmaster Gandling", cost = 5, type = "unit", rarity = "epic", atk = 4, hp = 5,
  tribe = "undead", text = "Round start: summon a 1/1 Skeleton in each of your empty neighbouring lanes.",
  flavor = "Scholomance's headmaster. Attendance is mandatory.", icon = icons("Spell_Shadow_Twilight", "Spell_Shadow_Requiem"),
  roundStart = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Summon(st, u.owner, l, "bones") end
  end }

-- ---------------------------------------------------------------------------
-- Defias (their trap cards come with traps, in Wave 2)
-- ---------------------------------------------------------------------------
add { id = "overseer", name = "Defias Overseer", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2,
  tribe = "defias", synergy = "defias", text = "Arrive: +1 attack if you have another Defias.",
  flavor = "Counts the loot. Twice.", icon = icons("INV_Misc_Coin_01", "INV_Misc_Bandana_03"),
  arrive = function(st, u) if #others(st, u, "defias") > 0 then R.Buff(st, u, 1, 0) end end }

add { id = "conjurer", name = "Defias Conjurer", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 3,
  tribe = "defias", synergy = "defias", text = "Arrive: the enemy loses 1 Morale for each other Defias you have (at most 2).",
  flavor = "Learned his tricks from a book he stole.", icon = icons("Spell_Fire_FlameShock", "Spell_Fire_FlameBolt"),
  arrive = function(st, u)
    local n = math.min(2, #others(st, u, "defias"))
    if n > 0 then R.HitMorale(st, 3 - u.owner, n) end
  end }

add { id = "blackguard", name = "Defias Blackguard", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 4,
  tribe = "defias", synergy = "defias", kw = { stealth = true }, text = "Arrive: your other Defias get Stealth.",
  flavor = "Teaches the new recruits to disappear.", icon = icons("Ability_Rogue_FeintFlurry", "Ability_Stealth"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "defias")) do R.Buff(st, x, 0, 0, "stealth") end
  end }

-- ---------------------------------------------------------------------------
-- Dragonkin
-- ---------------------------------------------------------------------------
add { id = "whelpling", name = "Brood Whelpling", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 2,
  tribe = "dragonkin", synergy = "dragonkin", text = "Arrive: +1 attack if you have another Dragonkin.",
  flavor = "Small, loud, and already hoarding.", icon = icons("INV_Misc_Head_Dragon_Bronze", "INV_Misc_Head_Dragon_01"),
  arrive = function(st, u) if #others(st, u, "dragonkin") > 0 then R.Buff(st, u, 1, 0) end end }

add { id = "firebrand", name = "Wyrmkin Firebrand", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 4,
  tribe = "dragonkin", synergy = "dragonkin", text = "Has +1 attack for each other Dragonkin you have.",
  flavor = "The flame burns hotter in a crowd.", icon = icons("Spell_Fire_Fireball", "Spell_Fire_Incinerate"),
  bonus = perOther("dragonkin") }

add { id = "wyrmkin", name = "Flamescale Wyrmkin", cost = 4, type = "unit", rarity = "uncommon", atk = 3, hp = 4,
  tribe = "dragonkin", synergy = "dragonkin", text = "Arrive: deal 1 damage to every enemy unit if you have another Dragonkin.",
  flavor = "Breathes on everyone. Apologises to no one.", icon = icons("Spell_Fire_SealOfFire", "Spell_Fire_Incinerate"),
  arrive = function(st, u)
    if #others(st, u, "dragonkin") == 0 then return end
    for _, x in ipairs(R.Units(st, 3 - u.owner)) do R.Damage(st, x, 1) end
  end }

add { id = "nefarian", name = "Nefarian", cost = 6, type = "unit", rarity = "legendary", atk = 5, hp = 7,
  tribe = "dragonkin", synergy = "dragonkin", text = "Arrive: your other Dragonkin get +2/+2.",
  flavor = "Blackwing Lair's host, and its worst landlord.", icon = icons("INV_Misc_Head_Dragon_Black"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "dragonkin")) do R.Buff(st, x, 2, 2) end
  end }

-- ---------------------------------------------------------------------------
-- Items: tactics, with a frame and a type line of their own. Consumables do
-- something once; gear stays on the unit (like Shield Wall).
-- ---------------------------------------------------------------------------
local function item(c)
  c.type, c.item = "tactic", true
  add(c)
end

local function gear(st, p, lane, atk, hp, ...)
  local u = R.FriendTarget(st, p, lane)
  if not u then return end
  local kws = { ... }
  R.Buff(st, u, atk, hp, kws[1])
  for i = 2, #kws do R.Buff(st, u, 0, 0, kws[i]) end
end

item { id = "cutlass", name = "Bloodsail Cutlass", cost = 1, rarity = "common", target = "friend",
  text = "Give one of your units +3/+1.", flavor = "Rusty, notched, and still sharper than you'd like.",
  icon = icons("INV_Sword_23", "INV_Sword_48"),
  play = function(st, p, lane) gear(st, p, lane, 3, 1) end }

item { id = "swiftness", name = "Swiftness Potion", cost = 1, rarity = "common", target = "friend",
  text = "Give one of your units Swift and +1/+1.", flavor = "Drink it before the fight, not during.",
  icon = icons("INV_Potion_95", "INV_Potion_51"),
  play = function(st, p, lane) gear(st, p, lane, 1, 1, "swift") end }

item { id = "scrollprot", name = "Scroll of Protection", cost = 1, rarity = "common", target = "friend",
  text = "Give one of your units +1/+4.", flavor = "Read aloud. Slowly. Mind the long words.",
  icon = icons("INV_Scroll_07", "Ability_Warrior_ShieldWall"),
  play = function(st, p, lane) gear(st, p, lane, 1, 4) end }

item { id = "grenade", name = "Iron Grenade", cost = 2, rarity = "common", target = "enemy",
  text = "Deal 2 damage to the enemy unit in a lane and freeze it.", flavor = "Pull pin. Throw. Do not hold.",
  icon = icons("INV_Misc_Bomb_08", "INV_Misc_Bomb_05"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t then
      R.Damage(st, t, 2)
      R.Freeze(st, t)
    end
  end }

item { id = "majorheal", name = "Major Healing Potion", cost = 2, rarity = "common", target = "none",
  text = "Restore 8 Morale.", flavor = "The good stuff. Tastes worse.",
  icon = icons("INV_Potion_54", "INV_Potion_51"),
  play = function(st, p) R.RestoreMorale(st, p, 8) end }

item { id = "netomatic", name = "Gnomish Net-o-Matic Projector", cost = 1, rarity = "uncommon", target = "enemy",
  text = "Freeze the enemy unit in a lane. Draw a card.", flavor = "Works every time. Sixty percent of the time.",
  icon = icons("INV_Gizmo_03", "Trade_Engineering"),
  play = function(st, p, lane)
    R.Freeze(st, R.EnemyTarget(st, p, lane))
    R.Draw(st, p, 1)
  end }

item { id = "trollblood", name = "Mighty Troll's Blood Potion", cost = 1, rarity = "uncommon", target = "friend",
  text = "Give one of your units Regenerate and +1/+2.", flavor = "Don't ask what's in it. Don't ask whose.",
  icon = icons("INV_Potion_79", "INV_Potion_51"),
  play = function(st, p, lane) gear(st, p, lane, 1, 2, "regen") end }

item { id = "giants", name = "Elixir of the Giants", cost = 2, rarity = "uncommon", target = "friend",
  text = "Give one of your units +3/+3.", flavor = "Side effects include ducking under doorways.",
  icon = icons("INV_Potion_61", "INV_Potion_51"),
  play = function(st, p, lane) gear(st, p, lane, 3, 3) end }

item { id = "lionheart", name = "Lionheart Helm", cost = 2, rarity = "rare", target = "friend",
  text = "Give one of your units +2/+2 and Rally.", flavor = "Whoever wears it, the rest stand taller.",
  icon = icons("INV_Helmet_36", "INV_BannerPVP_01"),
  play = function(st, p, lane) gear(st, p, lane, 2, 2, "rally") end }

item { id = "thunderfury", name = "Thunderfury", cost = 4, rarity = "legendary", target = "friend",
  text = "Give one of your units +2/+2, Swift and Cleave.", flavor = "Did someone say...?",
  icon = icons("INV_Sword_39", "Spell_Nature_ChainLightning"),
  play = function(st, p, lane) gear(st, p, lane, 2, 2, "swift", "cleave") end }

Cards.Finish()
