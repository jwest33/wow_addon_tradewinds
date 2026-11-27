-- Traps (SETS_PLAN.md, Wave 2): a card type of its own, set face down in one
-- of your empty lanes. The other player sees that you have a trap set, not
-- where. It springs when an enemy unit strikes into that lane: the strike is
-- stopped, and the trap does what it says. Engine/Rules.lua does the rest
-- (R.SetTrap, R.Spring, R.Redact). Also the Defias cards that work with
-- traps, and more items. Same fields as the other card files, plus:
--   type = "trap"
--   spring(st, p, lane, attacker)   when it springs: p owns the trap, lane is
--                                   where it was, attacker struck into it.
--                                   A unit it summons arrives at the end of
--                                   combat, so it never strikes that round.
-- This is the last card file: it calls Cards.Finish().
local _, ns = ...
local L = ns.L
local R = ns.Rules
local Cards = ns.Cards
local icons, neighbours = Cards.Icons, Cards.Neighbours

Cards.SETS.traps = L["Traps and Trickery"]

local function add(c)
  c.set = "traps"
  Cards.Add(c)
end

local function trap(c)
  c.type = "trap"
  add(c)
end

local function undeadOrDemon(u)
  local tribe = R.Card(u.id).tribe
  return tribe == "undead" or tribe == "demon"
end

-- ---------------------------------------------------------------------------
-- Traps
-- ---------------------------------------------------------------------------
trap { id = "snaketrap", name = "Snake Trap", cost = 1, rarity = "common",
  text = "Springs: a 1/1 Viper with Venom appears in this lane at the end of combat.",
  flavor = "Step lightly in the tall grass.", icon = icons("Ability_Hunter_SnakeTrap", "Spell_Nature_NullifyPoison"),
  spring = function(st, p, lane) R.Summon(st, p, lane, "viper") end }

trap { id = "immolation", name = "Immolation Trap", cost = 2, rarity = "common",
  text = "Springs: deal 3 damage to the unit that sprang it.",
  flavor = "Hunters call it a welcome mat.", icon = icons("Spell_Fire_FlameShock", "Spell_Fire_Immolation"),
  spring = function(st, p, lane, a) R.Damage(st, a, 3) end }

trap { id = "consecrate", name = "Consecrated Ground", cost = 2, rarity = "common",
  text = "Springs: destroy the unit that sprang it if it's Undead or a Demon, otherwise deal 2 damage to it.",
  flavor = "The Light has a long memory for the dead.", icon = icons("Spell_Holy_InnerFire", "Spell_Holy_HolyBolt"),
  spring = function(st, p, lane, a)
    if not a then return end
    if undeadOrDemon(a) then R.Destroy(st, a) else R.Damage(st, a, 2) end
  end }

trap { id = "freezingtrap", name = "Freezing Trap", cost = 2, rarity = "uncommon",
  text = "Springs: the unit that sprang it is frozen next round as well.",
  flavor = "Cold enough to stop a charge in its tracks.", icon = icons("Spell_Frost_ChainsOfIce", "Spell_Frost_FrostNova"),
  spring = function(st, p, lane, a) R.Chill(st, a) end }

trap { id = "shallowgrave", name = "Shallow Grave", cost = 2, rarity = "uncommon",
  text = "Springs: a 1/1 Skeleton appears in this lane and another in an empty lane next to it, at the end of combat.",
  flavor = "Raven Hill never buries anyone very deep.", icon = icons("INV_Misc_Shovel_01", "Spell_Shadow_AnimateDead"),
  spring = function(st, p, lane)
    R.Summon(st, p, lane, "bones")
    for _, l in ipairs(neighbours(lane)) do
      if not st.players[p].board[l] and not R.TrapAt(st, p, l) then
        R.Summon(st, p, l, "bones")
        return
      end
    end
  end }

trap { id = "defiasambush", name = "Defias Ambush", cost = 3, rarity = "uncommon",
  text = "Springs: deal 3 damage to the unit that sprang it, and a 3/3 Defias Ambusher appears in this lane at the end of combat.",
  flavor = "Westfall's roads have more Brotherhood on them than travellers.", icon = icons("Ability_Ensnare", "Ability_Rogue_Ambush"),
  spring = function(st, p, lane, a)
    R.Damage(st, a, 3)
    R.Summon(st, p, lane, "ambusher")
  end }

trap { id = "explosivetrap", name = "Explosive Trap", cost = 2, rarity = "rare",
  text = "Springs: deal 3 damage to the unit that sprang it and 2 damage to the enemy units next to it.",
  flavor = "The bang is the easy part. The cleanup takes all day.", icon = icons("INV_Misc_Bomb_06", "Spell_Fire_SelfDestruct"),
  spring = function(st, p, lane, a)
    if not a then return end
    R.Damage(st, a, 3)
    local board = st.players[a.owner].board
    for _, l in ipairs(neighbours(a.lane)) do R.Damage(st, board[l], 2) end
  end }

trap { id = "landmine", name = "Goblin Land Mine", cost = 2, rarity = "rare",
  text = "Springs: deal 4 damage to the unit that sprang it.",
  flavor = "Mind the pressure plate.", icon = icons("INV_Misc_Bomb_04", "INV_Misc_Bomb_02"),
  spring = function(st, p, lane, a) R.Damage(st, a, 4) end }

