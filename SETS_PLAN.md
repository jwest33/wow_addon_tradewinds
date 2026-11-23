# Tradewinds expansion plan: tribes, items, traps and special packs

Written 2026-11-23 against v0.16.0 (rules version 4), and revised twice that
day with the user's decisions (section 10).

**Goal:** many more cards to collect, with very little new to learn.

**How:**
1. **Tribes on every unit.** Beast, Humanoid, Murloc, Undead, Defias,
   Dragonkin, and later Mechanical, Demon and Elemental. Each tribe has its
   own synergy cards, built the way today's tribes already work.
2. **Same stats, different tribe.** Most new cards are new creatures whose
   stats copy a common stat line from another tribe. A plain Beast and a
   plain Humanoid can have the same cost, attack and health. They play the
   same on their own; their tribe decides which synergies they feed.
3. **Items.** A labelled family of tactics: consumables, gear and gadgets.
4. **Traps.** One new card type: set it hidden in an empty lane, and it
   springs when an enemy unit strikes into that lane.
5. **Special packs.** 5 cards with a guaranteed rare or better, earned only
   from milestones and from every ~45 minutes of travel. Regular packs stay
   at 3 cards.

**What a player has to learn:** how traps work, and that there's a second
kind of pack. Tribes are already in the game. Items play exactly like
tactics. No new keywords, resources, lanes or rounds.

**Not in this plan:** reprints, release sets, finishes, the Album, art
styles, card backs, achievements and drafts.

---

## 1. Where things stand

- 97 collectible cards: 77 units and 20 tactics. Only 2 tactics are items
  (Healing Potion, Heavy Linen Bandage).
- Units by tribe: Beast 18, Murloc 8, Defias 8, Dragonkin 8, Undead 7,
  **none 28**.
- 37 units are plain (stats and keywords only), and **no two share a stat
  line** today. That is the gap this plan fills.
- Everything tribes need is already in the code: `c.tribe`, `Cards.TRIBES`,
  `aura = { tribe, atk }`, `bonus(st, u)`, `others(st, u, tribe)` in
  `Engine/CardsRoads.lua`, the type line ("Beast unit"), the binder's Type
  filter and the Guide's "Tribes" section. (`c.set`, core/roads, only says
  which file a card is in, and stays as it is.)
- Packs: 3 cards (`C.PACK_SIZE`), two commons and a third card that is
  uncommon or better (`C.PACK_ODDS`, pity 25). They come from the first win
  of the day, stars, heroic wins, every 10th level, the tutorial, every 20
  minutes of travel (`C.TRAVEL_PACK_SECONDS`, flights, boats and zeppelins),
  and 30 shards each.
- **On login, 0.16.0 deletes card ids it doesn't know** (`C.Init`,
  Collection.lua:221). A player who gets new cards and then goes back to
  0.16.0 loses them. Phase 0 deals with this first.

---

## 2. Tribes

### 2.1 Every unit belongs to one tribe

The five tribes stay as they are, and four are added: **Humanoid**,
**Mechanical**, **Demon** and **Elemental**. The 28 units with no tribe get
one:

| Tribe | Cards that join it |
|---|---|
| Humanoid | Kobold Vermin, Riverpaw Gnoll, Ironforge Mountaineer, Darkspear Axe Thrower, Orgrimmar Grunt, Scarlet Crusader, Mosh'Ogg Brute, Gnomish Tinkerer, Witherbark Berserker, Dalaran Apprentice, Booty Bay Bruiser, Wildhammer Gryphon Rider, Dark Iron Demolitionist, Argent Dawn Medic, Frostwolf Warmaster, Hogger, Stranglethorn Tamer, Scholomance Necromancer, Lazy Peon, Northshire Chaplain, Goblin Sapper, Bloodhoof Brave, Darnassus Archer, Fleet Master Seahorn, Blackwing Technician (25) |
| Mechanical | Harvest Watcher, Venture Co. Shredder |
| Demon | Lord Kazzak |
| Elemental | Ragnaros |

- **Nothing plays differently.** No existing card refers to the new tribes,
  so giving these cards a tribe changes no interaction. No rules version bump
  is needed, and saved matches carry on.
- Tokens: Riverpaw Runt becomes Humanoid. The Sheep stays without a tribe
  (as a Beast it would set off King Bangalash and other Beast cards).
- Tactics, items and traps have no tribe. Some name one, as Call of the Wild
  does.
- Humanoid starts as the biggest tribe (25), so its synergy cards ask for
  more ("if you have 2 other Humanoids") or work only on neighbouring lanes.
- Mechanical, Demon and Elemental get their cards in Wave 3. Until then
  their four cards keep no tribe, so the binder never shows a nearly empty
  tribe.

### 2.2 Same stats, different tribe

The user's example was a plain 3/3 Beast and a plain 3/3 Humanoid. At
today's stat rates a plain 3-cost unit is a 3/4 (Orgrimmar Grunt), so in
practice it looks like this:

