# Tradewinds

A Warcraft-flavoured card game for WoW Forever, made for flights and boat
rides. Collect cards from packs you earn by travelling and playing, build a
20-card deck, take on the regulars of the tavern circuit, and challenge your
friends.

`/tradewinds` opens it. The first time, Flightmaster Dorn offers a short guided
match (the **tutorial**, also `/tradewinds tutorial`): four rounds where he tells
you what to play and why, then you finish the match yourself. Finishing it
earns a Windfall pack.

Games are saved after every round, so you can stop when you
land or dock and pick it up on the next trip. An update that changes the rules or
cards ends a match in progress; that match doesn't count as a win or a loss.
Other updates leave it alone.

## Install

Get Tradewinds from CurseForge, or download `Tradewinds-<version>.zip` from
the [Releases page](https://github.com/jwest33/wow_addon_tradewinds/releases)
and unzip it into `World of Warcraft\_forever_\Interface\AddOns`, so that you
end up with `AddOns\Tradewinds\Tradewinds.toc`. Then restart the game: a
`/reload` doesn't pick up a new addon.

GitHub's **Code → Download ZIP** button gives you the source, not the addon:
its folder is called `wow_addon_tradewinds-main` and holds the tests and
tools, and the game won't load it. Use a release zip, or build one with
`python tools/package.py` (see [Release](#release)).

## The game

- Both players start with **12 Morale**. A game lasts **at most 8 rounds**.
- Each round you draw a card and get **Supply** to spend: 1 in round 1, 2 in
  round 2 ... up to 6. The opening hand (4 cards) and draws from round 4 on are
  random, but the draws in rounds 1-3 are **guided**: round 1's is a unit
  costing 1, round 2's costs 2 or less, round 3's 3 or less (each picked at
  random among the cards left that qualify). So you always have something to
  play early.
- **Plan** your round: click a card, then click where it goes. Units go into
  your four lanes (bottom row), and so do traps, face down; tactics target a
  lane. Right-click a planned card to take it back. Then **Lock In**.
- Both sides are **revealed at once**: new units arrive and traps are set,
  then Arrive effects happen, then tactics resolve (the player with
  initiative first; it alternates), then **combat**. Every unit strikes the
  enemy unit across from it, or the enemy's Morale if that lane is empty (or
  springs the trap waiting there). Swift units strike first.
- The game ends when someone's Morale hits 0, or after round 8: higher Morale
  wins. If it's tied, the player with more units on the board wins.

Because tactics land *after* the reveal, an enemy-lane tactic hits whatever is
there by then, including a unit your opponent just played. Guessing where
they'll play is half the game.

Each lane is drawn as a column joining the enemy slot and yours. While you
plan, a **marker** between the rows shows what each lane will do in combat,
and small lights flow along the lane the way the damage goes (green up into
their empty slot, red down into yours, gold in from both sides to a clash
when two units fight):

- a green up arrow with a number: your unit hits their Morale
- a red down arrow: their unit hits yours, so block it
- crossed swords: the two units fight (or a Guard or Ranged unit gets involved)
- a snare: their unit strikes into your trap, which springs (dim when your
  trap is just waiting there)

When both sides have locked in, a quick **3, 2, 1, Reveal!** counts down,
then the round plays out and you see each strike in turn: a glowing bolt flies
from the attacker to what it hits (gold for yours, red for theirs), the
target shakes and the damage pops up over it, and keywords call themselves
out as they work ("Guard" when a unit steps in, "Pierce" when damage goes
through, "Venom", "Drain", "Sturdy!", "Regenerate" when a unit heals at the
end of the round). When something finds nothing to hit, the board says that
too: "No target" for a Fallen effect whose target died at the same time,
"Stealth" for a tactic that can't target the unit it was aimed at. A trap
that springs turns face up where it waited ("Trap!") before it does what it
says. Strikes in
a step still all happen at once, which is why units only fall after the whole
volley; units that die together also have their Fallen effects together, and
a unit one of them summons arrives after all of them. Click the board
to skip to the end of a round. The round counter shows how many rounds are
left, and the last one is announced as the final round.

Hover a marker for the details in words. The Morale panels show the predicted
change beside the number, and units that would die are marked "dies". All of
this assumes the opponent plays nothing new; it's the same what-if the
computer runs for its own plans. During combat the markers light up lane by
lane as the strikes land. `/tradewinds forecast off` hides the predictions.

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

185 cards. The core set has 48, **Roads of Azeroth** 49, **Tribes of
Azeroth** 71, and **Traps and Trickery** 17 (8 traps, 3 Defias who work with
them, and 6 items).

- **Tribes**: every unit belongs to one: Beasts, Humanoids, Murlocs, Undead,
  Defias or Dragonkin (Harvest Watcher, the Shredder, Kazzak and Ragnaros wait
  for tribes of their own in a later update). Tribe cards reward being played
  together ("Your other Beasts have +1 attack", "+1 attack for each other
  Murloc you have"). A card's tribe is on its type line. Point at a card that
  counts a tribe and the units it counts light up.
- **The same stats in different tribes**: 34 of the new cards are plain units
  with exactly the stats and keywords of a plain unit of another tribe (a 3/4
  for 3 is an Orgrimmar Grunt, an Ashenvale Bear, a Murloc Tidewarrior...). On
  their own they play the same; their tribe decides which cards count them.
- **Items**: potions, bombs and gear. They are tactics and play exactly like
  them, with a leather frame and "Item" on the type line. Gear stays on the
  unit, like Shield Wall. Healing Potion and Heavy Linen Bandage are items
  now too.
- **Traps**: a card type of their own, with a green frame (see below).

### Traps

You set a trap face down in one of your empty lanes, as you would play a unit
there. Your opponent sees how many traps you have set (a count by your Morale)
but not which ones or where. A trap springs when an enemy unit strikes into
its lane: the strike stops there and never reaches your Morale, the trap
turns face up and does what it says (3 damage to the attacker, a Viper with
Venom in the lane, the attacker frozen next round as well, and so on), and
then it goes to the grave.

- Set one across from a unit that's hitting your Morale and it springs that
  round.
- Ranged units shoot over traps; a frozen unit, or one with no attack,
  doesn't strike, so it springs nothing.
- Pierce doesn't carry on past a trap and Drain gets nothing from it; Cleave
  still hits the units beside it. A trap comes before a Guard next door.
- Tactics treat a trapped lane as empty (Fireball hits Morale, the trap stays).
- Your units can't go in a lane with your trap, and summoned units skip it.
  That can give a trap away: a Hogger played beside it leaves that one empty
  lane empty, for anyone watching. A unit a trap brings in arrives after
  combat, so it doesn't strike that round.
- Traps aren't units: they don't count for the tiebreak. Any still face down
  when the game ends are shown on the end screen.
- There's no limit on how many you set, one per lane.

Neither the forecast nor the computer can see where your opponent's traps are:
both work from a copy of the game with the other side's traps taken out and
only their count kept (`R.Redact`), and a test checks the computer plans
exactly the same with or without your trap on the board. Lil Fingers has a
Defias Ambush in her deck now. Everyone got a Defias Ambush and an
Immolation Trap with 0.18.0, to try them.

A deck is exactly 20 cards, with up to 2 copies of a card (1 of a legendary),
and it needs a **curve**: at least 2 units costing 1, 4 cards costing 2 and
3 cards costing 3, which is what the guided draws pick from. The Cards tab
shows the curve as a checklist.

### Getting cards

You start with a 20-card starter deck and 1 pack, plus a Windfall pack for
finishing the tutorial.

- **Packs** hold 3 cards: two commons and an uncommon. The uncommon is
  upgraded to a rare 25% of the time, an epic 3% and a **legendary 0.5%** (1
  pack in 200). If 24 packs in a row had no epic or legendary, the next one
  has an epic.
- **Windfall packs** hold 5 cards: two commons, an uncommon, a card rolled
  like a pack's third, and a last one that is always **rare or better** (88%
  rare, 10.5% epic, 1.75% legendary). They are earned, never bought: every 45
  minutes of travel, and for milestones (below).
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
| Every 45 minutes travelling (on a clock of its own) | 1 Windfall pack |
| Finishing the tutorial, every tenth level | 1 Windfall pack |
| All three stars against an opponent; every star on the circuit | 1 Windfall pack each |
| One of every card of a tribe (the Tribe filter's tooltip shows how close you are) | 1 Windfall pack each |
| A win | 2, 4 or 6 shards by the opponent's level, 8 in a heroic rematch. The first 3 wins a day against each opponent pay in full, later ones 1 |
| The first heroic win against each opponent | 1 Windfall pack, and their signature card, holographic |
| Every heroic rematch won | 1 Windfall pack, and the champion's card, holographic |
| A loss or draw that reached round 4 | 1 shard |
| The daily task | 10 shards |
| A level, a new flight path | 5 shards each |

Ending a match early pays nothing. A milestone reached before it paid (in an
older version, or through a trade) pays at the next login.

The numbers are set for a pace of about three quarters of the pack cards in
three to four weeks of casual play and one of everything in two to three
months (legendaries aside: they're a jackpot). A test simulates that and
fails if a change moves it.

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

Challenge a friend or guildmate who has Tradewinds: **Challenge a player** under
the opponent list (target them first and their name is filled in), or
`/tradewinds challenge Name`. They get a popup to accept or decline. You both
need the same version of Tradewinds.

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
- **Rematch** on the end screen sends the same player a new challenge.
- A win pays like a normal opponent's (4 shards, the first win of the day,
  the daily task) once the game reached round 4. Results are kept per player
  ("Against players" under the opponent list).
- Both clients play the same game from the same seed and send only their
  plans. After every round they compare a checksum of the game; if the two
  ever disagree, the match ends without a result (please report that). The
  last round's checksums cross after the game has ended on both sides, so a
  difference there can't undo the result any more, but it's still reported
  in chat.

It's meant for friends: plans travel in the open, so it isn't cheat-proof.
Whispers only reach players you could whisper anyway (same faction, same or
connected realm).

### Trading cards

Trade cards with a friend who has Tradewinds: **Trade** under the deck in the
Cards tab (target them first and their name is filled in), or
`/tradewinds trade Name`. They get a popup to accept or decline.

- While the trade is open, the deck panel shows it instead: what you give,
  what they give, and who has accepted. Click your cards in the binder to
  offer them (up to 8 a side); right-click takes one back. One side can put
  up nothing, to give a gift.
- What you'd get is marked: **New** for a card you don't have, **+N shards**
  for a copy past your limit (it turns into shards, as in a pack), **Holo**
  when it would make your copy holographic.
- A click offers a plain copy. Your holographic copy only goes if you
  shift-click it, or when it's the last copy you have left to offer.
- The trade happens once you've both accepted. Any change to either offer
  takes both acceptances back, so nobody accepts one deal and gets another.
- A card you give away that's in one of your decks comes out of that deck
  (the panel warns you first, and the chat lists them afterwards).
- Nothing is lost if a message goes missing or someone reloads: the side
  that didn't ask carries out the deal first, and the side that asked does
  its half once it hears back. That deal is saved and sent again (also after
  a reload or logout) until it's answered, and a side that no longer has
  the trade open says no, so nothing changes on either side.

### Achievements

58 achievements in seven groups (the circuit, the collection, battles,
travel, other players, traps, and oddities such as winning on exactly 1
Morale or on the tiebreak), on the **Records** tab with a progress bar each. They're worth
points and nothing else, so they don't change how fast the collection
grows. Each one earned shows a toast near the top of the screen (click it
for the Records tab) and a line in chat.

Some count what you've done since 0.18.0 (Morale dealt, units destroyed,
packs opened, travel time, rounds played while travelling, trades, daily
tasks, traps set and sprung): those counters started at zero for everyone. The rest read what your
character already has (stars, cards, wins), and a character from before
0.18.0 gets those at the first login, in one line instead of a toast each.

### The guild board

The Records tab's **Guild board** lists your guildmates who have
Tradewinds: their stars, heroic wins, cards collected, achievement points
and wins against players, and when they were last heard from. Click a column
to sort by it. **Challenge** and **Trade** work for anyone online on the
same version as you.

Tradewinds sends these numbers to your guild's addon channel (never to
chat): once 5-30 seconds after you log in, then at most once a minute while
one of them changes. Opening the guild board asks guildmates for theirs, at
most once every 5 minutes. The **Share progress with my guild** option
(`/tradewinds guild off`) turns all of that off: nothing is sent and nothing
answered. Guildmates not heard from for 30 days drop off the board.

### Sharing

**Share** buttons on a pack with an epic, legendary or holographic card, on
an end screen with a new star or a win against a player, and on each
achievement put a line into your chat box, such as "[Tradewinds] I just
pulled Onyxia (legendary) from a card pack!". You choose where it goes and
whether to send it: Tradewinds never sends chat by itself.

**Deck codes**: the **Code** button above your deck shows it as a line of
text (`TW1:` and 42 letters and digits) to copy and share. Paste someone else's code in
the same box and click **Load**: it replaces the deck in use with the cards
you own, and chat lists the ones you're missing with what crafting them
costs. A deck that comes out short says so in the deck panel, as always. A
code from a version with a different card list is refused rather than
loading the wrong cards.

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

- **Play**: the opponent list (each opponent's portrait, stars and signature
  card, which stays grey until you've won it; a lock on the ones you haven't
  reached) with the daily task and its progress bar, then the board.
  Cards show their keywords and a short line of rules text; hover one for the
  full wording. Click
  a card and then a lane, or drag it onto the lane. **Replay** shows the last
  round again. The log under your hand, and the cards you've placed but not
  locked in yet, are saved with the match. If you reload or log out while a
  round is playing out, it is shown when you come back. At the end of a
  match the stars you earned stamp in, shards and packs count up and the
  cards you won turn over; **Rematch** starts the same opponent again at
  once, and **Play** goes straight to an opponent you just unlocked.
- **Cards**: every card with filters (owned, rarity, cost, type: unit,
  tactic, item or trap, and tribe), three deck slots, the curve checklist and
  a chart of your deck's costs. With a tribe filtered, the header counts that
  tribe; the Tribe filter's tooltip lists every tribe's progress. Shift-click
  a card to craft it.
- **Packs**: open card packs and Windfall packs and click each card to turn
  it over. A rare or better glows in its colour first, and an epic, a
  legendary or a holographic card charges up for a moment before it turns.
  **Reveal all** turns the rest one after another, the best last, and a line
  under the pack sums it up ("2 new cards, +3 shards"). **Open all** opens
  every pack at once. Both travel clocks are here too.
- **Records**: achievements, and the guild board (see above).
- **Guide**: every rule, a round step by step, each keyword with a diagram,
  and a page on traps. The tutorial can be started from here too.
- **Options**: sound, the forecast, opponent lines, the travel prompt,
  closing when you arrive or in combat, the minimap button, sharing progress
  with your guild, replay speed, window size and the **board**: the tavern
  table, a ship's deck, the evening sky, or **Automatic** (the default: the
  sky on a flight, the deck on a boat or zeppelin, the tavern otherwise,
  picked when a game goes on the board).

