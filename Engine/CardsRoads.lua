-- The second set, "Roads of Azeroth": five tribes (Beast, Murloc, Undead,
-- Defias, Dragonkin) with cards that reward playing them together, and a few
-- neutral cards. Same fields as Engine/Cards.lua, plus:
--   tribe             "beast" | "murloc" | "undead" | "defias" | "dragonkin"
--   aura = { tribe, atk }   your OTHER units of that tribe get +atk attack
--   bonus(st, u)      extra attack for this unit right now (must only read
--                     st.players[..].board, so it also works on a replay view)
local _, ns = ...
local R = ns.Rules
local Cards = ns.Cards
local icons, neighbours, hitAcross = Cards.Icons, Cards.Neighbours, Cards.HitAcross

local function add(c)
  c.set = "roads"
  Cards.Add(c)
end

local function across(st, u)
  return st.players[3 - u.owner].board[u.lane]
end

-- Your other units (of a tribe, if given).
local function others(st, u, tribe)
  local out = {}
  for _, x in ipairs(R.Units(st, u.owner)) do
    if x.lane ~= u.lane and (not tribe or R.Card(x.id).tribe == tribe) then out[#out + 1] = x end
  end
  return out
end

local function perOther(tribe)
  return function(st, u) return #others(st, u, tribe) end
end

-- A token in the first empty lane next to u (a lane with u's owner's trap in
-- it isn't empty).
local function summonBeside(st, u, id)
  for _, l in ipairs(neighbours(u.lane)) do
    if not st.players[u.owner].board[l] and not R.TrapAt(st, u.owner, l) then return R.Summon(st, u.owner, l, id) end
  end
end
Cards.Others, Cards.PerOther, Cards.SummonBeside = others, perOther, summonBeside

-- ---------------------------------------------------------------------------
-- Beasts
-- ---------------------------------------------------------------------------
add { id = "cub", name = "Nightsaber Cub", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 2, tribe = "beast",
  text = "Arrive: +1 attack if you have another Beast.", flavor = "Teldrassil's smallest ambush.",
  icon = icons("Ability_Hunter_Pet_Cat"),
  arrive = function(st, u) if #others(st, u, "beast") > 0 then R.Buff(st, u, 1, 0) end end }

add { id = "owl", name = "Strigid Screecher", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 1, tribe = "beast",
  kw = { swift = true }, flavor = "You hear it after it lands.", icon = icons("Ability_Hunter_Pet_Owl") }

add { id = "turtle", name = "Saltwater Snapjaw", cost = 3, type = "unit", rarity = "common", atk = 1, hp = 6, tribe = "beast",
  kw = { guard = true }, flavor = "In no hurry, and neither are you.", icon = icons("Ability_Hunter_Pet_Turtle") }

add { id = "packleader", name = "Worg Packleader", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 3, tribe = "beast",
  text = "Your other Beasts have +1 attack.", flavor = "The pack eats when he says.",
  icon = icons("Ability_Mount_WhiteDireWolf", "Ability_Hunter_Pet_Wolf"), aura = { tribe = "beast", atk = 1 } }

add { id = "tamer", name = "Stranglethorn Tamer", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 3,
  text = "Arrive: summon a 1/1 Hound in an empty neighbouring lane.", flavor = "Never travels alone.",
  icon = icons("Ability_Hunter_BeastTaming", "Ability_Hunter_BeastCall"),
  arrive = function(st, u) summonBeside(st, u, "hound") end }

add { id = "gorilla", name = "Elder Mistvale Gorilla", cost = 5, type = "unit", rarity = "rare", atk = 4, hp = 5, tribe = "beast",
  text = "Arrive: gains +1/+1 for each other Beast you have.", flavor = "The vale answers to him.",
  icon = icons("Ability_Hunter_Pet_Gorilla"),
  arrive = function(st, u)
    local n = #others(st, u, "beast")
    if n > 0 then R.Buff(st, u, n, n) end
  end }

add { id = "bangalash", name = "King Bangalash", cost = 4, type = "unit", rarity = "epic", atk = 4, hp = 3, tribe = "beast",
  kw = { swift = true }, text = "Whenever another of your Beasts dies, gains +1/+1.",
  flavor = "The white tiger of Stranglethorn.", icon = icons("Ability_Mount_WhiteTiger", "Ability_Hunter_Pet_Cat"),
  onDeath = function(st, u, dead)
    if dead.owner == u.owner and R.Card(dead.id).tribe == "beast" then R.Buff(st, u, 1, 1) end
  end }

add { id = "callwild", name = "Call of the Wild", cost = 2, type = "tactic", rarity = "uncommon", target = "none",
  text = "Your Beasts get +1/+1.", flavor = "Something out there howls back.",
  icon = icons("Ability_Hunter_BeastCall"),
  play = function(st, p)
    for _, u in ipairs(R.Units(st, p)) do
      if R.Card(u.id).tribe == "beast" then R.Buff(st, u, 1, 1) end
    end
  end }

-- ---------------------------------------------------------------------------
-- Murlocs
-- ---------------------------------------------------------------------------
add { id = "coastrunner", name = "Murloc Coastrunner", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, tribe = "murloc",
  text = "Has +1 attack for each other Murloc you have.", flavor = "Fast. Faster with friends.",
  icon = icons("INV_Misc_Fish_04", "INV_Misc_Fish_02"), bonus = perOther("murloc") }

add { id = "tidehunter", name = "Murloc Tidehunter", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 1, tribe = "murloc",
  text = "Arrive: summon a 1/1 Murloc Scout in an empty neighbouring lane.", flavor = "Brought a friend.",
  icon = icons("INV_Spear_05", "INV_Spear_02"),
  arrive = function(st, u) summonBeside(st, u, "scout") end }

add { id = "netter", name = "Murloc Netter", cost = 2, type = "unit", rarity = "common", atk = 1, hp = 3, tribe = "murloc",
  text = "Arrive: freeze the enemy unit across.", flavor = "Catch of the day: you.",
  icon = icons("Trade_Fishing", "INV_Misc_Fish_01"),
  arrive = function(st, u) R.Freeze(st, across(st, u)) end }

add { id = "lurker", name = "Murloc Lurker", cost = 3, type = "unit", rarity = "common", atk = 3, hp = 2, tribe = "murloc",
  kw = { stealth = true }, flavor = "The reeds are watching.", icon = icons("Ability_Ambush", "Ability_Stealth") }

add { id = "oracle", name = "Bluegill Oracle", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 3, tribe = "murloc",
  text = "Arrive: your other Murlocs get +1/+1.", flavor = "Speaks for the tide. Loudly.",
  icon = icons("Spell_Nature_HealingWaveGreater", "Spell_Frost_SummonWaterElemental"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "murloc")) do R.Buff(st, x, 1, 1) end
  end }

add { id = "warrior", name = "Bluegill Warrior", cost = 3, type = "unit", rarity = "rare", atk = 3, hp = 3, tribe = "murloc",
  text = "Your other Murlocs have +1 attack.", flavor = "Mrgl mrgl, charge.",
  icon = icons("INV_Sword_27", "INV_Sword_04"), aura = { tribe = "murloc", atk = 1 } }

add { id = "murkeye", name = "Old Murk-Eye", cost = 4, type = "unit", rarity = "epic", atk = 2, hp = 4, tribe = "murloc",
  kw = { swift = true }, text = "Has +1 attack for each other Murloc you have.",
  flavor = "Westfall's coast has one rule: don't go near the old one.",
  icon = icons("INV_Misc_Eye_01", "INV_Misc_Fish_02"), bonus = perOther("murloc") }

add { id = "shoal", name = "Call the Shoal", cost = 3, type = "tactic", rarity = "uncommon", target = "none",
  text = "Summon a 1/1 Murloc Scout in each of your empty lanes.", flavor = "There's never just one.",
  icon = icons("Spell_Frost_SummonWaterElemental", "INV_Misc_Fish_02"),
  play = function(st, p)
    for l = 1, R.LANES do R.Summon(st, p, l, "scout") end
  end }

-- ---------------------------------------------------------------------------
-- Undead
-- ---------------------------------------------------------------------------
add { id = "skeleton", name = "Rattlecage Skeleton", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, tribe = "undead",
  text = "Fallen: deal 1 damage to the enemy unit across.", flavor = "Falls apart on purpose.",
  icon = icons("INV_Misc_Bone_HumanSkull_01", "Spell_Shadow_RaiseDead"),
  fallen = function(st, u) hitAcross(st, u, 1) end }

add { id = "corpse", name = "Ravaged Corpse", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2, tribe = "undead",
  text = "Fallen: summon a 1/1 Skeleton in its lane.", flavor = "There's more of him in there.",
  icon = icons("Spell_Shadow_AnimateDead", "Spell_Shadow_RaiseDead"),
  fallen = function(st, u) R.Summon(st, u.owner, u.lane, "bones") end }

add { id = "patchwork", name = "Patchwork Horror", cost = 4, type = "unit", rarity = "common", atk = 4, hp = 5, tribe = "undead",
  flavor = "Some assembly required.", icon = icons("Spell_Shadow_AbominationExplosion", "Spell_Shadow_UnholyStrength") }

add { id = "necro", name = "Scholomance Necromancer", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 3,
  text = "Round start: summon a 1/1 Skeleton in an empty neighbouring lane.", flavor = "Class is in session.",
  icon = icons("Spell_Shadow_Requiem", "Spell_Shadow_RaiseDead"),
  roundStart = function(st, u) summonBeside(st, u, "bones") end }

add { id = "banshee", name = "Wailing Banshee", cost = 3, type = "unit", rarity = "uncommon", atk = 3, hp = 2, tribe = "undead",
  text = "Fallen: the enemy unit across gets -2 attack.", flavor = "The last thing she says stays with you.",
  icon = icons("Spell_Shadow_PsychicScream"),
  fallen = function(st, u)
    local t = across(st, u)
    if t then R.Buff(st, t, -2, 0) else R.Fizzle(st, u, "notarget") end
  end }

add { id = "gargoyle", name = "Stoneskin Gargoyle", cost = 4, type = "unit", rarity = "uncommon", atk = 3, hp = 5, tribe = "undead",
  kw = { regen = true }, flavor = "Cracks, then doesn't.", icon = icons("Spell_Shadow_UnholyStrength", "Ability_Hunter_Pet_Bat") }

add { id = "rivendare", name = "Baron Rivendare", cost = 5, type = "unit", rarity = "legendary", atk = 4, hp = 5, tribe = "undead",
  kw = { rally = true }, text = "Arrive: your other Undead get +1/+1 and Sturdy.",
  flavor = "Stratholme keeps its own time. You're late.",
  icon = icons("Ability_Mount_Undeadhorse", "Spell_Shadow_DeathPact"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "undead")) do R.Buff(st, x, 1, 1, "sturdy") end
  end }

add { id = "deathcoil", name = "Death Coil", cost = 2, type = "tactic", rarity = "common", target = "enemy",
  text = "Deal 2 damage to the enemy unit in a lane. Restore 2 Morale.", flavor = "Theirs to lose, yours to keep.",
  icon = icons("Spell_Shadow_DeathCoil"),
  play = function(st, p, lane)
    R.Damage(st, R.EnemyTarget(st, p, lane), 2)
    R.RestoreMorale(st, p, 2)
  end }

add { id = "raise", name = "Raise Dead", cost = 2, type = "tactic", rarity = "rare", target = "none",
  text = "Summon a fresh copy of your unit that died most recently, in a random empty lane of yours.",
  flavor = "Nobody stays down on the Plaguelands' clock.", icon = icons("Spell_Holy_Resurrection", "Spell_Shadow_RaiseDead"),
  play = function(st, p)
    local grave, id = st.players[p].grave, nil
    for i = #grave, 1, -1 do
      if R.Card(grave[i]).type == "unit" then id = grave[i]; break end
    end
    local free = R.EmptyLanes(st, p)
    if id and #free > 0 then R.Summon(st, p, free[R.Random(st, #free)], id) end
  end }

-- ---------------------------------------------------------------------------
-- Defias
-- ---------------------------------------------------------------------------
add { id = "footpad", name = "Defias Footpad", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 2, tribe = "defias",
  kw = { stealth = true }, flavor = "You didn't see him. That's the job.", icon = icons("INV_Misc_Bandana_01", "Ability_Stealth") }

add { id = "pillager", name = "Defias Pillager", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2, tribe = "defias",
  text = "Arrive: the enemy loses 1 Morale.", flavor = "Sets the fields on fire, then asks for the toll.",
  icon = icons("Spell_Fire_FlameBolt", "Spell_Fire_Fireball02"),
  arrive = function(st, u) R.HitMorale(st, 3 - u.owner, 1) end }

add { id = "smuggler", name = "Defias Smuggler", cost = 2, type = "unit", rarity = "uncommon", atk = 2, hp = 2, tribe = "defias",
  text = "Arrive: draw a card if you have another Defias.", flavor = "Knows a man who knows a man.",
  icon = icons("INV_Misc_Bag_10", "INV_Misc_Bag_07"),
  arrive = function(st, u) if #others(st, u, "defias") > 0 then R.Draw(st, u.owner, 1) end end }

add { id = "nightblade", name = "Defias Night Blade", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 2, tribe = "defias",
  kw = { stealth = true, venom = true }, flavor = "One cut is the whole plan.", icon = icons("Ability_BackStab") }

add { id = "taskmaster", name = "Defias Taskmaster", cost = 4, type = "unit", rarity = "uncommon", atk = 3, hp = 4, tribe = "defias",
  text = "Your other Defias have +1 attack.", flavor = "Motivation, Deadmines-style.",
  icon = icons("INV_Sword_05", "INV_Misc_Bandana_03"), aura = { tribe = "defias", atk = 1 } }

add { id = "smite", name = "Mr. Smite", cost = 5, type = "unit", rarity = "epic", atk = 5, hp = 5, tribe = "defias",
  text = "Arrive: freeze the enemy unit across and the ones next to it.", flavor = "Now you're making me angry!",
  icon = icons("Ability_Smash", "INV_Hammer_09"),
  arrive = function(st, u)
    local eb = st.players[3 - u.owner].board
    R.Freeze(st, eb[u.lane])
    for _, l in ipairs(neighbours(u.lane)) do R.Freeze(st, eb[l]) end
  end }

add { id = "ambush", name = "Ambush", cost = 1, type = "tactic", rarity = "common", target = "enemy",
  text = "Deal 4 damage to the enemy unit in a lane if it arrived this round, otherwise 2.",
  flavor = "They walked right into it.", icon = icons("Ability_Rogue_Ambush"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t then R.Damage(st, t, t.new and 4 or 2) end
  end }

add { id = "vanish", name = "Vanish", cost = 1, type = "tactic", rarity = "uncommon", target = "friend",
  text = "Give one of your units Stealth and +2/+2.", flavor = "Now you see me.",
  icon = icons("Ability_Vanish"),
  play = function(st, p, lane) R.Buff(st, R.FriendTarget(st, p, lane), 2, 2, "stealth") end }

-- ---------------------------------------------------------------------------
-- Dragonkin
-- ---------------------------------------------------------------------------
add { id = "whelp", name = "Crimson Whelp", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 1, tribe = "dragonkin",
  kw = { ranged = true }, flavor = "Small, and aware of it.", icon = icons("INV_Misc_Head_Dragon_Red", "Spell_Fire_Fire") }

add { id = "dragonspawn", name = "Black Dragonspawn", cost = 4, type = "unit", rarity = "common", atk = 4, hp = 4, tribe = "dragonkin",
  kw = { pierce = true }, flavor = "Burning Steppes border control.", icon = icons("INV_Misc_Head_Dragon_Black", "INV_Misc_Head_Dragon_01") }

add { id = "scalebane", name = "Blue Scalebane", cost = 5, type = "unit", rarity = "uncommon", atk = 4, hp = 6, tribe = "dragonkin",
  kw = { guard = true }, flavor = "Azshara is closed.", icon = icons("INV_Misc_Head_Dragon_Blue", "INV_Misc_Head_Dragon_01") }

add { id = "drake", name = "Searscale Drake", cost = 5, type = "unit", rarity = "rare", atk = 4, hp = 5, tribe = "dragonkin",
  text = "Arrive: deal 1 damage to every enemy unit.", flavor = "Arrives warm.",
  icon = icons("INV_Misc_Head_Dragon_Bronze", "Spell_Fire_Fire"),
  arrive = function(st, u)
    for _, x in ipairs(R.Units(st, 3 - u.owner)) do R.Damage(st, x, 1) end
  end }

add { id = "technician", name = "Blackwing Technician", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 3,
  text = "Your Dragonkin have +1 attack.", flavor = "Results are mandatory.",
  icon = icons("INV_Gizmo_01", "Trade_Engineering"), aura = { tribe = "dragonkin", atk = 1 } }

add { id = "drakkisath", name = "General Drakkisath", cost = 5, type = "unit", rarity = "epic", atk = 4, hp = 6, tribe = "dragonkin",
  kw = { rally = true }, text = "Arrive: your other Dragonkin get +2 health.", flavor = "The spire's last door.",
  icon = icons("Spell_Shadow_ShadowWordDominate", "INV_Misc_Head_Dragon_Black"),
  arrive = function(st, u)
    for _, x in ipairs(others(st, u, "dragonkin")) do R.Buff(st, x, 0, 2) end
  end }

add { id = "flamebreath", name = "Flame Breath", cost = 4, type = "tactic", rarity = "rare", target = "enemy",
  text = "Deal 4 damage to the enemy unit in a lane and 2 damage to the enemy units next to it.",
  flavor = "Stand anywhere else.", icon = icons("Spell_Fire_Incinerate", "Spell_Fire_Fire"), splash = true,
  play = function(st, p, lane)
    R.Damage(st, R.EnemyTarget(st, p, lane), 4)
    for _, l in ipairs(neighbours(lane)) do R.Damage(st, R.EnemyTarget(st, p, l), 2) end
  end }

-- ---------------------------------------------------------------------------
-- Neutral
-- ---------------------------------------------------------------------------
add { id = "peon", name = "Lazy Peon", cost = 1, type = "unit", rarity = "common", atk = 2, hp = 2,
  text = "Arrive: you lose 1 Morale.", flavor = "Work, work.", icon = icons("INV_Pick_02", "Trade_Mining"),
  arrive = function(st, u) R.HitMorale(st, u.owner, 1) end }

add { id = "chaplain", name = "Northshire Chaplain", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 3,
  text = "Round start: restore 1 Morale.", flavor = "A kind word every morning.",
  icon = icons("Spell_Holy_Renew", "Spell_Holy_Heal"),
  roundStart = function(st, u) R.RestoreMorale(st, u.owner, 1) end }

add { id = "sapper", name = "Goblin Sapper", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 1,
  text = "Fallen: deal 1 damage to the enemy unit across and the ones next to it.", flavor = "Refunds not available.",
  icon = icons("INV_Misc_Bomb_05", "Spell_Fire_SelfDestruct"),
  fallen = function(st, u)
    local eb = st.players[3 - u.owner].board
    local any = eb[u.lane] ~= nil
    R.Damage(st, eb[u.lane], 1)
    for _, l in ipairs(neighbours(u.lane)) do
      if eb[l] then any = true end
      R.Damage(st, eb[l], 1)
    end
    if not any then R.Fizzle(st, u, "notarget") end
  end }

add { id = "brave", name = "Bloodhoof Brave", cost = 5, type = "unit", rarity = "common", atk = 5, hp = 6,
  flavor = "Mulgore's idea of a welcome.", icon = icons("INV_Misc_Head_Tauren_01", "Ability_WarStomp") }

add { id = "archer", name = "Darnassus Archer", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 2,
  kw = { swift = true, ranged = true }, flavor = "She already let go.", icon = icons("Ability_Marksmanship", "INV_Weapon_Bow_07") }

add { id = "seahorn", name = "Fleet Master Seahorn", cost = 4, type = "unit", rarity = "epic", atk = 3, hp = 3,
  text = "Arrive: draw 2 cards.", flavor = "Every ship in Booty Bay owes him a favour.",
  icon = icons("INV_Misc_Spyglass_02", "INV_Misc_Coin_03"),
  arrive = function(st, u) R.Draw(st, u.owner, 2) end }

add { id = "warstomp", name = "War Stomp", cost = 2, type = "tactic", rarity = "common", target = "enemy",
  text = "Freeze the enemy unit in a lane and the ones next to it: they don't strike this round.",
  flavor = "The ground has an opinion.", icon = icons("Ability_WarStomp"), splash = true,
  play = function(st, p, lane)
    R.Freeze(st, R.EnemyTarget(st, p, lane))
    for _, l in ipairs(neighbours(lane)) do R.Freeze(st, R.EnemyTarget(st, p, l)) end
  end }

add { id = "might", name = "Blessing of Might", cost = 1, type = "tactic", rarity = "common", target = "friend",
  text = "Give one of your units +2/+2.", flavor = "Hit it harder, with the Light's permission.",
  icon = icons("Spell_Holy_FistOfJustice"),
  play = function(st, p, lane) R.Buff(st, R.FriendTarget(st, p, lane), 2, 2) end }

add { id = "execute", name = "Execute", cost = 1, type = "tactic", rarity = "rare", target = "enemy",
  text = "Destroy the enemy unit in a lane, if it is damaged.", flavor = "Finish what someone else started.",
  icon = icons("INV_Sword_48", "Ability_Warrior_Decisivestrike"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t and t.hp < t.maxHp then R.Destroy(st, t) end
  end }

-- ---------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------
add { id = "hound", name = "Hound", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, tribe = "beast", collectible = false,
  flavor = "Fetch.", icon = icons("Ability_Hunter_Pet_Hyena", "Ability_Hunter_Pet_Wolf") }

add { id = "scout", name = "Murloc Scout", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, tribe = "murloc", collectible = false,
  flavor = "Mrgl?", icon = icons("INV_Misc_Fish_02", "INV_Misc_Fish_01") }

add { id = "bones", name = "Skeleton", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, tribe = "undead", collectible = false,
  flavor = "Clack.", icon = icons("INV_Misc_Bone_HumanSkull_01", "Spell_Shadow_RaiseDead") }

