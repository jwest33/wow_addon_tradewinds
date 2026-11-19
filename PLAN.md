# Deckhand polish plan

Written 2026-11-19 against v0.2.2, after reading every source file, running the
tests (567 engine + 64 UI checks pass) and simulating the pack economy.

The rules engine is the strong part: pure, deterministic, well tested. What
makes the addon feel like a draft is everything around it: the reward loop,
the look and feel of the board, onboarding, and release hygiene. The plan
keeps the engine and rebuilds those four.

---

## 1. Findings

### 1.1 Rewards (the biggest problem)

Simulated with the real pack odds, starting from the starter deck (2,000 runs,
shards re-spent on packs):

| Milestone | Packs earned (median) | 10th-90th percentile |
|---|---|---|
| Own 50% of the cards | 5 | 4-6 |
| Own 75% | 13 | 11-15 |
| Own 90% | 25 | 21-32 |
| Every non-legendary card | 39 | 28-62 |
| Every card | 73 | 43-134 |
| Full playset (2 of each, 1 legendary) | 81 | 53-135 |

Against that, a new character gets 3 packs at the start, one per level, one
per flight path discovered, one per 10 flight minutes, one for the first win
each day and five for first wins. Levelling alone covers the whole set.

Why it happens:

1. **The set is small for the pack size.** 48 cards, 5 per pack, a
   guaranteed rare-or-better in every pack. The 9 rares are done in about 25
   packs.
2. **Most packs don't come from playing.** Levels and flight paths pay out
   whether or not a match is ever played. A win is worth 3 shards (0.15 of a
   pack), so the game itself is the worst source.
3. **Shards have one use.** They only buy more packs, so duplicates speed the
   collection up, and once it's complete they do nothing.
4. **Nothing is earned by skill.** All five opponents are open from the
   start and every card is in every pack, legendaries included.
5. **There is nothing after the collection.** No ranks, goals or cosmetics.

Two exploits:

- **Concede farming.** Starting a match and ending it pays 1 shard
  (`UI/Game.lua:874`, `Collection.lua:229`). Twenty of those is a pack.
- **Dorn farming.** A win pays the same 3 shards against any opponent
  (`Collection.lua:228`), and the starter deck beats Dorn 82% of the time.

### 1.2 Bugs and robustness

| # | Problem | Where |
|---|---|---|
| B1 | A round resolves directly on the saved match. If a card effect errors midway, a half-applied round is saved and the board stays locked until End match or /reload. | `UI/Game.lua:799` |
| B2 | During the round replay the hand, Supply and hand/deck counts already show the next round, including the card you are about to draw. | `UI/Game.lua:378, 389, 444` |
| B3 | Logging out or reloading during a replay loses it. If that was the last round, the next login jumps straight to Victory or Defeat. | `UI/Game.lua:502` |
| B4 | Morale can show as a negative number on the board, the end screen and in chat. | `UI/Game.lua:366, 490, 845` |
| B5 | The forecast runs random effects with a fixed seed and shows that one outcome ("dies") as certain. | `UI/Game.lua:161` |
| B6 | Any version bump ends a saved match, even a cosmetic one. | `Collection.lua:76` |
| B7 | The saved data has no schema version, so every future migration has to guess. A match is only checked for having a state and a known opponent, not for a sane shape. | `Collection.lua:47-81` |
| B8 | Boats and zeppelins are not detected at all: no offer, no travel time. Only taxi flights are. | `Travel.lua` |
| B9 | The pack toast always says "+1 card pack". | `UI/Main.lua:207` |
| B10 | Changing the window scale moves a window whose position was saved. | `UI/Main.lua:15-29, 149` |
| B11 | Pierce damage passes through a Sturdy unit that survives the hit. Needs a decision: intended or not. | `Engine/Rules.lua:425` |

Still unverified in game (carried over from the first session): card icon
paths (`/deckhand icons`), creature ids for portraits, the addon compartment
entry, and whether the "How to play" text fits its box.

### 1.3 Look and feel

- **Cards hide their effects.** The face shows keyword names only, cut to two
  (`UI/Widgets.lua:284`). Arrive, Fallen and other text is in the tooltip
  only, so Plainstrider, Hogger and Onyxia look like plain units.