| Cost 3, 3/4, no text | Tribe |
|---|---|
| Orgrimmar Grunt (exists) | Humanoid |
| Ashenvale Bear | Beast |
| Murloc Tidewarrior | Murloc |
| Scourge Footsoldier | Undead |
| Black Drakonid | Dragonkin |
| Steam Tonk | Mechanical |
| Felguard Sentry | Demon |
| Lesser Rock Elemental | Elemental |

Each one has its own name, icon and flavour line. On an empty board they're
the same card. Next to a Worg Packleader only the Bear gets +1 attack, and
next to a Bluegill Warrior only the Tidewarrior does.

**The shared stat lines.** Twelve common lines, taken from today's plain
cards. Each tribe takes the lines that suit it. A name means the card already
exists, ✓ is a new card, and · means that tribe doesn't get that line.

| Line | Beast | Humanoid | Murloc | Undead | Defias | Dragonkin | Mechanical | Demon | Elemental | New |
|---|---|---|---|---|---|---|---|---|---|---|
| 1: 1/2 | ✓ | Kobold Vermin | ✓ | · | ✓ | · | ✓ | ✓ | · | 5 |
| 1: 2/1 | ✓ | · | Murloc Forager | ✓ | ✓ | · | · | ✓ | ✓ | 5 |
| 2: 2/3 | ✓ | ✓ | · | ✓ | Defias Thug | · | ✓ | · | ✓ | 5 |
| 2: 3/2 | ✓ | Riverpaw Gnoll | · | ✓ | ✓ | ✓ | · | ✓ | ✓ | 6 |
| 2: 1/4 Guard | ✓ | Ironforge Mountaineer | · | ✓ | · | · | ✓ | ✓ | ✓ | 5 |
| 3: 3/4 | ✓ | Orgrimmar Grunt | ✓ | ✓ | · | ✓ | ✓ | ✓ | ✓ | 7 |
| 3: 3/2 Swift | Sunscale Lashtail | ✓ | · | · | ✓ | ✓ | · | ✓ | ✓ | 5 |
| 3: 2/3 Ranged | · | Darkspear Axe Thrower | ✓ | · | ✓ | ✓ | · | ✓ | ✓ | 5 |
| 4: 3/6 Guard | Grizzled Black Bear | ✓ | · | ✓ | · | ✓ | ✓ | · | ✓ | 5 |
| 4: 4/5 | ✓ | ✓ | · | Patchwork Horror | · | ✓ | ✓ | ✓ | ✓ | 6 |
| 5: 5/6 | ✓ | Bloodhoof Brave | · | · | · | ✓ | ✓ | ✓ | ✓ | 5 |
| 5: 4/5 Cleave | · | Mosh'Ogg Brute | · | · | · | ✓ | ✓ | ✓ | ✓ | 4 |
| **New** | 8 | 4 | 3 | 6 | 5 | 8 | 8 | 10 | 11 | **63** |

Rules for shared lines:
- **Different cards, separate copy limits.** A deck may hold 2 Orgrimmar
  Grunts and 2 Ashenvale Bears. That's fine, because these are plain lines.
- **Only common lines are shared:** stats plus at most one ordinary keyword.
  Effects at rare and above stay unique to one card, and strong keywords
  (Venom, Drain, Stealth with Venom) are not shared, so no deck gets four
  copies of a strong effect.

### 2.3 Synergy per tribe

Every tribe uses some of the patterns today's tribes already have:

| Pattern | Today's example |
|---|---|
| Lord: "Your other X have +1 attack." | Worg Packleader, Bluegill Warrior, Defias Taskmaster |
| Recruit: "Arrive: +1 attack / draw a card if you have another X." | Nightsaber Cub, Defias Smuggler |
| Swarm: "+1 attack for each other X you have." | Murloc Coastrunner, Old Murk-Eye |
| Rally call: "Arrive: your other X get +1/+1." | Bluegill Oracle, Baron Rivendare |
| Avenger: "Whenever another of your X dies, gains +1/+1." | King Bangalash |
| Tribe tactic: "Your X get +1/+1." | Call of the Wild |

Each tribe also gets two or three cards of its own that give it a style:

