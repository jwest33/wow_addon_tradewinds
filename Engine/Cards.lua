-- The core set. Card fields:
--   id, name, cost (supply), type ("unit" | "tactic"), rarity
--   units: atk, hp, kw = { keyword = true }, and optional hooks
--     arrive(st, u)        when it's revealed
--     fallen(st, u)        when it dies (u still knows its owner and lane)
--     roundStart(st, u)    at the start of every round
--     onDeath(st, u, dead) whenever another unit dies
--   tactics: target ("enemy" | "friend" | "none"), play(st, p, lane)
--     splash = true: an enemy tactic that also hits the lanes beside its
--     target, so it's still worth aiming at a unit it can't target (Stealth)
--   text (rules beyond keywords), flavor, icon (list of candidates, first one
--   the client has wins)
--   tribe, aura, bonus: see Engine/CardsRoads.lua (the second set)
--   item, synergy, twin: see Engine/CardsTribes.lua
--   signature: set by Data/Opponents.lua on cards that are won, not found in packs
local _, ns = ...
local L = ns.L
local R = ns.Rules

local Cards = { list = {}, byId = {} }
ns.Cards = Cards

Cards.RARITIES = { "common", "uncommon", "rare", "epic", "legendary" }
Cards.RARITY_RANK = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
Cards.TRIBES = { beast = L["Beast"], humanoid = L["Humanoid"], murloc = L["Murloc"], undead = L["Undead"], defias = L["Defias"],
  dragonkin = L["Dragonkin"] }
Cards.TRIBE_ORDER = { "beast", "humanoid", "murloc", "undead", "defias", "dragonkin" }
-- Which file a card came from (not shown to players).
Cards.SETS = { core = L["Core set"], roads = L["Roads of Azeroth"], tribes = L["Tribes of Azeroth"] }

local function icons(...)
  local t = {}
  for i, n in ipairs({ ... }) do t[i] = "Interface\\Icons\\" .. n end
  return t
end

-- The card's text in the client's language (Locales/Locale.lua).
local function translate(c)
  c.name = L[c.name]
  if c.text then c.text = L[c.text] end
  if c.flavor then c.flavor = L[c.flavor] end
end

