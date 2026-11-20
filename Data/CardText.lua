-- The short rules text printed on a card's face (c.short). The full wording
-- (c.text) is in the tooltip. Every card with rules text needs a line here,
-- at most 38 characters so it fits the card's text box under a keyword line.
local _, ns = ...
local L = ns.L

local SHORT = {
  -- core set
  strider = "Arrive: restore 2 Morale",
  fireball = "3 damage, or 2 to Morale if empty",
  shout = "Your units: +1 attack this round",
  potion = "Restore 4 Morale",
  bandage = "Fully heal a unit. Restore 2 Morale",
  watcher = "Fallen: 2 damage across",
  vulture = "+1 attack when a unit dies",
  tinker = "Arrive: draw a card",
  apprentice = "Arrive: 1 damage to a random enemy",
  nova = "Freeze every enemy unit",
  evisc = "4 damage to a unit",
  shieldwall = "+3 health and Guard",
  demo = "Fallen: 3 damage across",
  medic = "Round start: heal neighbours 2",
  warmaster = "Arrive: neighbours +1 health",
  blizzard = "2 damage to every enemy unit",
  poly = "Turn a unit into a 0/1 Sheep",
  chain = "3 damage, 1 to those beside",
  hogger = "Arrive: 1/1 Runts beside him",
  princess = "Fallen: restore 4 Morale",
  azuregos = "Arrive: freeze every enemy",
  kazzak = "Arrive: restore 3 Morale",
  onyxia = "Arrive: 2 damage to every enemy",
  -- Roads of Azeroth
  cub = "Arrive: +1 attack with a Beast",
  packleader = "Other Beasts: +1 attack",
  tamer = "Arrive: a 1/1 Hound beside it",
  gorilla = "Arrive: +1/+1 per other Beast",
  bangalash = "+1/+1 when your Beast dies",
  callwild = "Your Beasts: +1/+1",
  coastrunner = "+1 attack per other Murloc",
  tidehunter = "Arrive: a 1/1 Scout beside it",
  netter = "Arrive: freeze the unit across",
  oracle = "Arrive: other Murlocs +1/+1",
  warrior = "Other Murlocs: +1 attack",
  murkeye = "+1 attack per other Murloc",
  shoal = "1/1 Scouts in your empty lanes",
  skeleton = "Fallen: 1 damage across",
  corpse = "Fallen: leaves a 1/1 Skeleton",
  necro = "Round start: a 1/1 Skeleton beside",
  banshee = "Fallen: -2 attack across",
  rivendare = "Arrive: other Undead +1/+1, Sturdy",
  deathcoil = "2 damage. Restore 2 Morale",
  raise = "Return your last dead unit",
  pillager = "Arrive: enemy loses 1 Morale",
  smuggler = "Arrive: draw with a Defias",
  taskmaster = "Other Defias: +1 attack",
  smite = "Arrive: freeze across and beside",
  ambush = "4 damage to a new arrival, else 2",
  vanish = "Stealth and +2/+2",
  drake = "Arrive: 1 damage to every enemy",
  technician = "Your Dragonkin: +1 attack",
  drakkisath = "Arrive: other Dragonkin +2 health",
  flamebreath = "4 damage, 2 to those beside",
  peon = "Arrive: you lose 1 Morale",
  chaplain = "Round start: restore 1 Morale",
  sapper = "Fallen: 1 damage across and beside",
  seahorn = "Arrive: draw 2 cards",
  warstomp = "Freeze a unit and those beside",
  might = "+2/+2",
  execute = "Destroy a damaged unit",
}

for id, text in pairs(SHORT) do
  local c = ns.Cards.byId[id]
  if c then c.short = L[text] end
end
ns.Cards.SHORT = SHORT
