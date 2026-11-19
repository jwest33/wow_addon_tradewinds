# Deckhand

A Warcraft-flavoured card game for WoW Forever, made for flights and boat
rides. Collect cards from packs you earn by travelling and playing, build a
20-card deck, and take on the regulars of the tavern circuit.

`/deckhand` opens it. Games are saved after every round, so you can stop when you
land and pick it up on the next flight. An update that changes the rules or
cards ends a match in progress; that match doesn't count as a win or a loss.
Other updates leave it alone.

## The game

- Both players start with **12 Morale**. A game lasts **at most 8 rounds**.
- Each round you draw a card and get **Supply** to spend: 1 in round 1, 2 in
  round 2 ... up to 6. The opening hand (4 cards) and draws from round 4 on are
  random, but the draws in rounds 1-3 are **guided**: round 1's is a unit
  costing 1, round 2's costs 2 or less, round 3's 3 or less (each picked at
  random among the cards left that qualify). So you always have something to
  play early.
- **Plan** your round: click a card, then click where it goes. Units go into
  your four lanes (bottom row); tactics target a lane. Right-click a planned
  card to take it back. Then **Lock In**.
- Both sides are **revealed at once**: new units arrive (Arrive effects), then
  tactics resolve (the player with initiative first; it alternates), then
  **combat**. Every unit strikes the enemy unit across from it, or the enemy's
  Morale if that lane is empty. Swift units strike first.
- The game ends when someone's Morale hits 0, or after round 8: higher Morale
  wins. If it's tied, the player with more units on the board wins.

Because tactics land *after* the reveal, an enemy-lane tactic hits whatever is
there by then, including a unit your opponent just played. Guessing where
they'll play is half the game.

Each lane is drawn as a column joining the enemy slot and yours. While you
plan, a **marker** between the rows shows what each lane will do in combat:

- a green up arrow with a number: your unit hits their Morale
- a red down arrow: their unit hits yours, so block it
- crossed swords: the two units fight (or a Guard or Ranged unit gets involved)

Hover a marker for the details in words. The Morale panels show the predicted
change beside the number, and units that would die are marked "dies". All of
this assumes the opponent plays nothing new; it's the same what-if the
computer runs for its own plans. During combat the markers light up lane by
lane as the strikes land. `/deckhand forecast off` hides the predictions.

### Keywords

| Keyword | Effect |
|---|---|
| Swift | Strikes before other units; a unit it kills doesn't strike back |
| Guard | Unblocked enemies in neighbouring lanes strike it instead of your Morale |
| Ranged | Strikes the weakest enemy unit anywhere (Morale if there are none) |
| Pierce | Damage beyond the kill carries on to the enemy's Morale |
| Cleave | Also strikes the enemy units in the neighbouring lanes |
| Venom | Destroys any unit it damages |
| Drain | Damage it deals restores your Morale |
| Sturdy | Survives the first death with 1 health |
| Regenerate | Heals to full at the end of each round |
| Rally | Your neighbouring units get +1 attack |
| Stealth | Enemy tactics can't target it until it has struck |

### Cards