- **Cards are small.** 66x92 with 8-9 pt text, in a 560x452 window.
- **No art direction.** Every surface is a flat one-pixel-border rectangle
  with a cropped spell icon. Stock red buttons sit beside the flat style.
- **Combat has no motion or sound.** Strikes are colour flashes. The only
  sounds in the addon are in pack opening.
- **Planning is click-then-click only.** No drag and drop, no keys, no
  warning when locking in with Supply and playable cards left.
- **Settings are slash commands only.**
- **The rules are a wall of text** shown once, plus one tip box.
- **The game log** is hidden by default, sits outside the window and is
  emptied by /reload.
- **The binder** has no search or filters and holds a single deck.
- **Pack opening** has no flip or build-up, and no way to open several.

### 1.4 Depth

- **AI.** It scores plans as if the player adds nothing (hard also tries one
  generic blocker). It never holds a card on purpose, samples plans at random
  instead of searching small hands fully, and all opponents share one
  personality. Starter-deck win rates run 82 / 53 / 33 / 28 / 8%, so the
  ladder shape is fine but there is no step above "hard".
- **Deck building.** 48 cards with no factions or synergy groups. A better
  deck is mostly the same deck with rarer cards.
- **Balance is measured by ladder win rate only.** Nothing measures single
  cards. Healing Potion (1 Supply for 4 Morale, when most games are decided
  on Morale at the round cap) and Lord Kazzak (Cleave + Drain) are the first
  two I would check.

### 1.5 Engineering

- The folder is not a git repository.
- No linter. One harmless shadowed local already exists (`UI/Binder.lua:85,
  111`).
- `tests/`, `README.md` and this file sit inside the folder the game loads.
- The .toc has no author, category or changelog.
- Every string is hard-coded English.

---

## 2. Plan

Each phase ships on its own with a version bump. Sizes: S = one sitting,
M = a few, L = many.

### Phase 0: Safety net (S)

Status (v0.3.0, 2026-11-19): items 1 and 3-6 are done. Item 2 is replaced for
now by a test that fails on stray globals, because there is no Lua toolchain
on this machine to run luacheck. Item 7 is partly done: the generated
textures load in game; icons, portraits and the addon compartment entry are
still unchecked.

1. `git init`, first commit of v0.2.2, `.gitignore`.
2. Add `luacheck` with a WoW globals list; fix what it finds.
3. `db.schema` number and an ordered list of migrations in `Collection.lua`,
   with a test per migration (B7).
4. `R.RULES_VERSION`, bumped only when rules or cards change; matches compare
   that instead of the addon version (B6).
5. Resolve on a clone and swap it in on success; on error keep the old state,
   unlock the board and report once (B1).
6. Fixes: B4 (show 0), B9, B10, concede pays nothing.
7. In-game check of the unverified list above. This needs you: one session,
   `/deckhand icons`, and any Lua errors.

Done when: tests and luacheck pass, and an injected card error leaves the
match playable.

### Phase 1: Rewards and progression (L)

Status (v0.4.0, 2026-11-19): built, with these differences from the text
below.

- The set was doubled instead of waiting for Phase 4: "Roads of Azeroth", 49
  cards around five tribes, and three new opponents (8 in all). Regional
  packs are still to do.
- Pack odds are rare 26% and epic 5%, tuned on the larger set. Measured pace:
  half the pack cards at 19 packs, three quarters at 44, one of each at about
  120. With the packs from stars that is roughly three weeks for three
  quarters.
- The second star pays the signature card. The third (a deck with no rares or
  better) pays 2 packs.
- Starter packs are 2 until the tutorial exists (then 1 + 1).
- Not built yet: cosmetics (they need the new card face from Phase 2), heroic
  rematches (they need the Phase 4 AI), the achievements page.
- The new cards are tested for what they do, not yet for balance, and their
  icons are unchecked in game.

Target pace (change this if you want it faster or slower): a new card most
sessions for the first two weeks, about 75% of the set in two to three weeks
of casual play, the full playset in two to three months, and legendaries
never by luck alone.

**1a. Packs**

- 3 cards: 2 commons and 1 uncommon or better (uncommon 75%, rare 21%, epic
  4%, a guaranteed epic if 14 packs pass without one).