The first time a keyword turns up in a match (in your hand or on the board),
a box explains it with its diagram; traps get one too. Opponents say a line now and then: when
a match starts, after a big hit either way, and when they're close to losing.
Click the bubble to dismiss it; the Opponent lines option turns them off.

## Languages

Tradewinds follows the game client's language: English, German, French,
Spanish (Spain and Latin America), Italian, Brazilian Portuguese, Russian,
Korean, and simplified and traditional Chinese. Cards, creatures, spells and
places use the client's official names where there are some. The chat
commands stay in English in every language.

The translations were made with an AI model, not by native speakers, so
corrections are welcome. To fix or add one, see Translating below.

## Commands

- `/tradewinds`: show or hide (`/tradewinds play | cards | packs | records | guide | options`
  opens a tab). There's also a minimap button and a key binding.
- `/tradewinds tutorial`: the guided match against Dorn. It doesn't use your
  deck and doesn't count on the circuit.
- `/tradewinds challenge [name]`: challenge another player (no name: your
  target).
- `/tradewinds trade [name]`: trade cards with another player (no name: your
  target).
- `/tradewinds end`: end the match you're in (the same as the **End match**
  button; it asks first, counts as a loss and earns nothing). You never
  *have* to end a match: it's saved after every round.
- `/tradewinds rules`: opens the Guide
- `/tradewinds icons`: card icons this client doesn't have (for bug reports)
- `/tradewinds travel`: what Tradewinds sees of your travel right now.
  `/tradewinds travel log` prints a line a second (to check boat detection on
  a real crossing); run it again to stop.