97 cards in two sets. The core set has 48. **Roads of Azeroth** adds 49, built
around five tribes: Beasts, Murlocs, Undead, Defias and Dragonkin. Tribe cards
reward being played together ("Your other Beasts have +1 attack", "+1 attack
for each other Murloc you have"). A card's tribe is in its tooltip.

A deck is exactly 20 cards, with up to 2 copies of a card (1 of a legendary),
and it needs a **curve**: at least 2 units costing 1, 4 cards costing 2 and
3 cards costing 3, which is what the guided draws pick from. The Cards tab
shows the curve as a checklist.

### Getting cards

You start with a 20-card starter deck and 2 packs.

- **Packs** hold 3 cards: two commons and an uncommon, which is a rare 26% and
  an epic 5% of the time (and always an epic if 14 packs in a row had none).
- **Shards** buy packs (30) or **craft** a card you choose: shift-click it in
  the Cards tab. Common 10, uncommon 25, rare 60, epic 150, legendary 400. A
  copy past the deck limit turns into shards (1 / 3 / 10 / 25).
- **Legendaries and signature cards are not in packs.** Each opponent has a
  signature card, won with their second star. Ragnaros is the reward for
  every star on the circuit. All of them can also be crafted, for 400.

Where packs and shards come from:

| | |
|---|---|
| First win of the day | 1 pack |
| Every 20 minutes on a flight path | 1 pack |
| Every tenth level | 1 pack |
| A win | 2, 4 or 6 shards by the opponent's level. The first 3 wins a day against each opponent pay in full, later ones 1 |
| A loss or draw that reached round 4 | 1 shard |
| The daily task | 10 shards |
| A level, a new flight path | 5 shards each |

Ending a match early pays nothing.

The numbers are set for a pace of about three quarters of the pack cards in
three weeks of casual play and one of everything in two to three months. A
test simulates that and fails if a change moves it.

### Opponents and stars

The circuit is a ladder: beating an opponent opens the next one.

| | Level | Deck | Signature card |
|---|---|---|---|
| Flightmaster Dorn | easy | beasts | King Bangalash |
| Old Bluegill | easy | murlocs | Old Murk-Eye |
| Sally Mudwhistle | normal | Booty Bay crew, removal | Fleet Master Seahorn |
| Innkeeper Grumbletusk | normal | Horde tavern, Rally | Hogger |
| Lil Fingers | normal | Defias, stealth and tricks | Edwin VanCleef |
| Sexton Graves | hard | undead that come back | Baron Rivendare |
| Archmage Pellwick | hard | spells and ranged | Azuregos |
| Lady Katrana Prestor | hard | the boss: guards, venom | Onyxia |

Each opponent has three stars:

1. **Victory**: win. Pays a pack and opens the next opponent.
2. **Decisive**: win with at least 6 more Morale than them. Pays their
   signature card.
3. **Rank and file**: win with a deck that has no rare, epic or legendary
   cards. Pays 2 packs.

There is also one **daily task** (shown under the opponent list), such as
"Destroy 10 enemy units" or "Play 6 Beasts".

The computer plays honestly: it builds random legal plans, plays each one out
on a copy of the game where you do nothing new, scores the board and keeps the
best. It never sees your hand or your plan. Harder opponents try more plans
and also check each one against you blocking their best attacker.

## Commands

- `/deckhand`: show or hide (`/deckhand play | cards | packs` opens a tab). There's also
  a minimap button and a key binding.
- `/deckhand end`: end the match you're in (the same as the **End match**
  button; it asks first, counts as a loss and earns nothing). You never *have* to end a
  match: it's saved after every round.
- `/deckhand rules`: how to play, in chat
- `/deckhand speed 1-3`: how fast rounds play out (click the board to skip a round)
- `/deckhand scale 0.6-1.5`, `/deckhand reset`: window size and position
- `/deckhand toast | land | combat | portraits | forecast | minimap [on|off]`:
  offer a game at take-off, close the window on landing / in combat, creature
  portraits in tooltips, the round forecast, the minimap button
- `/deckhand icons`: card icons this client doesn't have (for bug reports)

## How it's built

- `Engine/Rules.lua`: the rules, pure Lua with no WoW calls and a seeded
  random number generator, so the same seed and plans always give the same
  game. That's what lets the computer simulate, and what player-vs-player will
  use later (both clients run the same game and only send plans).
- `Engine/Cards.lua`, `Engine/CardsRoads.lua`: the two card sets.
  `Engine/AI.lua`: the computer opponent.
- `Data/Opponents.lua`, `Collection.lua`: opponents; collection, deck, packs,
  crafting, stars, daily tasks and rewards (saved per character in
  `DeckhandCharDB`, with numbered migrations).
- `Art/`: textures, generated by `tools/gen_art.py`.
- `UI/`: the window (`Main`), board (`Game`), binder and deck (`Binder`),
  pack opening (`Packs`), shared widgets and tooltips (`Widgets`), creature
  portraits (`Portraits`).
- `Travel.lua`: flight detection. On this client `UnitOnTaxi` has been seen
  to stay true after landing, so landing is also detected from speed.
- Creature portraits are still images. The client turns a creature id into a
  display id through a *hidden* model, and the result is saved. No 3D model is
  ever shown, because shown models have hung this client's GPU before.

## Tests

```
pip install lupa
python tests/run_tests.py
```

`tests/engine.lua` checks every keyword and card effect, determinism, the copy
limits, pack odds, rewards, stars, crafting, save migrations and the pace of
the collection, and plays a few hundred AI-vs-AI games (to check for errors,
game length and balance). `tests/ui.lua` loads the whole
addon against a strict WoW API mock, where an unknown widget method is an
error. It plays games through the same functions the buttons call, then
opens packs, edits the deck and takes a mock flight.

## Next

See `PLAN.md`.