- Legendaries leave packs (see 1c).
- Simulated on the current set: 75% of the pack cards at 23 packs, 90% at 48,
  full playset at about 170, against 13 / 25 / 81 today.

**1b. Income, tied to playing**

| Source | Now | Proposed |
|---|---|---|
| Start | 3 packs | 1 pack, plus 1 for finishing the tutorial |
| Level up | 1 pack | 5 shards; a pack every 10th level |
| New flight path | 1 pack | 5 shards |
| Flight time | pack per 10 min | pack per 20 min |
| Win | 3 shards | 2 / 4 / 6 / 8 by opponent tier; full value for the first 3 wins per opponent per day, then 1 |
| Loss or draw | 1 shard | 1 shard, only if the game reached round 4 |
| Concede | 1 shard | nothing |
| First win of the day | 1 pack | 1 pack |
| Daily task | none | 10 shards (see 1d) |
| Pack price | 20 shards | 30 shards |

That is roughly 12-15 packs a week for someone who plays three or four
matches a day. All numbers live in one table in `Collection.lua`.

**1c. Things to spend on and earn**

- **Crafting.** Shards make a chosen card: common 10, uncommon 25, rare 60,
  epic 150, legendary 400. Duplicates pay 1 / 3 / 10 / 25. This removes the
  bad-luck tail (today's 90th percentile for the last card is 134 packs).
- **Signature cards.** Each opponent owns one or two cards that only they
  give: Hogger from Grumbletusk, Azuregos from Pellwick, Onyxia from Prestor,
  and so on. They are won through mastery, or crafted at the legendary price.
- **Cosmetics** as the endless sink: card backs, a gilded border for a card
  owned beyond its playset, board themes.

**1d. Structure**

- **The circuit becomes a ladder.** Opponents unlock in order. Each has three
  mastery stars: win; win by a margin of 6 or more Morale; win with a
  restricted deck (for example no rares or better). Stars unlock the next
  opponent and pay the signature card.
- **Heroic rematches** after the last boss: the same five with tuned decks
  and the stronger AI from Phase 4, paying the top win rate.
- **Daily task**, one a day, drawn from a list ("win with 3 Guard units in
  play", "deal 6 Morale damage in one round"). Checked from the events the
  engine already emits.
- **Achievements page** with collection, ladder and oddity goals.

**1e. Existing saves**

Collections, decks and unopened packs carry over as they are (old packs open
with the new odds). Legendaries already owned stay. Opponents already beaten
count as unlocked with their first star.

**1f. Tests**

An economy test that runs the simulation and fails if the medians leave the
target bands, so later card or odds changes can't break the pace silently.
Tests for both exploits.

### Phase 2: Board and card presentation (L)

Status (v0.5.0, 2026-11-19): built, not yet seen in game. Item by item:

- Done: 1 (800x600 window, 92x128 cards), 2 (card face on the generated
  frame, with keywords and a short rules line), 4 (a double-size card beside
  the tooltip, which stays for the full wording), 6, 8, 9, 10, 13 (filters,
  three deck slots, cost chart; crafting is shift-click), 14.
- Partly: 3 (card frame, card back, badges, board and stars are generated
  art; buttons, panels and lane markers still use the client's), 5 (attackers
  lunge; no shake or death fade yet), 7 (drag and drop, and a nudge when
  Supply and a playable card are left; no keyboard shortcuts), 11 (damage and
  unit counts on the end screen; rewards don't count up), 12 (open all, with
  the new cards listed in chat; no flip animation or glow).
- Not done: search by name in the binder.
- The art test command is gone.

1. **Bigger layout.** Window about 780x580, cards about 90x126. Text no
   smaller than 10 pt.
2. **Card face redesign.** Art, name bar, a rules box with keyword icons and
   one short line of text ("Arrive: +2 Morale"), cost gem, attack and health
   badges, rarity gem. Short text is a new `short` field per card.
3. **Shipped textures** in `Art/`: card frames per rarity, a card back, a
   board background, badges, lane markers. Generated by a script in the repo
   so they can be regenerated at any size. Buttons restyled to match.
   Reliability: frames, borders, gems, badges, backgrounds and glows are
   safe to generate. Creature illustrations are not, so card art stays the
   client's icons and portraits. First step is one test texture loaded in
   game, to confirm the file format on this client.
4. **Large card preview** on hover, replacing the GameTooltip for cards, with
   the portrait inside it.
5. **Combat motion.** Attackers lunge toward their target, the target shakes,
   deaths fade, Morale hits pulse the panel. Swift strikes visibly go first.
6. **Sound**, with a setting: card placed, lock in, strike, death, tactic,
   round start, win, loss.
7. **Planning.** Drag and drop next to click-click; Space to lock in, Escape
   to deselect; a note on the Lock In button when Supply and playable cards
   remain.
8. **Replay.** Freeze hand, Supply and counts at the pre-round state (B2).
   Save the last round's events with the match so it can be shown again after
   a reload, and add a "Replay round" button (B3).
9. **Forecast.** Mark outcomes that depend on a random effect as "may die"
   instead of "dies" (B5).
10. **Log** inside the window, on by default, saved with the match.
11. **End screen** with match numbers (damage dealt, units lost, best round)
    and rewards counting up.
12. **Packs.** Card flip, rarity glow before the flip for epics, "Open all".
13. **Binder.** Search, filters by cost, rarity and type, three named deck
    slots, a cost-curve bar chart, crafting from the card's context.
14. **Options tab** in the window for everything that is a slash command now.

Done when: the UI test covers the new widgets, and a full match, a pack
opening and a deck edit look right in game at scale 0.8, 1.0 and 1.3.

### Phase 3: Onboarding (M)

1. **Tutorial match** against Dorn with a fixed seed and deck: three guided
   rounds that teach lanes and blocking, tactics landing after the reveal,
   and one keyword. It replaces the rules text as the first-run experience.
2. **Glossary page**: keywords with small diagrams, turn order, how the game
   ends. The current rules text moves here.
3. **Keyword tips the first time each keyword appears** in a real match, in
   the style of the existing lane tip.
4. Opponent lines during play (opening, a big hit, near defeat), short and
   skippable.

### Phase 4: Depth (L)

1. **AI.**
   - Search every plan when the hand is small; sample only above a limit.
   - Model the player's reply by sampling plays from a generic card pool
     sized to their Supply and hand count. It stays honest: it never reads
     the real hand.
   - Let it value holding a card.
   - Personalities per opponent: weights for aggression, board and Morale.
   - A "heroic" level above hard.
2. **Balance harness.** Per-card win-rate impact (deck with the card against
   the same deck without it, over a few hundred games), run on demand. Tune
   outliers. Decide B11.
3. **Second set, about 40 cards**, built around tribes (Beast, Murloc,
   Undead, Defias, Dragonkin) with payoffs, so deck building has directions.
   Regional packs: the pack you earn depends on the continent you are flying
   over.
4. **More opponents** to fill the ladder to 8-10, each built on a tribe.
5. **Boats and zeppelins** (B8). Needs research in game first: what the
   client exposes while on a transport.

### Phase 5: Release (M)

1. Move `tests/`, `README.md` and `PLAN.md` out of the loaded folder, or add
   a packaging step that leaves them out.
2. .toc: author, category, a real version scheme; `CHANGELOG.md`.
3. Strings into one locale table (English only for now).
4. A sanity check on load that drops a malformed saved match with a message
   instead of erroring later.
5. A memory and frame-time check over a long session.
6. 1.0.

### After 1.0

Player against player over addon messages (already designed for: seeds,
plans, checksums), then trading.

---

## 3. Decisions (made 2026-11-19)

1. **Pace.** Approved: about 75% of the set in two to three weeks of casual
   play, everything in two to three months.
2. **Current collection.** Kept. The card set itself is to be expanded, so
   the second set (Phase 4 item 3) moves up: design it alongside Phase 1 so
   the reward numbers are tuned for the larger set, and ship it right after
   Phase 2's card face is done.
3. **Art.** Card art stays the client's icons. Everything else (frames,
   borders, badges, card back, board, markers, glows) is generated by
   `tools/gen_art.py` into `Art/`. A first pass exists; `/deckhand art`
   shows it in game.
4. **Audience.** Friends now, public later. Phase 5 items 1-3 are required,
   but can wait until just before the public release.
5. **Player against player.** After Phase 3.