- `/tradewinds probe`: checks the game functions Tradewinds relies on (the
  guild roster, the guild addon channel, the chat box, sound kits) and
  prints a line for each, for bug reports. In English only.
- Everything in the Options tab also has a command: `/tradewinds help` lists
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
  plans, checksums, concede, resends), and deck codes. The message format is
  at the top.
- `Guild.lua`: the guild board's two messages on the guild addon channel
  (`LB`, a player's numbers; `LQ`, a request for them), checked field by
  field on arrival. `UI/Records.lua` draws the Records tab.
- `Data/Achievements.lua`: the achievements, each with a function that says
  how far along you are; `Collection.lua` keeps the lifetime counters
  (`db.life`) and the ones earned (`db.ach`).
- `Probe.lua`: `/tradewinds probe`.
- `Trade.lua`: trading cards, over the same whispers; `UI/Trading.lua` is
  the trade panel in the Cards tab.
- `Engine/Cards.lua`, `Engine/CardsRoads.lua`, `Engine/CardsTribes.lua`,
  `Engine/CardsTraps.lua`: the card sets (`CardsTribes` also gives every unit
  its tribe and marks the items). Traps live beside the board, in
  `P.traps`, and `R.Redact` is the copy of the game one side may see.
  `Engine/AI.lua`: the computer opponent.
- `Data/Opponents.lua`, `Collection.lua`: opponents; collection, deck, packs,
  crafting, stars, daily tasks and rewards (saved per character in
  `TradewindsCharDB`, with numbered migrations).
- `Art/`: textures, generated by `tools/gen_art.py`, including the rules
  diagrams (`Diagram_*.tga`).
- `UI/Effects.lua`: the combat effects in the round replay (projectiles,
  impacts, damage numbers, keyword callouts, death ghosts, banners), driven
  by one OnUpdate.
- `UI/`: the window (`Main`), board (`Game`), binder and decks (`Binder`),
  pack opening (`Packs`), options (`Options`), the card frame, tooltips and
  sounds (`Widgets`).
- `Locales/`: translations. Text is written in English in the code and looked
  up in `ns.L` (`L["Lock In"]`); `Locales/Locale.lua` sets that up and each
  language file fills it when the client uses that language. Card, opponent,
  keyword and tutorial text goes through `L` where it's defined. Labels that
  would overflow (card names, card text, buttons) shrink to fit
  (`UI.FitText`).
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
  between continents are skipped over, and the client closes open windows
  when you arrive, so a window that was open opens again after one; for 15
  seconds after it, standing still doesn't count as docking. The reopening
  has not been checked on a real boat yet.

## Tests

```
pip install lupa
python tests/run_tests.py          # engine, ui, pvp, saves and locale
```

`tests/engine.lua` checks every keyword and card effect (every case in the
traps' rules too, and that neither side's forecast nor the computer can tell
where the other side's trap is), determinism, the copy limits, pack odds, rewards, stars, crafting, save migrations and the pace of
the collection, and plays a few hundred AI-vs-AI games (to check for errors,
game length and balance). `tests/ui.lua` loads the whole
addon against a strict WoW API mock, where an unknown widget method is an
error. It plays games through the same functions the buttons call, then
opens packs, edits the deck and takes a mock flight and a mock boat ride.

`tests/pvp.lua` runs two complete clients (each with its own mock, saved
data and copy of the addon) joined by a pretend network. It plays whole
matches between them, loses a message, reloads one client mid-match, takes
one offline for a few minutes, concedes, and corrupts one copy to check the
mismatch is caught (in the last round too). Three more clients share a
guild: they see each other on the guild board, one who doesn't share sends
nothing, and malformed or misdirected messages are ignored. Alice sets two
traps against Bob: one springs on both sides, and Bob's board shows only that
she has one left. `tests/engine.lua` also plays 50 games as both mirrored
copies (20 of them with decks full of traps) and checks they never differ.

`tests/saves.lua` loads saved data through the whole addon: the real saves
in `tests/saves/` (copies of players' files, kept out of git because they
have character names in them) and constructed ones from each era. Every card
count must stay exactly as it was, cards this version doesn't know must be
set aside rather than lost, and fields a newer version wrote must be left
alone. Each save is then saved and loaded again, used (tabs, packs, a round
of a match), and loaded by the previous version, which `run_tests.py`
exports from git (the last commit with another `## Version` in the .toc).

`tests/locale.lua` checks the translations: every text the code looks up is
in the template `Locales/enUS.lua`, and every language file translates all of
them, nothing else, with the same placeholders, colour codes and line breaks,
and card text short enough for the card. `tests/locale_smoke.lua` then plays
the addon in each language (every tab, card, tooltip, the tutorial and a
match), so a translation that breaks a format string fails there.

`tests/balance.lua` is the balance harness, run on demand (minutes, not
seconds; `balance tribes` plays decks of one tribe against each other):

```
python tests/run_tests.py balance ai [games]       # the AI levels against each other
python tests/run_tests.py balance ladder [games]   # the circuit with the starter deck, and the heroic rematches
python tests/run_tests.py balance cards [n] [ids]  # each card's effect on winning
```

`cards` plays every card in nine decks (the starter and each opponent's)
against the opponents, then the same games with a plain unit of the same cost
in its place, and reports the difference in win rate.

## Translating

`Locales/enUS.lua` lists every text with notes on where it appears. It's
generated: after changing text in the code, run
`python tests/run_tests.py locale write`, then `python tests/run_tests.py
locale` to see what each language is missing. To add a language, copy the
template to `Locales/<code>.lua`, change the code in its `NewLocale` line,
add it to `Tradewinds.toc` after `Locales\Locale.lua`, and translate the
right-hand sides. The template's header lists the rules (placeholders in the
same order, colour codes kept, commands in English).

## Release

`python tools/package.py` runs the tests and builds
`dist/Tradewinds-<version>.zip` with only what the game loads (no tests, tools,
plans or translators' template). Unzip it into `Interface/AddOns`. `.pkgmeta`
has the same exclusions for the CurseForge / Wago packager, which also takes
the release notes from `CHANGELOG.md`.

## License

MIT, see [LICENSE](LICENSE). World of Warcraft and its icons belong to
Blizzard Entertainment: the cards show the game's own icons, which aren't
part of this repository. Everything in `Art/` and `media/` is drawn by the
scripts in `tools/`.

## AI Disclosure

Built with Claude!