-- ---------------------------------------------------------------------------
-- Defias: the Brotherhood works with traps
-- ---------------------------------------------------------------------------
add { id = "trapper", name = "Defias Trapper", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 3,
  tribe = "defias", text = "Arrive: draw a card if you have a trap set.",
  flavor = "Every road out of Moonbrook has one of his snares on it.", icon = icons("INV_Misc_Rope_01", "INV_Misc_Bandana_03"),
  arrive = function(st, u) if R.TrapCount(st, u.owner) > 0 then R.Draw(st, u.owner, 1) end end }

add { id = "watchman", name = "Defias Watchman", cost = 3, type = "unit", rarity = "common", atk = 3, hp = 3,
  tribe = "defias", text = "Arrive: the enemy loses 1 Morale if you have a trap set.",
  flavor = "He doesn't fight. He waits for you to step wrong.", icon = icons("INV_Misc_Spyglass_03", "INV_Misc_Spyglass_01"),
  arrive = function(st, u) if R.TrapCount(st, u.owner) > 0 then R.HitMorale(st, 3 - u.owner, 1) end end }

add { id = "saboteur", name = "Defias Saboteur", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 2,
  tribe = "defias", kw = { stealth = true }, text = "Arrive: set a Snake Trap in one of your empty lanes, picked at random.",
  flavor = "Leaves something nasty behind in every lane he crosses.", icon = icons("INV_Misc_Bomb_01", "Ability_Stealth"),
  arrive = function(st, u)
    local free = R.EmptyLanes(st, u.owner)
    if #free > 0 then R.SetTrap(st, u.owner, free[R.Random(st, #free)], "snaketrap") end
  end }

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------
local function item(c)
  c.type, c.item = "tactic", true
  add(c)
end

local function gear(st, p, lane, atk, hp, kw)
  local u = R.FriendTarget(st, p, lane)
  if u then R.Buff(st, u, atk, hp, kw) end
  return u
end

item { id = "sappercharge", name = "Goblin Sapper Charge", cost = 2, rarity = "common", target = "enemy", splash = true,
  text = "Deal 2 damage to the enemy unit in a lane and 1 damage to the enemy units next to it.",
  flavor = "Some assembly required. No refunds.", icon = icons("Spell_Fire_SelfDestruct", "INV_Misc_Bomb_08"),
  play = function(st, p, lane)
    R.Damage(st, R.EnemyTarget(st, p, lane), 2)
    for _, l in ipairs(neighbours(lane)) do R.Damage(st, R.EnemyTarget(st, p, l), 1) end
  end }

item { id = "holywater", name = "Stratholme Holy Water", cost = 2, rarity = "common", target = "enemy",
  text = "Deal 4 damage to the enemy unit in a lane if it's Undead or a Demon, otherwise 2.",
  flavor = "Blessed in Stratholme, before Stratholme needed it.", icon = icons("INV_Potion_75", "INV_Potion_51"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t then R.Damage(st, t, undeadOrDemon(t) and 4 or 2) end
  end }

item { id = "rocketboots", name = "Goblin Rocket Boots", cost = 1, rarity = "uncommon", target = "friend",
  text = "Give one of your units Swift. Draw a card.", flavor = "Top speed: yes. Steering: no.",
  icon = icons("INV_Boots_Plate_06", "INV_Boots_05"),
  play = function(st, p, lane)
    gear(st, p, lane, 0, 0, "swift")
    R.Draw(st, p, 1)
  end }

item { id = "commission", name = "Argent Dawn Commission", cost = 2, rarity = "uncommon", target = "friend",
  text = "Give one of your units +1/+1 and Sturdy.", flavor = "Proof you've done the Dawn a favour. Several, in fact.",
  icon = icons("INV_Jewelry_Talisman_07", "INV_Misc_Token_ArgentDawn"),
  play = function(st, p, lane) gear(st, p, lane, 1, 1, "sturdy") end }

item { id = "flask", name = "Flask of the Titans", cost = 3, rarity = "rare", target = "friend",
  text = "Give one of your units +1/+5. Restore 3 Morale.", flavor = "One sip and you feel like a mountain.",
  icon = icons("INV_Potion_62", "INV_Potion_51"),
  play = function(st, p, lane)
    gear(st, p, lane, 1, 5)
    R.RestoreMorale(st, p, 3)
  end }

item { id = "ironfoe", name = "Ironfoe", cost = 3, rarity = "epic", target = "friend",
  text = "Give one of your units +3/+3 and Pierce.", flavor = "Forged in Blackrock Depths for someone who never stopped swinging.",
  icon = icons("INV_Mace_10", "INV_Hammer_04"),
  play = function(st, p, lane) gear(st, p, lane, 3, 3, "pierce") end }

-- ---------------------------------------------------------------------------
-- Tokens (brought in by traps, never in packs or decks)
-- ---------------------------------------------------------------------------
add { id = "viper", name = "Viper", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, kw = { venom = true },
  tribe = "beast", collectible = false, flavor = "It was hiding in the grass. So was the trap.",
  icon = icons("Ability_Hunter_AspectoftheViper", "Ability_Hunter_SnakeTrap", "Spell_Nature_NullifyPoison") }

add { id = "ambusher", name = "Defias Ambusher", cost = 3, type = "unit", rarity = "common", atk = 3, hp = 3,
  tribe = "defias", collectible = false, flavor = "Waited in the bushes all round for this.",
  icon = icons("Ability_Rogue_Ambush", "INV_Misc_Bandana_03") }

Cards.Finish()
