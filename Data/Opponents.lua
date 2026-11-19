-- The computer opponents ("the tavern circuit"), in ladder order: beating one
-- unlocks the next. Their decks follow the same rules as yours: copy limits
-- and the curve (Collection.CURVE).
--
-- signature: a card that isn't in packs. It's the reward for the opponent's
-- second star (Collection.STARS), or it can be crafted.
local _, ns = ...

local function deck(spec)
  local out = {}
  for id, n in pairs(spec) do
    for _ = 1, n do out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

local I = "Interface\\Icons\\"

ns.Opponents = {
  {
    id = "dorn", name = "Flightmaster Dorn", short = "Dorn", title = "Keeps gryphons. Collects strays.", level = "easy",
    icon = { I .. "Ability_Mount_Gryphon_01", I .. "Ability_Hunter_Pet_WindSerpent" },
    hello = "Got a few minutes before the next bird's ready. Deal 'em.",
    win = "Ha! The beasts always know.", lose = "Fair's fair. Safe flight, friend.",
    signature = "bangalash",
    deck = deck { wolf = 2, boar = 2, strider = 2, spider = 2, croc = 2, raptor = 1, kobold = 2, vulture = 2, bat = 1, potion = 2, shout = 2 },
  },
  {
    id = "bluegill", name = "Old Bluegill", short = "Bluegill", title = "Fishes the Lakeshire docks. Talks to the catch.", level = "easy",
    icon = { I .. "INV_Misc_Fish_02", I .. "Trade_Fishing" },
    hello = "Sit, sit. The murlocs taught me this one.",
    win = "Mrgl. That means 'pay up'.", lose = "Hm. They never taught me that part.",
    signature = "murkeye",
    deck = deck { coastrunner = 2, murloc = 2, tidehunter = 2, netter = 2, lurker = 2, oracle = 2, warrior = 1, shoal = 1,
      murkeye = 1, potion = 1, shout = 2, turtle = 2 },
  },
  {
    id = "sally", name = "Sally Mudwhistle", short = "Sally", title = "Deckhand on the Booty Bay run", level = "normal",
    icon = { I .. "INV_Misc_Coin_01" },
    hello = "Long crossing. Let's make it interesting.",
    win = "Pay up, landlubber.", lose = "Cheated, probably. Again tomorrow?",
    signature = "seahorn",
    deck = deck { kobold = 2, murloc = 2, thug = 2, gnoll = 2, axe = 2, demo = 2, fireball = 2, evisc = 2,
      potion = 1, tinker = 1, bruiser = 1, shredder = 1 },
  },
  {
    id = "grumbletusk", name = "Innkeeper Grumbletusk", short = "Grumbletusk", title = "Runs the table by the hearth", level = "normal",
    icon = { I .. "INV_Drink_05", I .. "INV_Misc_Head_Orc_01" },
    hello = "House rules: loser buys the next round.",
    win = "Another round on you, then.", lose = "Bah. Drinks are on me.",
    signature = "hogger",
    deck = deck { grunt = 2, troll = 2, axe = 2, ghoul = 2, bat = 1, warmaster = 2, shout = 2, kodo = 1,
      wolf = 2, bandage = 1, hogger = 1, gnoll = 2 },
  },
  {
    id = "fingers", name = "Lil Fingers", short = "Fingers", title = "Deals for the Brotherhood. Counts for herself.", level = "normal",
    icon = { I .. "INV_Misc_Bandana_03", I .. "Ability_Stealth" },
    hello = "Keep your hands where I can see them. Mine too, if you can.",
    win = "Nothing personal. It's all personal.", lose = "You're quick. Edwin should hear about you.",
    signature = "vancleef",
    deck = deck { footpad = 2, thug = 2, pillager = 2, smuggler = 2, nightblade = 2, taskmaster = 2, ambush = 2, vanish = 1,
      evisc = 2, demo = 1, smite = 1, vancleef = 1 },
  },
  {
    id = "graves", name = "Sexton Graves", short = "Graves", title = "Tends the Raven Hill plots. They tend back.", level = "hard",
    icon = { I .. "INV_Misc_Bone_HumanSkull_01", I .. "Spell_Shadow_RaiseDead" },
    hello = "Quiet night. Most of my regulars don't talk.",
    win = "I'll save you a plot.", lose = "Well. That hasn't happened since I was alive.",
    signature = "rivendare",
    deck = deck { skeleton = 2, corpse = 2, ghoul = 2, deathcoil = 2, banshee = 2, necro = 1, gargoyle = 2, patchwork = 2,
      raise = 1, rivendare = 1, bat = 2, execute = 1 },
  },
  {
    id = "pellwick", name = "Archmage Pellwick", short = "Pellwick", title = "Retired. Allegedly.", level = "hard",
    icon = { I .. "Spell_Holy_MagicalSentry", I .. "Spell_Nature_StarFall" },
    hello = "I've calculated every outcome. Please, proceed.",
    win = "As predicted.", lose = "A statistical anomaly. Fascinating.",
    signature = "azuregos",
    deck = deck { apprentice = 2, fireball = 2, poly = 1, blizzard = 1, chain = 1, mountaineer = 2, croc = 2,
      tinker = 2, potion = 2, azuregos = 1, kobold = 2, bruiser = 1, scorpid = 1 },
  },
  {
    id = "prestor", name = "Lady Katrana Prestor", short = "Lady Prestor", title = "Of House Prestor. Very real.", level = "hard",
    icon = { I .. "INV_Misc_Head_Dragon_Black", I .. "INV_Misc_Head_Dragon_01" },
    hello = "How delightful. A commoner wishes to play.",
    win = "How fortuitous.", lose = "Enjoy it, little mortal.",
    signature = "onyxia",
    deck = deck { crusader = 2, mountaineer = 2, bear = 2, murloc = 2, potion = 2, evisc = 2, princess = 1,
      bruiser = 2, scorpid = 2, shieldwall = 1, onyxia = 1, spider = 1 },
  },
}

-- The reward for earning every star on the circuit.
ns.CHAMPION_CARD = "ragnaros"

ns.OpponentById = {}
for i, o in ipairs(ns.Opponents) do
  o.index = i
  ns.OpponentById[o.id] = o
  ns.Cards.byId[o.signature].signature = o.id
end
ns.Cards.byId[ns.CHAMPION_CARD].signature = "champion"
