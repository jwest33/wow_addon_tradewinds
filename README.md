# Deckhand

A Warcraft-flavoured card game for WoW Forever, made for flights and boat
rides. Collect cards from packs you earn by travelling and playing, build a
20-card deck, take on the regulars of the tavern circuit, and challenge your
friends.

`/deckhand` opens it. The first time, Flightmaster Dorn offers a short guided
match (the **tutorial**, also `/deckhand tutorial`): four rounds where he tells
you what to play and why, then you finish the match yourself. Finishing it
earns a card pack.

Games are saved after every round, so you can stop when you
land or dock and pick it up on the next trip. An update that changes the rules or
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
| Pierce | Damage beyond the struck unit's health carries on to the enemy's Morale (a Sturdy unit that survives the hit still lets it through) |
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

You start with a 20-card starter deck and 1 pack, plus 1 for finishing the
tutorial.

- **Packs** hold 3 cards: two commons and an uncommon. The uncommon is
  upgraded to a rare 25% of the time, an epic 3% and a **legendary 0.5%** (1
  pack in 200). If 24 packs in a row had no epic or legendary, the next one
  has an epic.
- **Holographic cards**: about 1 pack in 100 has a holographic card, with a
  shimmering foil over its art and a prismatic border. It plays exactly like
  the normal card. Once you own a holographic copy, every copy of that card
  you play or browse shows holographic. A holographic pull of a card you
  already have every copy of makes yours holographic instead of turning into
  shards.
- **Shards** buy packs (30) or **craft** a card you choose: shift-click it in
  the Cards tab. Common 10, uncommon 25, rare 60, epic 150, legendary 400. A
  copy past the deck limit turns into shards (1 / 3 / 10 / 25).
- **Signature cards** are won from opponents: each opponent has one, won with
  their second star, and Ragnaros is the reward for every star on the
  circuit. All of them can also be crafted, for 400. The epic ones are never
  in packs; the legendary ones turn up very rarely, like any legendary.

Where packs and shards come from:

| | |
|---|---|
| First win of the day | 1 pack |
| Every 20 minutes travelling (flight path, boat or zeppelin) | 1 pack |
| Every tenth level | 1 pack |
| A win | 2, 4 or 6 shards by the opponent's level, 8 in a heroic rematch. The first 3 wins a day against each opponent pay in full, later ones 1 |
| The first heroic win against each opponent | 1 pack, and their signature card, holographic |
| A loss or draw that reached round 4 | 1 shard |
| The daily task | 10 shards |
| A level, a new flight path | 5 shards each |

Ending a match early pays nothing.