| Tribe | Style | New examples (starting points) |
|---|---|---|
| Beast | hunt and grow | Silverback Patriarch (5, 4/6: Arrive: your other Beasts get +1/+1); Tracking Hound (2, 2/2: Arrive: draw a card if you have another Beast) |
| Humanoid | formation: neighbours, Guard, Morale | Stormwind Captain (4, 3/4: Arrive: your Humanoids in the neighbouring lanes get +1/+1); Town Crier (2, 1/3: Arrive: draw a card if you have 2 other Humanoids) |
| Murloc | go wide, tokens | Murloc Flopper (2, 2/2: Fallen: summon a Murloc Scout in its lane); Murloc Tidecaller (1, 1/2: +1 attack for each other Murloc) |
| Undead | Fallen effects | Bonecaller (2, 1/3: Fallen: your other Undead get +1 attack); Plague Eater (3, 2/3: whenever another of your Undead dies, gains +1/+1) |
| Defias | Stealth, Morale chip, traps | Defias Trapper (2, 1/3: Arrive: draw a card if you have a trap set); Defias Watchman (3, 3/3: Arrive: the enemy loses 1 Morale if you have a trap set) |
| Dragonkin | big bodies, breath | Wyrmkin Firebrand (3, 2/3: +1 attack for each other Dragonkin); Flamescale Broodling (4, 3/4: Arrive: deal 1 damage to every enemy unit if you have another Dragonkin) |
| Mechanical | explosions, Sturdy | Repair Bot (2, 0/3: Round start: restore 2 health to your other Mechanicals); Mekgineer Thermaplugg (legendary, 5, 4/5: Arrive: your other Mechanicals get Sturdy) |
| Demon | power at a price in Morale | Felguard (3, 4/4: Arrive: you lose 2 Morale); Doomguard (epic, 5, 6/6 Cleave: Arrive: you lose 3 Morale) |
| Elemental | stronger when hurt | Searing Elemental (3, 2/4: has +2 attack while damaged); Baron Geddon (legendary, 5, 4/6: Arrive: deal 1 damage to every unit, yours included) |

Every effect above uses hooks that already exist (`arrive`, `fallen`,
`roundStart`, `onDeath`, `aura`, `bonus`). "While damaged" is a `bonus`
that checks `u.hp < u.maxHp`.

To keep tribes readable on the board, hovering a synergy card lights up the
units it counts.

### 2.4 Sizes

| Tribe | Units now | Shared-line cards | Other new | Units after |
|---|---|---|---|---|
| Beast | 18 | 8 | 2 | 28 |
| Humanoid | 25 | 4 | 4 | 33 |
| Murloc | 8 | 3 | 6 (and the tactic High Tide) | 17 |
| Undead | 7 | 6 | 6 (and the tactic Army of the Dead) | 19 |
| Defias | 8 | 5 | 6 | 19 |
| Dragonkin | 7 | 8 | 4 | 19 |
| Mechanical | 2 | 8 | 10 | 20 |
| Demon | 1 | 10 | 9 | 20 |
| Elemental | 1 | 11 | 8 | 20 |
| **Total** | **77** | **63** | **55** | **195** |

(Corrected after Wave 1 was built: Blackwing Technician had no tribe, so it's a
Humanoid and Dragonkin starts at 7; Murlocs and Undead each got a tribe tactic
in place of one unit.)

Plus about 6 new spells (tribe tactics like Call of the Wild for the tribes
without one), 21 items and 8 traps. **The collection goes from 97 cards to
about 252.**

Rarity of the 155 new cards, roughly: 72 common (most shared-line cards are
common), 46 uncommon, 21 rare, 10 epic, 6 legendary.

---

## 3. Items (decided 2026-11-23: item tactics)

An item is a tactic with `item = true`. It resolves exactly like any other
tactic and needs no engine change. What's different:

- Type line: "Item", "Item: your unit", "Item: enemy lane" (instead of
  "Tactic: ...").
- Frame: the tactic frame in a leather-and-brass tint (`tools/gen_art.py`,
  `CardItem.tga`), so items stand out from spells.
- Binder Type filter: Unit / Tactic / Item / Trap. The deck panel's chart
  counts items with tactics.
- Healing Potion and Heavy Linen Bandage become items. Only their label
  changes.

