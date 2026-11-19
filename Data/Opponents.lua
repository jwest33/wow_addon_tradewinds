-- The computer opponents ("the tavern circuit"). Their decks follow the same
-- rules as yours: copy limits and the curve (Collection.CURVE).
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
    deck = deck { wolf = 2, boar = 2, strider = 2, spider = 2, croc = 2, raptor = 1, kobold = 2, vulture = 2, bat = 1, potion = 2, shout = 2 },
  },
  {
    id = "sally", name = "Sally Mudwhistle", short = "Sally", title = "Deckhand on the Booty Bay run", level = "normal",
    icon = { I .. "INV_Misc_Coin_01" },
    hello = "Long crossing. Let's make it interesting.",
    win = "Pay up, landlubber.", lose = "Cheated, probably. Again tomorrow?",
    deck = deck { kobold = 2, murloc = 2, thug = 2, gnoll = 2, axe = 2, demo = 2, fireball = 2, evisc = 2,
      potion = 1, tinker = 1, bruiser = 1, shredder = 1 },
  },
  {
    id = "grumbletusk", name = "Innkeeper Grumbletusk", short = "Grumbletusk", title = "Runs the table by the hearth", level = "normal",
    icon = { I .. "INV_Drink_05", I .. "INV_Misc_Head_Orc_01" },
    hello = "House rules: loser buys the next round.",
    win = "Another round on you, then.", lose = "Bah. Drinks are on me.",
    deck = deck { grunt = 2, troll = 2, axe = 2, ghoul = 2, bat = 1, warmaster = 2, shout = 2, kodo = 1,
      wolf = 2, bandage = 1, hogger = 1, gnoll = 2 },
  },
  {
    id = "pellwick", name = "Archmage Pellwick", short = "Pellwick", title = "Retired. Allegedly.", level = "hard",
    icon = { I .. "Spell_Holy_MagicalSentry", I .. "Spell_Nature_StarFall" },
    hello = "I've calculated every outcome. Please, proceed.",
    win = "As predicted.", lose = "A statistical anomaly. Fascinating.",
    deck = deck { apprentice = 2, fireball = 2, poly = 1, blizzard = 1, chain = 1, mountaineer = 2, croc = 2,
      tinker = 2, potion = 2, azuregos = 1, kobold = 2, bruiser = 1, scorpid = 1 },
  },
  {
    id = "prestor", name = "Lady Katrana Prestor", short = "Lady Prestor", title = "Of House Prestor. Very real.", level = "hard",
    icon = { I .. "INV_Misc_Head_Dragon_Black", I .. "INV_Misc_Head_Dragon_01" },
    hello = "How delightful. A commoner wishes to play.",
    win = "How fortuitous.", lose = "Enjoy it, little mortal.",
    deck = deck { crusader = 2, mountaineer = 2, bear = 2, murloc = 2, potion = 2, evisc = 2, princess = 1,
      bruiser = 2, scorpid = 2, shieldwall = 1, onyxia = 1, spider = 1 },
  },
}

ns.OpponentById = {}
for _, o in ipairs(ns.Opponents) do ns.OpponentById[o.id] = o end