The numbers are set for a pace of about three quarters of the pack cards in
three weeks of casual play and one of everything in two to three months
(legendaries aside: they're a jackpot). A test simulates that and fails if a
change moves it.

### Opponents and stars

The circuit is a ladder: beating an opponent opens the next one.

| | Level | Deck | Signature card |
|---|---|---|---|
| Flightmaster Dorn | easy | beasts | King Bangalash |
| Old Bluegill | easy | murlocs | Old Murk-Eye |
| Sally Mudwhistle | normal | Booty Bay crew, removal | Fleet Master Seahorn |
| Innkeeper Grumbletusk | normal | Horde tavern, Rally | Hogger |
| Lil Fingers | normal | Defias, stealth and tricks | Edwin VanCleef |
| Archmage Pellwick | hard | spells and ranged | Azuregos |
| Sexton Graves | hard | undead that come back | Baron Rivendare |
| Lady Katrana Prestor | hard | the boss: guards, venom | Onyxia |

Each opponent has three stars:

1. **Victory**: win. Pays a pack and opens the next opponent.
2. **Decisive**: win with at least 6 more Morale than them. Pays their
   signature card.
3. **Rank and file**: win with a deck that has no rare, epic or legendary
   cards. Pays 2 packs.

There is also one **daily task** (shown under the opponent list), such as
"Destroy 10 enemy units" or "Play 6 Beasts".

### Heroic rematches

Beat Lady Prestor and a **Heroic rematches** button appears on the opponent
list: all eight again, each with a stronger deck built around their tribe and
signature card, played by the strongest computer level. Heroic games keep their
own record and earn no stars. A heroic win pays 8 shards; the first one
against each opponent also pays a pack and a **holographic** copy of their
signature card (or makes yours holographic). Win all eight and Ragnaros turns
holographic too.

### Playing other players

Challenge a friend or guildmate who has Deckhand: **Challenge a player** under
the opponent list (target them first and their name is filled in), or
`/deckhand challenge Name`. They get a popup to accept or decline. You both
need the same version of Deckhand.

- You each play your own deck, and rounds work as usual: plan, lock in, and
  the round plays out once both of you have locked in. There's no time limit:
  lock in, close the window, and come back whenever. "Bob has locked in"
  shows when they're waiting for you; while you wait for them, your plan
  stays on the board. If you're elsewhere when they lock in, a prompt says
  so.
- **Several games at once.** You can have a game going with up to 8 players
  (one each), beside your match against the computer. **Your games** on the
  Play tab lists them all with where each stands ("Your move", "Waiting for
  Bob", "A new round to watch"), and **All games** on the board takes you
  back to it without ending anything. A round plays out as soon as both
  plans are in, even if that game isn't on screen; you watch it when you
  next open the game.
- Plans travel as whispers, so they only arrive while you're both online
  (not necessarily at the same time as you play: a plan waits on your side
  until it gets through). Games are saved like any other. If either of you
  reloads or logs out, they carry on when you're both back: an unanswered plan is sent again after
  5, 15 and 45 seconds, then every 2 minutes, until the other side has it. A
  round that played out while your window was closed is shown when you open
  it.
- Ending the match concedes it: a loss for you, a win for them.
- A win pays like a normal opponent's (4 shards, the first win of the day,
  the daily task) once the game reached round 4. Results are kept per player
  ("Against players" under the opponent list).
- Both clients play the same game from the same seed and send only their
  plans. After every round they compare a checksum of the game; if the two
  ever disagree, the match ends without a result (please report that).

It's meant for friends: plans travel in the open, so it isn't cheat-proof.
Whispers only reach players you could whisper anyway (same faction, same or
connected realm).

### The computer

It plays honestly. Each round it lists the plans it could play, plays each
one out on a copy of the game and scores the board after combat. It never
sees your hand or your plan. The levels differ in how hard they look:

- **Easy** tries a handful of plans and picks loosely among the decent ones.
- **Normal** tries about 60 and assumes you add nothing new.
- **Hard** also tests every plan against a couple of made-up replies:
  plays you could make with your Supply and the number of cards you hold,
  drawn from ordinary cards (it can't see yours).
- **Heroic** lists every legal plan (when there are at most 300) and tests
  each against six made-up replies.

Each opponent also has a style: Sally and Fingers go for your Morale,
Bluegill, Graves and Pellwick care most about the board, and so on. Every
opponent opens round 1 with a 1-cost unit, and none of them plays a card it
rates worse than doing nothing (a Healing Potion at full Morale, say), however
loosely the easy ones play.

## The window

- **Play**: the opponent list with stars and the daily task, then the board.
  Cards show their keywords and a short line of rules text; hover one for the
  full wording. Click
  a card and then a lane, or drag it onto the lane. **Replay** shows the last
  round again. The log under your hand is saved with the match. If you reload
  or log out while a round is playing out, it is shown when you come back.
- **Cards**: every card with filters (owned, rarity, cost, type or tribe),
  three deck slots, the curve checklist and a chart of your deck's costs.
  Shift-click a card to craft it.
- **Packs**: open one pack card by card, or all of them at once.
- **Guide**: every rule, a round step by step, and each keyword with a
  diagram. The tutorial can be started from here too.
- **Options**: sound, portraits, the forecast, opponent lines, the travel
  prompt, closing when you arrive or in combat, the minimap button, replay
  speed and window size.

The first time a keyword turns up in a match (in your hand or on the board),
a box explains it with its diagram. Opponents say a line now and then: when
a match starts, after a big hit either way, and when they're close to losing.
Click the bubble to dismiss it; the Opponent lines option turns them off.

## Commands

- `/deckhand`: show or hide (`/deckhand play | cards | packs | guide | options`
  opens a tab). There's also a minimap button and a key binding.
- `/deckhand tutorial`: the guided match against Dorn. It doesn't use your
  deck and doesn't count on the circuit.
- `/deckhand challenge [name]`: challenge another player (no name: your
  target).
- `/deckhand end`: end the match you're in (the same as the **End match**
  button; it asks first, counts as a loss and earns nothing). You never
  *have* to end a match: it's saved after every round.
- `/deckhand rules`: opens the Guide
- `/deckhand icons`: card icons this client doesn't have (for bug reports)
- `/deckhand travel`: what Deckhand sees of your travel right now.
  `/deckhand travel log` prints a line a second (to check boat detection on
  a real crossing); run it again to stop.
- Everything in the Options tab also has a command: `/deckhand help` lists
  them.

## How it's built

- `Engine/Rules.lua`: the rules, pure Lua with no WoW calls and a seeded
  random number generator, so the same seed and plans always give the same
  game. That's what lets the computer simulate, and what player against
  player uses: both clients run the same game and only send plans. Each side
  plays as its own player 1, so the two copies are mirror images; the few
  steps whose order matters (shuffling, drawing, who goes first) run in
  "seat" order (`R.Seats`), which keeps them identical. `R.Checksum` is the
  fingerprint the two compare after every round.
- `Net.lua`: player against player over addon whispers (challenge, decks,
  plans, checksums, concede, resends). The message format is at the top.
- `Engine/Cards.lua`, `Engine/CardsRoads.lua`: the two card sets.
  `Engine/AI.lua`: the computer opponent.
- `Data/Opponents.lua`, `Collection.lua`: opponents; collection, deck, packs,
  crafting, stars, daily tasks and rewards (saved per character in
  `DeckhandCharDB`, with numbered migrations).
- `Art/`: textures, generated by `tools/gen_art.py`, including the rules
  diagrams (`Diagram_*.tga`).
- `UI/`: the window (`Main`), board (`Game`), binder and decks (`Binder`),
  pack opening (`Packs`), options (`Options`), the card frame, tooltips and
  sounds (`Widgets`), creature portraits (`Portraits`).
- `Data/CardText.lua`: the short rules text printed on each card.
- `Data/Tutorial.lua`: the tutorial's script (stacked decks, what each side
  plays in the guided rounds, the coach's text). `UI/Tutorial.lua` draws the
  coach; `UI/Guide.lua` is the Guide tab. A test plays the script and checks
  that every round does what the coach says.
- `Travel.lua`: flights, boats and zeppelins. On this client `UnitOnTaxi`
  has been seen to stay true after landing, so landing is also detected from
  speed. There is no call that says you're on a boat, so a ride is recognised
  from movement: you stand still while your map position keeps moving
  sideways at boat speed for 6 seconds. It ends after 10 seconds without
  moving (docked) or 30 seconds of running (you walked off). Loading screens
  between continents are skipped over. This has not been checked on a real
  boat yet.
- Creature portraits are still images. The client turns a creature id into a
  display id through a *hidden* model, and the result is saved. No 3D model is
  ever shown, because shown models have hung this client's GPU before.

## Tests

```
pip install lupa
python tests/run_tests.py          # engine, ui and pvp
```

`tests/engine.lua` checks every keyword and card effect, determinism, the copy
limits, pack odds, rewards, stars, crafting, save migrations and the pace of
the collection, and plays a few hundred AI-vs-AI games (to check for errors,
game length and balance). `tests/ui.lua` loads the whole
addon against a strict WoW API mock, where an unknown widget method is an
error. It plays games through the same functions the buttons call, then
opens packs, edits the deck and takes a mock flight and a mock boat ride.

`tests/pvp.lua` runs two complete clients (each with its own mock, saved
data and copy of the addon) joined by a pretend network. It plays whole
matches between them, loses a message, reloads one client mid-match, takes
one offline for a few minutes, concedes, and corrupts one copy to check the
mismatch is caught. `tests/engine.lua` also plays 30 games as both mirrored
copies and checks they never differ.

`tests/balance.lua` is the balance harness, run on demand (minutes, not
seconds):

```
python tests/run_tests.py balance ai [games]       # the AI levels against each other
python tests/run_tests.py balance ladder [games]   # the circuit with the starter deck, and the heroic rematches
python tests/run_tests.py balance cards [n] [ids]  # each card's effect on winning
```

`cards` plays every card in nine decks (the starter and each opponent's)
against the opponents, then the same games with a plain unit of the same cost
in its place, and reports the difference in win rate.

## Next

See `PLAN.md`.