Three kinds, as flavour only (the rules don't tell them apart):
- **Consumables** (potions, bombs, scrolls): do something once.
- **Gear** (weapons, armour, trinkets): permanently give one of your units
  stats and/or a keyword, as Shield Wall and Blessing of Might already do.
- **Gadgets** (engineering): summon a unit, as Call the Shoal already does,
  or do something clever once.

Items have no tribe, but a few work better with one. That gives the tribes
more hooks without new rules.

| Item | Cost | Rarity | Kind | Text (starting point) |
|---|---|---|---|---|
| Bloodsail Cutlass (W1) | 1 | common | gear | Give one of your units +3/+1. |
| Swiftness Potion (W1) | 1 | common | consumable | Give one of your units Swift and +1/+1. |
| Scroll of Protection (W1) | 1 | common | consumable | Give one of your units +1/+4. |
| Iron Grenade (W1) | 2 | common | consumable, enemy lane | Deal 2 damage to the enemy unit in a lane and freeze it. |
| Goblin Sapper Charge | 2 | common | consumable, enemy lane | Deal 2 damage to the enemy unit in a lane and 1 to the ones next to it. |
| Stratholme Holy Water | 2 | common | consumable, enemy lane | Deal 4 damage to the enemy unit in a lane if it's Undead or a Demon, otherwise 2. |
| Major Healing Potion (W1) | 2 | common | consumable | Restore 8 Morale. |
| Target Dummy | 2 | common | gadget | Summon a 0/4 Mechanical Target Dummy with Guard in an empty lane of yours. |
| Goblin Rocket Boots | 1 | uncommon | gear | Give one of your units Swift. |
| Gnomish Net-o-Matic Projector (W1) | 1 | uncommon | gadget, enemy lane | Freeze the enemy unit in a lane. Draw a card. |
| Arclight Spanner | 1 | uncommon | gear | Give one of your units +1/+1, or +2/+2 if it's Mechanical. |
| Mighty Troll's Blood Potion (W1) | 1 | uncommon | consumable | Give one of your units Regenerate and +1/+2. |
| Elixir of the Giants (W1) | 2 | uncommon | consumable | Give one of your units +3/+3. |
| Argent Dawn Commission | 2 | uncommon | gear | Give one of your units +1/+1 and Sturdy. |
| Lionheart Helm (W1) | 2 | rare | gear | Give one of your units +2/+2 and Rally. |
| Gnomish Battle Chicken | 3 | rare | gadget | Summon a 3/2 Mechanical Battle Chicken with Swift in an empty lane of yours. |
| Flask of the Titans | 3 | rare | consumable | Give one of your units +4 health. Restore 3 Morale. |
| Captain's Spyglass | 3 | rare | gadget | Draw 2 cards. |
| Ironfoe | 3 | epic | gear | Give one of your units +2/+2 and Pierce. |
| Thunderfury (W1) | 4 | legendary | gear | Give one of your units +2/+2, Swift and Cleave. |
| Corrupted Ashbringer | 5 | legendary | gear | Give one of your units +3 attack and Drain. |

That takes the item roster from 2 to 23. (W1): built in Wave 1, with the
numbers `balance cards` settled on; the rest are still first guesses.

---

## 4. Traps (decided 2026-11-23: the opponent sees the count, not the lane)

### 4.1 The rule, as the Guide and the keyword tip say it

> **Trap:** Set it in one of your empty lanes. Your opponent sees that you
> have a trap set, but not where. It springs when an enemy unit strikes into
> that lane: the strike is stopped, and the trap does what it says.

A trap isn't a unit with the Stealth keyword. Stealth units are on the board
and both players see them. A trap is off the board and hidden from the
opponent until it springs.

### 4.2 Edge cases

| Situation | What happens |
|---|---|
| An enemy unit already stands across the lane when you set the trap | It springs in this round's combat. This is how a trap answers a unit hitting your Morale. |
| Enemy unit has Ranged | It never springs a trap: Ranged shoots over it. |
| Enemy unit is Frozen, or has 0 attack | It doesn't strike, so the trap doesn't spring. |
| Pierce | The strike goes into the trap, so nothing carries on to Morale. |
| Drain | Restores nothing (the stopped strike did no damage). |
| Cleave | The main strike springs the trap. The cleave hits on neighbouring units still happen. |
| Guard beside the trapped lane | The trap comes first. Guard only covers lanes with nothing in them. |
| Attacker with Stealth | Loses Stealth, as with any strike. |
| Enemy tactic aimed at the lane | The lane counts as empty (Fireball hits Morale). The trap isn't touched. |
| Your own unit or summon into a trapped lane | Not allowed: a trap takes the lane, like a unit. Summons that look for empty lanes skip it. |
| A unit a trap brings in (Defias Ambush, Snake Trap) | Arrives at the end of combat, so it never strikes in the round it appears. |
| Several traps | Allowed, one per lane. If the balance runs show a problem, cap it at 2 set at once. |
| Game ends with traps unsprung | Revealed on the game-over screen. They don't count as units for the tiebreak. |
| Deck curve rule | A trap counts as a card of its cost (not as a unit). |

### 4.3 Engine (rules version 5)

- `P.traps[lane] = { uid, id }`, beside `P.board`. Keeping traps off
  `P.board` means `R.Units`, `R.Attack`, Rally, auras, Fireball's
  empty-lane check and the tiebreak need no change.
- `R.CheckPlan`: a trap needs a lane with no unit, no trap and no unit
  planned in it.
- `R.Resolve`: traps are set after the Arrive step and before tactics, in
  initiative order. Each one emits `{ t = "trap", p, lane, id }`.
- `strikesFor`: if a non-Ranged unit has no enemy unit across and that lane
  has a trap, the hit becomes `{ src = u, trap = { p, lane } }`. This is
  checked before `pickGuard`.
- `R.Combat`: the hit emits its strike (`via = "trap"`), then
  `R.Spring(st, p, lane, attacker)`. That removes the trap, puts it in the
  grave, emits `{ t = "spring", ... }` and runs `card.spring(st, p, lane,
  attacker)`. Units it summons wait until the end of combat (the same
  deferral `R.Cleanup` already uses).
- `R.Summon` and `R.EmptyLanes` treat your own trapped lane as taken.
- `R.SetTrap(st, p, lane, id)` lets a card set a trap.
- `R.Checksum` includes traps.
- `R.Redact(st, p)`: a clone with the other player's traps removed and only
  their count kept. Everything that shows or plans from one player's point of
  view uses it (4.4).
- For Freezing Trap only: `u.chill`, "frozen next round as well".
  `R.StartRound` turns it into `R.Freeze`. It goes into the checksum.

### 4.4 Hidden information: every place it could leak

| Place | Fix |
|---|---|
| Forecast (Morale change, "dies" marks) | `computeForecast` simulates on `R.Redact(st, ME)` |
| Lane markers and flow lights | built from the forecast, so fixed with it |
| Opponent slots, tooltips, `makeView` | traps aren't on `board`; the view carries only `trapCount` |
| Replay and log | the opponent's `trap` event shows "Dorn set a trap." with no lane or name; `spring` shows everything |
| AI planning | `simulate` runs on `R.Redact(st, aiSeat)`: the AI sees its own traps, not yours |
| PvP | both engines know every trap (they have to, for lockstep); only the UI hides them. Plans already carry the lane, and anti-cheat is out of scope by design |
| Saved match | holds the AI's traps; same reasoning |

Test it directly: the forecast, lane markers and AI choice must be the same
with and without an enemy trap on the board.

### 4.5 Board and UI

- Planning: pick the trap card, then one of your empty lanes, as you would a
  unit.
- Your trap shows in your slot as a face-down card with a small trap badge.
  Hovering it shows which trap it is. Your lane marker says "Trap waits
  here", and the forecast shows it springing if an enemy unit is across.
- The opponent's traps show as a marker beside their Morale: a face-down
  card icon with a count, and a tooltip ("Dorn has 1 trap set in an empty
  lane. It springs when one of your units strikes into that lane.").
- Spring: the strike arrow stops at the lane, the card snaps up and flips
  face-up, the effect plays, and the log says "Your Riverpaw Gnoll sprang
  Dorn's Immolation Trap."
- Game-over: unsprung traps are revealed.
- Card face: a "Trap" type line on its own frame (`CardTrap.tga`, dark green
  and iron, from `gen_art.py`).
- Guide: a Trap section with a diagram (`Diagram_trap.tga`), and a first-time
  tip when a trap first appears (the `seenKw` mechanism with key `trap`).

### 4.6 AI

- `AI.RandomPlan`, `AI.AllPlans` and `openingPlans` place traps like units:
  in a free lane that no planned unit uses.
- `AI.Evaluate` gives a set trap a value (about 0.8 x its cost), so setting
  one doesn't look like wasted Supply. The "you add nothing" simulation
  already rewards a trap in front of a unit that is hitting the AI's Morale.
- Made-up replies (`AI.SampleReply`) don't include traps at first. When the
  player has traps set, the heroic AI can treat their empty lanes as risky.
  That waits until the balance runs show it matters.

### 4.7 The trap cards

Traps have no tribe, but the units they bring in do. The Defias Ambusher is
Defias, so it counts for Defias synergy.

| Trap | Cost | Rarity | Springs: the strike is stopped, then |
|---|---|---|---|
| Snake Trap | 1 | common | a 1/1 Viper (Beast) with Venom appears in this lane |
| Immolation Trap | 2 | common | deal 3 damage to the attacker |
| Consecrated Ground | 2 | common | destroy the attacker if it's Undead or a Demon, otherwise deal 2 damage to it |
| **Defias Ambush** | 3 | uncommon | a 3/3 Defias Ambusher appears in this lane, and the attacker takes 3 damage |
| Freezing Trap | 2 | uncommon | the attacker is frozen next round as well |
| Shallow Grave | 2 | uncommon | two 1/1 Skeletons (Undead): one in this lane, one in an empty lane next to it |
| Explosive Trap | 3 | rare | deal 2 damage to the attacker and the enemy units next to it |
| Goblin Land Mine | 3 | rare | deal 4 damage to the attacker |

Defias Ambush is the headline ambush card. It's uncommon so people find it
early. Everyone also gets one Defias Ambush and one Immolation Trap the
first time they log in with traps, so they can try them right away (a
one-time grant flagged in `db.progress`, no schema change).

---

## 5. Collecting

### 5.1 Binder

As built in Wave 1 (simpler than the Tribes page first planned, which would
have been a new view nobody had seen in game):
- A separate **Tribe** filter. The tribes used to be mixed into the Type
  filter; Type is now Unit / Tactic / Item (Trap comes with Wave 2).
- Pointing at the Tribe filter lists every tribe's progress ("Murloc 9 / 17",
  in orange when complete) and says what completing one pays.
- With a tribe filtered, the header counts that tribe ("Murloc: collected 9
  of 17"), with an orange mark when it's complete.
- **Tribe completion:** owning one of every card in a tribe pays a Windfall
  pack (5.2).
- Cards with the same stat line sit next to each other when sorted by cost,
  which shows off the shared lines.

### 5.2 Packs (decided 2026-11-23)

**Regular packs don't change:** 3 cards, two commons and one uncommon or
better, from the same sources as today, and still 30 shards in the shop.

**Special packs** are new: 5 cards with a guaranteed rare or better ("3+" on
the rarity scale: common 1, uncommon 2, rare 3, epic 4, legendary 5). They
are earned, never bought.

| Slot | Card |
|---|---|
| 1-2 | common |
| 3 | uncommon |
| 4 | uncommon or better: the same roll as a regular pack's third card |
| 5 | **rare or better:** the regular odds with uncommon taken out (rare about 88%, epic about 10.5%, legendary about 1.75%) |

- Pity: a special pack counts like any pack. An epic or legendary in slot 4
  or 5 resets it.
- Holographic: the same 1-in-100 chance per pack, on any of the five cards.
- Signature cards stay out of the epic pool, as in regular packs.

**Where special packs come from:**

| Milestone | Today | With special packs |
|---|---|---|
| Every ~45 minutes of travel | (regular pack every 20 minutes) | **+1 special pack.** The 20-minute regular packs stay. |
| Finishing the tutorial | 1 pack | 1 special pack instead |
| All three stars on an opponent | (stars pay packs and the signature card) | +1 special pack (8 in all) |
| First heroic win against an opponent | 1 pack and the holo signature card | 1 special pack instead, and the holo signature card |
| Every star on the circuit | the champion card | +1 special pack |
| Every heroic rematch won | the holo champion card | +1 special pack |
| Every 10th level | 1 pack | 1 special pack instead |
| One of every card in a tribe | (new, 5.1) | 1 special pack (9 in all) |

That's about 34 milestone special packs, front-loaded into the first weeks
and months, plus the steady travel ones. The 45-minute clock counts the same
travel time as the 20-minute one: flights, boats and zeppelins (decision 5
in section 10).

Players who already passed a new milestone (all three stars, the circuit,
every heroic win, a whole tribe) get it at their first login with the update,
once. Milestones that only change their reward (tutorial, levels, first
heroic wins) aren't paid again.

**Pace.** I modelled it with a quick script that I didn't keep: 13 regular
packs a week (PLAN.md estimates 12-15), the real odds and pity, shards spent
on packs and then on crafting, median of 150 runs. 3.5 special packs a week
means about 2 hours of travel (2.7 packs) plus a milestone now and then.

| Pool | Special packs a week | One of 75% of cards | 2 of 75% | One of every card |
|---|---|---|---|---|
| Today, 97 cards | none | 4 weeks | 8 weeks | 23 weeks |
| After Wave 1, about 168 | none | 7 weeks | 13 weeks | 36 weeks |
| After Wave 1 | 3.5 | **5 weeks** | **8 weeks** | **20 weeks** |
| After Wave 3, about 252 | none | 11 weeks | 20 weeks | 60 weeks |
| After Wave 3 | 3.5 | 7 weeks | 12 weeks | 33 weeks |

The absolute numbers are rough. The comparison is the useful part: with
special packs, Wave 1 keeps today's pace even though the pool almost
doubles.

Built: the pace test in `tests/engine.lua` (section 8) now opens a Windfall
pack for every 4 card packs. With Wave 1's cards it takes a median of 48 card
packs to own three quarters of the pack cards (about 3.7 weeks at 13 a
week) and 119 for one of everything (about 9 weeks). Its bounds are 36-60
and 90-170.

**Code:**
- `db.specialPacks` (a count beside `db.packs`), `db.progress.specialTravel`
  (seconds toward the next one) and `db.progress.special = { [milestone] =
  true }`. New fields only, set by `C.Init`: no schema change. 0.16.0 keeps
  fields it doesn't know, so unopened special packs survive a downgrade.
- `C.RollPack(rnd, pity, kind)` and `C.OpenPack(db, rnd, kind)` with
  `kind = "special"`. `C.SPECIAL_SLOTS` describes the table above.
- `pay()` takes `{ special = n }`, and the reward lists say "+1 special
  pack". `C.AddTravel` returns both counts, and chat says "+1 special pack
  for 45 minutes of travel."
- `C.BuyPack` stays regular only.

**Pack screen (`UI/Packs.lua`):** two piles, the regular count and the
special count, with a gold-trimmed graphic for special packs (`gen_art.py`).
"Open a pack" opens a special pack first if you have one, and "Open all"
opens both kinds. A special pack lays out 5 cards at scale 1.1 (it fits the
784-unit page), and the guaranteed card flips last with a glow in its rarity
colour.

### 5.3 Crafting and shards

No change: craft any card at its rarity's price. Copies past 2 (1 for a
legendary) turn into shards.

---

## 6. Saves and safety

1. **Before any new card ships:** `C.Init` sets unknown card ids aside in
   `db.stash` instead of deleting them, and restores them once the card is
   known again. Use the same shape as the archived 0.17 code
   (`stash.collection[id] = n`, `stash.decks[slot] = list`,
   `stash.trades[tid] = deal`; see `git show a42ba11:Collection.lua`,
   around line 576), because a tester's save already has a `db.stash`
   from 0.17. This only protects players once a version with it is
   installed, so ship it on its own first.
2. **No schema change is needed.** Tribes are card data, new cards are new
   keys, special packs are new fields, and traps live in match state. If one
   is ever needed, **number it 9 or higher** (pad 8 with a no-op):
   a tester's save says schema 8.
3. Wave 1 changes no rules, so saved matches carry on. Wave 2 (traps) is
   rules version 5, which ends saved matches from version 4 on load, PvP
   games included. The changelog should say to finish games first.
4. Bring back `tests/saves.lua` from a42ba11 (adapted). It loads the real
   saves in `tests/saves/`, round-trips them, and checks the previous version
   loading the new save.
5. `N.CardSum` changes with every wave, so PvP and trading need the same
   version on both sides. That's already the rule. The 2-character card codes
   have room for 1,296 cards.

---

## 7. Waves

Each wave ends with every test suite passing, and is seen in game before the
next one starts.

**Phase 0: safety net and boat fix. Built 2026-11-23; ships in 0.17.0 with
Wave 1 (decided 2026-11-23: no separate 0.16.1).**
- **Stash (done):** `C.SetAside` (Collection.lua, run by `C.Init` at every
  login) sets unknown cards aside in `db.stash` with their holographic flag
  (`stash.holo`), whole decks (`stash.decks`, plus `stash.deckLeft`, the
  count left after trimming, so a deck changed meanwhile isn't overwritten)
  and pending deals (`stash.trades`), and brings them back when they're known
  again. Chat says so once when it happens. `tests/saves.lua` is back as its
  own suite (8 real saves, constructed ones, the set-aside store step by
  step, and the previous version exported from git); it fails against the
  old code.
- **Boats (done 2026-11-23, in the working tree, not yet seen in game):** the
  client closes open windows at the loading screen halfway across a boat or
  zeppelin trip, which ended games there. `Travel.lua` now reopens the window
  on the far side if it was open (`PLAYER_LEAVING_WORLD` /
  `PLAYER_ENTERING_WORLD`, `UI.HiddenAt`), and for `T.LOAD_GRACE` (15)
  seconds after a loading screen, standing still doesn't count as docking.
  `tests/ui.lua` covers both orders the client might close it in, and a
  window closed on purpose staying closed.

*Done when* a save with unknown ids survives a load/save round trip and gets
the cards back once they're known again, and a boat crossing keeps a game on
screen from dock to dock.

**Wave 1: tribes, items and special packs (0.17.0). Built 2026-11-23, not
yet seen in game.** 71 new cards in `Engine/CardsTribes.lua`; the special
packs are called **Windfall packs** in game.

Balance, measured after building it:
- `balance tribes` (6 random decks a tribe, 720 games each): Murloc 57.5%,
  Defias 56.5%, Beast 49.0%, Undead 48.2%, Humanoid 44.4%, Dragonkin 44.4%.
  Inside the target (no tribe much over 60%).
- `balance ladder`: identical, game for game, to the commit before Wave 1
  (the circuit's decks didn't change, and Humanoid changes no rules).
- `balance cards` on the 37 new cards with effects: the cheap gear items were
  well behind a plain unit (-8 to -12, as Blessing of Might once was) and
  were raised: Bloodsail Cutlass +3/+1 (was +3 attack), Scroll of Protection
  +1/+4 (was +4 health), Mighty Troll's Blood Potion Regenerate and +1/+2
  (was +1/+1), Lionheart Helm +2/+2 and Rally (was +2 health), Gnomish
  Net-o-Matic also draws a card, Major Healing Potion restores 8 (was 7).
  Murloc Raider 2/2, Plague Eater 2/4, Wyrmkin Firebrand 2/4 and Darkmaster
  Gandling 4/5 got a point each. After that every one of them measures
  between -6.4 and +1.0, where the older cheap tactics sit. High Tide
  (-15.8) is left alone: like Call of the Wild, it was tested in decks
  without its tribe. Murkdeep (+8.5) and Thunderfury (+6.8) sit where epics
  and legendaries usually do.

What the wave contains:
- Humanoid joins the five tribes, and the 24 Humanoids get it (2.1). The
  Guide's "Tribes" section lists all of them.
- Binder: Tribe filter, Type filter with Item and Trap, the Tribes page,
  tribe completion, and synergy highlighting on hover.
- Shared-line cards for Beast, Humanoid, Murloc, Undead, Defias and
  Dragonkin (34).
- Their other new cards (27; Defias's trap cards wait for Wave 2).
- Items: the label and frame, Potion and Bandage relabelled, and about 10
  new items.
- Special packs (5.2): the roll, the milestones and the travel clock, the
  first-login catch-up for veterans, the pack screen, and the pace re-tune.
- Translations (about 250 keys x 9 languages, split across parallel
  subagents as in 0.13), `balance tribes` and `balance ladder`.

*Done when* `balance tribes` shows no tribe far ahead of the rest (see 8),
the ladder win rates are where they are today, a special pack has been
earned and opened in game, and `/tradewinds icons` reports nothing missing.

**Wave 2: traps (0.18.0).** About 17 new cards.
- The engine (4.3), redaction (4.4), board and replay (4.5), the AI (4.6),
  the Guide section and tip. Rules version 5.
- The 8 traps, Defias's 3 trap cards, about 6 items, and the one-time trap
  gift.

*Done when* the engine tests cover every row of 4.2, the no-leak tests pass,
PvP mirrored clients agree on checksums with traps in play, the AI sets
traps in `balance ai` runs, and a real match with traps has been played in
game.

**Wave 3: Mechanical, Demon and Elemental (0.19.0).** About 67 new cards:
29 shared-line cards, 27 others, about 5 items and 6 spells. Watcher and
Shredder become Mechanical, Kazzak Demon, Ragnaros Elemental. Optionally one
new opponent per new tribe.

Leave a few weeks between waves, so each gets played and its feedback can
shape the next.

Version numbers: 0.17 and 0.18 were only used on the archived branch and
never published, so they're free to use. Pick 0.19+ instead if that's less
confusing.

---

## 8. Tests to add

- **engine.lua:** every row of the 4.2 table; trap setting and springing in
  replay events; `R.Redact` (counts kept, traps gone); trap summons arriving
  after combat; every collectible unit has a tribe (except listed tokens);
  shared-line cards really match their line (same cost, attack, health and
  keywords, no text); no shared line at rare or above; pack pools.
- **Special packs:** 5 cards, the fifth always rare or better, signature
  epics never rolled; pity resets on an epic in slot 4 or 5; each milestone
  pays once (including the login catch-up, which runs twice without paying
  twice); converted milestones don't pay twice for veterans; both travel
  clocks run side by side (45 minutes gives 2 regular packs and 1 special
  pack, with 5 minutes carried to the regular clock); `C.BuyPack` never gives
  one; a 0.16.0 round trip keeps `db.specialPacks`.
- **No-leak tests:** the forecast, lane markers and `AI.ChoosePlan` (same
  seed) give the same result with and without an enemy trap.
- **pvp.lua:** a trap set and sprung between two clients; plan encoding with
  a trap; checksums equal.
- **ui.lua:** your trap renders face-down with its tooltip; the opponent's
  slot stays empty and their trap marker shows the count; item and trap type
  lines; the Tribe filter and Tribes page; the pack screen with both piles
  and a 5-card reveal.
- **balance.lua:** a new `tribes` mode: a deck per tribe (its own units plus
  neutral tactics and items) plays the others round-robin with the normal
  AI. Target: no tribe wins much more than 60% on average. `cards` runs one
  card per shared line instead of all of them, and traps and items join the
  card runs.
- **saves.lua:** stash round trip; the previous version loading a save that
  has new cards and special packs.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Too many plain cards make packs dull | Shared-line cards are about half the new units and the rest have effects; each tribe keeps 2-3 cards with a style of its own; flavour and art differ |
| One tribe (Humanoid, the biggest) dominates | Its synergy cards ask for more or reach only neighbours; `balance tribes` checks it |
| Hidden traps leak through some UI path | The 4.4 table and its no-leak tests; the Wave 2 review looks for leaks only |
| Traps punish aggressive decks too much, or are ignored | `balance cards` and ladder runs; the count marker gives fair warning; cap at 2 if needed |
| Collection pace slows as the pool grows 2.5x | Special packs; shared lines make decks easier to fill; the pace test |
| Special packs make regular packs feel worthless | Regular packs stay the main source (13 a week against about 3.5); specials are a treat on milestones and long trips |
| Going back to 0.16.0 deletes new cards | Phase 0 first. Release notes: don't go back past 0.17.0 |
| Translation volume (about 550 keys) | Spread over three waves; shared-line cards need only name and flavour; parallel subagents with full key context |
| Icons missing in the client | Two icon candidates per card; `/tradewinds icons` before release |
| Scope creep (the reason the collection expansion was reverted) | This plan covers tribes, items, traps and special packs only; anything else gets its own plan |

---

## 10. Decisions

**Made 2026-11-23**
1. Tribes are groups of different creatures, and every unit belongs to one.
   Cards in different tribes may share a stat line. No reprints. The word
   players see stays "tribe".
2. Items are a labelled family of tactics (consumables, gear, gadgets), not a
   new card type.
3. A set trap shows the opponent a count, not its lane.
4. Regular packs stay at 3 cards. Special packs have 5 cards with a
   guaranteed rare or better, and come only from milestones and every ~45
   minutes of travel.
5. The 45-minute clock counts flights, boats and zeppelins, like the
   20-minute one. Boat games no longer end at the loading screen (Phase 0).
6. Phase 0 ships inside 0.17.0, not as a 0.16.1 of its own.
7. Withdrawn: "the copy limit is shared across prints". There are no prints.
   Cards with the same stats are different cards with their own limits.

**Open (my recommendation first)**
1. The special pack's name in game: **"Windfall pack"** (it fits
   Tradewinds) / "special pack" / another name.
2. The milestone list in 5.2: **as listed** / add or drop some.
3. Veterans get the new milestones they already passed, at first login:
   **yes** / no.
4. Trap limit: **none, unless balance says otherwise** / at most 2 set at
   once.
5. A free Defias Ambush and Immolation Trap when traps arrive: **yes** / no.
6. A new opponent for each Wave 3 tribe: **yes** / none.