local function add(c)
  translate(c)
  c.set = c.set or "core"
  if c.collectible == nil then c.collectible = true end
  c.kw = c.kw or {}
  Cards.list[#Cards.list + 1] = c
  Cards.byId[c.id] = c
end
Cards.Add = add
Cards.Icons = icons

local function neighbours(lane)
  local out = {}
  if lane > 1 then out[#out + 1] = lane - 1 end
  if lane < R.LANES then out[#out + 1] = lane + 1 end
  return out
end
Cards.Neighbours = neighbours

local function across(st, u)
  return st.players[3 - u.owner].board[u.lane]
end

-- Fallen: n damage to the enemy unit across, if there is one.
local function hitAcross(st, u, n)
  local t = across(st, u)
  if t then R.Damage(st, t, n) else R.Fizzle(st, u, "notarget") end
end
Cards.HitAcross = hitAcross

local function eachEnemy(st, p, fn)
  for _, x in ipairs(R.Units(st, 3 - p)) do fn(x) end
end

-- ---------------------------------------------------------------------------
-- Common
-- ---------------------------------------------------------------------------
add { id = "kobold", name = "Kobold Vermin", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 2,
  flavor = "You no take candle!", icon = icons("INV_Misc_Head_Kobold_01", "Trade_Mining") }

add { id = "murloc", name = "Murloc Forager", cost = 1, type = "unit", rarity = "common", atk = 2, hp = 1,
  flavor = "Mrrrggk!", icon = icons("INV_Misc_Head_Murloc_01", "INV_Misc_Fish_02") }

add { id = "wolf", name = "Young Wolf", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, kw = { swift = true },
  flavor = "The first thing that bit you in Elwynn.", icon = icons("Ability_Hunter_Pet_Wolf") }

add { id = "boar", name = "Mottled Boar", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 2, kw = { pierce = true },
  flavor = "Durotar's welcoming committee.", icon = icons("Ability_Hunter_Pet_Boar") }

add { id = "thug", name = "Defias Thug", cost = 2, type = "unit", rarity = "common", atk = 2, hp = 3,
  flavor = "Westfall's finest, by default.", icon = icons("INV_Misc_Bandana_03", "INV_Misc_Head_Human_01") }

add { id = "gnoll", name = "Riverpaw Gnoll", cost = 2, type = "unit", rarity = "common", atk = 3, hp = 2,
  flavor = "Hogger sends his regards.", icon = icons("INV_Misc_Head_Gnoll_01", "Ability_Hunter_Pet_Hyena") }

add { id = "mountaineer", name = "Ironforge Mountaineer", cost = 2, type = "unit", rarity = "common", atk = 1, hp = 4,
  kw = { guard = true }, flavor = "Nothing gets past Dun Morogh. Nothing.",
  icon = icons("INV_Misc_Head_Dwarf_01", "INV_Shield_06") }

add { id = "strider", name = "Plainstrider", cost = 2, type = "unit", rarity = "common", atk = 1, hp = 3,
  text = "Arrive: restore 2 Morale.", flavor = "Mulgore's most dignified bird.",
  icon = icons("Ability_Hunter_Pet_TallStrider"),
  arrive = function(st, u) R.RestoreMorale(st, u.owner, 2) end }

add { id = "spider", name = "Forest Spider", cost = 2, type = "unit", rarity = "common", atk = 1, hp = 3, kw = { venom = true },
  flavor = "Duskwood's welcome mat.", icon = icons("Ability_Hunter_Pet_Spider") }

add { id = "croc", name = "Loch Crocolisk", cost = 3, type = "unit", rarity = "common", atk = 2, hp = 5,
  flavor = "Loch Modan's lazy landlord.", icon = icons("Ability_Hunter_Pet_Crocolisk") }

add { id = "axe", name = "Darkspear Axe Thrower", cost = 3, type = "unit", rarity = "common", atk = 2, hp = 3, kw = { ranged = true },
  flavor = "Never misses the weak link.", icon = icons("INV_ThrowingAxe_01", "INV_Axe_02") }

add { id = "grunt", name = "Orgrimmar Grunt", cost = 3, type = "unit", rarity = "common", atk = 3, hp = 4,
  flavor = "Lok'tar!", icon = icons("INV_Misc_Head_Orc_01", "INV_Axe_02") }

add { id = "raptor", name = "Sunscale Lashtail", cost = 3, type = "unit", rarity = "common", atk = 3, hp = 2, kw = { swift = true },
  flavor = "The Barrens' fastest grudge.", icon = icons("Ability_Hunter_Pet_Raptor") }

add { id = "bear", name = "Grizzled Black Bear", cost = 4, type = "unit", rarity = "common", atk = 3, hp = 6, kw = { guard = true },
  flavor = "Old, grumpy, and in your way.", icon = icons("Ability_Hunter_Pet_Bear") }

add { id = "crusader", name = "Scarlet Crusader", cost = 4, type = "unit", rarity = "common", atk = 4, hp = 4, kw = { rally = true },
  flavor = "Zeal in its purest, worst form.", icon = icons("Spell_Holy_SealOfMight") }

add { id = "ogre", name = "Mosh'Ogg Brute", cost = 5, type = "unit", rarity = "common", atk = 4, hp = 5, kw = { cleave = true },
  flavor = "Swings first. Counts never.", icon = icons("Ability_Warrior_Cleave") }

add { id = "fireball", name = "Fireball", cost = 2, type = "tactic", rarity = "common", target = "enemy",
  text = "Deal 3 damage to the enemy unit in a lane. If the lane is empty, deal 2 damage to their Morale instead.",
  flavor = "The first spell every apprentice learns, and the last thing many targets see.",
  icon = icons("Spell_Fire_Fireball02"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t then R.Damage(st, t, 3)
    elseif not st.players[3 - p].board[lane] then R.HitMorale(st, 3 - p, 2) end
  end }

add { id = "shout", name = "Battle Shout", cost = 1, type = "tactic", rarity = "common", target = "none",
  text = "Your units get +1 attack this round.", flavor = "Louder is better.",
  icon = icons("Ability_Warrior_BattleShout"),
  play = function(st, p) for _, u in ipairs(R.Units(st, p)) do R.TempAttack(st, u, 1) end end }

add { id = "potion", name = "Healing Potion", cost = 1, type = "tactic", rarity = "common", target = "none",
  text = "Restore 4 Morale.", flavor = "Tastes like cherries and regret.",
  icon = icons("INV_Potion_51", "Spell_Holy_Heal"),
  play = function(st, p) R.RestoreMorale(st, p, 4) end }

add { id = "bandage", name = "Heavy Linen Bandage", cost = 1, type = "tactic", rarity = "common", target = "friend",
  text = "Fully heal one of your units, and restore 2 Morale.", flavor = "Hold still.",
  icon = icons("INV_Misc_Bandage_15", "Spell_Holy_Heal02"),
  play = function(st, p, lane)
    R.Heal(st, R.FriendTarget(st, p, lane))
    R.RestoreMorale(st, p, 2)
  end }

-- ---------------------------------------------------------------------------
-- Uncommon
-- ---------------------------------------------------------------------------
add { id = "watcher", name = "Harvest Watcher", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 4,
  text = "Fallen: deal 2 damage to the enemy unit across.", flavor = "Westfall's scarecrows took the job too seriously.",
  icon = icons("INV_Misc_Gear_01"),
  fallen = function(st, u) hitAcross(st, u, 2) end }

add { id = "vulture", name = "Carrion Vulture", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 2,
  text = "Whenever another unit dies, gains +1 attack.", flavor = "Patience is a virtue. So is lunch.",
  icon = icons("Ability_Hunter_Pet_Vulture"),
  onDeath = function(st, u) R.Buff(st, u, 1, 0) end }

add { id = "tinker", name = "Gnomish Tinkerer", cost = 2, type = "unit", rarity = "uncommon", atk = 1, hp = 2,
  text = "Arrive: draw a card.", flavor = "Results not guaranteed. Explosions likely.",
  icon = icons("Trade_Engineering"),
  arrive = function(st, u) R.Draw(st, u.owner, 1) end }

add { id = "ghoul", name = "Rotting Ghoul", cost = 2, type = "unit", rarity = "uncommon", atk = 2, hp = 2, kw = { sturdy = true },
  flavor = "Already dead. Not done.", icon = icons("Spell_Shadow_RaiseDead") }

add { id = "troll", name = "Witherbark Berserker", cost = 3, type = "unit", rarity = "uncommon", atk = 3, hp = 3, kw = { regen = true },
  flavor = "Arathi's trolls grow back. Mostly.", icon = icons("INV_Misc_Head_Troll_01", "Ability_Racial_Bloodrage") }

add { id = "kodo", name = "Barrens Kodo", cost = 5, type = "unit", rarity = "uncommon", atk = 3, hp = 8, kw = { guard = true },
  flavor = "Moves at its own pace. Which is slowly. Through you.", icon = icons("Ability_Mount_Kodo_01") }

add { id = "bat", name = "Vampiric Duskbat", cost = 2, type = "unit", rarity = "uncommon", atk = 2, hp = 2, kw = { drain = true },
  flavor = "Tirisfal's night shift.", icon = icons("Ability_Hunter_Pet_Bat") }

add { id = "scorpid", name = "Venomtail Scorpid", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 4, kw = { venom = true },
  flavor = "Watch your step in the Valley of Trials.", icon = icons("Ability_Hunter_Pet_Scorpid") }

add { id = "apprentice", name = "Dalaran Apprentice", cost = 3, type = "unit", rarity = "uncommon", atk = 2, hp = 2, kw = { ranged = true },
  text = "Arrive: deal 1 damage to a random enemy unit.", flavor = "Still practising. On you.",
  icon = icons("Spell_Holy_MagicalSentry", "Spell_Nature_StarFall"),
  arrive = function(st, u)
    local list = R.Units(st, 3 - u.owner)
    if #list > 0 then R.Damage(st, list[R.Random(st, #list)], 1) end
  end }

add { id = "nova", name = "Frost Nova", cost = 3, type = "tactic", rarity = "uncommon", target = "none",
  text = "Freeze every enemy unit: they don't strike this round.", flavor = "Chill out.",
  icon = icons("Spell_Frost_FrostNova"),
  play = function(st, p) eachEnemy(st, p, function(x) R.Freeze(st, x) end) end }

add { id = "evisc", name = "Eviscerate", cost = 2, type = "tactic", rarity = "uncommon", target = "enemy",
  text = "Deal 4 damage to the enemy unit in a lane.", flavor = "Five combo points well spent.",
  icon = icons("Ability_Rogue_Eviscerate"),
  play = function(st, p, lane) R.Damage(st, R.EnemyTarget(st, p, lane), 4) end }

add { id = "shieldwall", name = "Shield Wall", cost = 1, type = "tactic", rarity = "uncommon", target = "friend",
  text = "Give one of your units +3 health and Guard.", flavor = "Plant your feet.",
  icon = icons("Ability_Warrior_ShieldWall"),
  play = function(st, p, lane) R.Buff(st, R.FriendTarget(st, p, lane), 0, 3, "guard") end }

-- ---------------------------------------------------------------------------
-- Rare
-- ---------------------------------------------------------------------------
add { id = "bruiser", name = "Booty Bay Bruiser", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 5,
  kw = { guard = true, sturdy = true }, flavor = "Keeps the peace. Breaks the rest.",
  icon = icons("INV_Misc_Coin_02") }

add { id = "gryphon", name = "Wildhammer Gryphon Rider", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 3,
  kw = { swift = true, pierce = true }, flavor = "Straight down, straight through.",
  icon = icons("Ability_Mount_Gryphon_01", "Ability_Hunter_Pet_WindSerpent") }

add { id = "demo", name = "Dark Iron Demolitionist", cost = 3, type = "unit", rarity = "rare", atk = 2, hp = 2,
  text = "Fallen: deal 3 damage to the enemy unit across.", flavor = "Short fuse, long memory.",
  icon = icons("Spell_Fire_SelfDestruct"),
  fallen = function(st, u) hitAcross(st, u, 3) end }

add { id = "medic", name = "Argent Dawn Medic", cost = 3, type = "unit", rarity = "rare", atk = 1, hp = 4,
  text = "Round start: restore 2 health to your units in the neighbouring lanes.", flavor = "Triage, Light-style.",
  icon = icons("Spell_Holy_Heal02"),
  roundStart = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Heal(st, st.players[u.owner].board[l], 2) end
  end }

add { id = "warmaster", name = "Frostwolf Warmaster", cost = 4, type = "unit", rarity = "rare", atk = 3, hp = 4, kw = { rally = true },
  text = "Arrive: your units in the neighbouring lanes get +1 health.", flavor = "For the clan!",
  icon = icons("INV_BannerPVP_01"),
  arrive = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Buff(st, st.players[u.owner].board[l], 0, 1) end
  end }

add { id = "shredder", name = "Venture Co. Shredder", cost = 5, type = "unit", rarity = "rare", atk = 4, hp = 5,
  kw = { cleave = true, sturdy = true }, flavor = "Stonetalon's least sustainable logging.",
  icon = icons("INV_Misc_Gear_02", "Trade_Engineering") }

add { id = "blizzard", name = "Blizzard", cost = 4, type = "tactic", rarity = "rare", target = "none",
  text = "Deal 2 damage to every enemy unit.", flavor = "Bring a coat.",
  icon = icons("Spell_Frost_IceStorm"),
  play = function(st, p) eachEnemy(st, p, function(x) R.Damage(st, x, 2) end) end }

add { id = "poly", name = "Polymorph", cost = 3, type = "tactic", rarity = "rare", target = "enemy",
  text = "Turn the enemy unit in a lane into a 0/1 Sheep.", flavor = "Baa.",
  icon = icons("Spell_Nature_Polymorph"),
  play = function(st, p, lane)
    local t = R.EnemyTarget(st, p, lane)
    if t then R.Transform(st, t, "sheep") end
  end }

add { id = "chain", name = "Chain Lightning", cost = 3, type = "tactic", rarity = "rare", target = "enemy",
  text = "Deal 3 damage to the enemy unit in a lane and 1 damage to the enemy units next to it.",
  flavor = "Bounces are free.", icon = icons("Spell_Nature_ChainLightning"), splash = true,
  play = function(st, p, lane)
    R.Damage(st, R.EnemyTarget(st, p, lane), 3)
    for _, l in ipairs(neighbours(lane)) do R.Damage(st, R.EnemyTarget(st, p, l), 1) end
  end }

-- ---------------------------------------------------------------------------
-- Epic
-- ---------------------------------------------------------------------------
add { id = "hogger", name = "Hogger", cost = 4, type = "unit", rarity = "epic", atk = 4, hp = 4,
  text = "Arrive: summon a 1/1 Riverpaw Runt in each of your empty neighbouring lanes.",
  flavor = "Elwynn's most wanted.", icon = icons("INV_Misc_Head_Gnoll_01", "Ability_Hunter_Pet_Hyena"),
  arrive = function(st, u)
    for _, l in ipairs(neighbours(u.lane)) do R.Summon(st, u.owner, l, "runt") end
  end }

add { id = "princess", name = "Princess", cost = 3, type = "unit", rarity = "epic", atk = 2, hp = 5, kw = { guard = true },
  text = "Fallen: restore 4 Morale.", flavor = "The pride of the Brackwell Pumpkin Patch.",
  icon = icons("Ability_Hunter_Pet_Boar"),
  fallen = function(st, u) R.RestoreMorale(st, u.owner, 4) end }

add { id = "azuregos", name = "Azuregos", cost = 6, type = "unit", rarity = "epic", atk = 5, hp = 7,
  text = "Arrive: freeze every enemy unit (they don't strike this round).", flavor = "Azshara's most bookish resident.",
  icon = icons("INV_Misc_Head_Dragon_Blue", "Spell_Frost_FrostNova"),
  arrive = function(st, u) eachEnemy(st, u.owner, function(x) R.Freeze(st, x) end) end }

add { id = "kazzak", name = "Lord Kazzak", cost = 6, type = "unit", rarity = "epic", atk = 5, hp = 6,
  kw = { cleave = true }, text = "Arrive: restore 3 Morale.", flavor = "The Blasted Lands earned the name.",
  icon = icons("Spell_Shadow_SummonInfernal"),
  arrive = function(st, u) R.RestoreMorale(st, u.owner, 3) end }

-- ---------------------------------------------------------------------------
-- Legendary
-- ---------------------------------------------------------------------------
add { id = "onyxia", name = "Onyxia", cost = 6, type = "unit", rarity = "legendary", atk = 6, hp = 7,
  text = "Arrive: deal 2 damage to every enemy unit.", flavor = "Lady Prestor sends her apologies.",
  icon = icons("INV_Misc_Head_Dragon_01", "INV_Misc_Head_Dragon_Black"),
  arrive = function(st, u) eachEnemy(st, u.owner, function(x) R.Damage(st, x, 2) end) end }

add { id = "ragnaros", name = "Ragnaros", cost = 6, type = "unit", rarity = "legendary", atk = 6, hp = 6,
  kw = { cleave = true, pierce = true }, flavor = "Too soon, executus.",
  icon = icons("INV_Hammer_Unique_Sulfuras", "Spell_Fire_Immolation") }

add { id = "vancleef", name = "Edwin VanCleef", cost = 4, type = "unit", rarity = "legendary", atk = 4, hp = 3,
  kw = { swift = true, stealth = true, pierce = true }, flavor = "The Brotherhood remembers.",
  icon = icons("Ability_Stealth"), display = 2029 }

-- ---------------------------------------------------------------------------
-- Tokens (made by other cards, never in packs or decks)
-- ---------------------------------------------------------------------------
add { id = "runt", name = "Riverpaw Runt", cost = 1, type = "unit", rarity = "common", atk = 1, hp = 1, collectible = false,
  flavor = "Hogger's nephew. Allegedly.", icon = icons("INV_Misc_Head_Gnoll_01", "Ability_Hunter_Pet_Hyena") }

add { id = "sheep", name = "Sheep", cost = 1, type = "unit", rarity = "common", atk = 0, hp = 1, collectible = false,
  flavor = "Baa.", icon = icons("Spell_Nature_Polymorph") }

-- Stand-in for "something the opponent might play", used only by the AI's
-- what-if simulations.
add { id = "ghost", name = "Unknown Unit", cost = 0, type = "unit", rarity = "common", atk = 1, hp = 1, collectible = false,
  icon = icons("INV_Misc_QuestionMark") }

-- Tribes of the core set's cards.
for tribe, ids in pairs({
  beast = { "wolf", "boar", "strider", "spider", "croc", "raptor", "bear", "vulture", "kodo", "bat", "scorpid", "princess" },
  murloc = { "murloc" },
  undead = { "ghoul" },
  defias = { "thug", "vancleef" },
  dragonkin = { "azuregos", "onyxia" },
}) do
  for _, id in ipairs(ids) do Cards.byId[id].tribe = tribe end
end

-- Collectible cards by rarity, sorted by cost then name (packs and the
-- binder). Called by the last card file (Engine/CardsTribes.lua) once every
-- set is in.
function Cards.Finish()
  Cards.byRarity = {}
  for _, r in ipairs(Cards.RARITIES) do Cards.byRarity[r] = {} end
  Cards.collectible = {}
  for _, c in ipairs(Cards.list) do
    if c.collectible then
      Cards.collectible[#Cards.collectible + 1] = c
      table.insert(Cards.byRarity[c.rarity], c.id)
    end
  end
  table.sort(Cards.collectible, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
end

-- Card text for tooltips: keyword names, then the card's own text.
function Cards.KeywordList(kw)
  local list = {}
  for _, k in ipairs(R.KEYWORDS) do
    if kw[k.key] then list[#list + 1] = k end
  end
  return list
end
