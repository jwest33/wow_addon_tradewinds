# Changelog

## 0.17.0

**Tribes of Azeroth**: 71 new cards (168 in all), Windfall packs, and items.
Matches in progress carry on: no rule changed. Games against players and
trades need you both on this version.

- **Every unit has a tribe.** Humanoids join Beasts, Murlocs, Undead, Defias
  and Dragonkin: the Kobold, the Grunt, Hogger and 22 others. No card counted
  Humanoids before, so nothing plays differently. (Harvest Watcher, the
  Shredder, Kazzak and Ragnaros keep no tribe until a later update gives them
  their own.)
- **The same stats in different tribes.** 34 new plain units have exactly the
  cost, stats and keywords of a plain unit of another tribe: an Ashenvale
  Bear, a Murloc Tidewarrior, a Scourge Footsoldier and a Black Drakonid are
  all 3/4 for 3, like the Orgrimmar Grunt. On their own they play the same;
  their tribe decides which cards count them.
- **27 new tribe cards**, from Murloc Raider and Rotting Squire to Bolvar
  Fordragon, Darkmaster Gandling, Murkdeep and Nefarian, built the way the
  Roads of Azeroth tribes work (auras, Arrive buffs, "for each other...").
- **Items**: 10 new (Iron Grenade, Elixir of the Giants, Thunderfury...).
  They are tactics with a leather frame and "Item" on the type line, and play
  exactly like tactics. Healing Potion and Heavy Linen Bandage are items now.
- **Windfall packs**: 5 cards, and the last one is always rare or better.
  They come every 45 minutes of travel (on a clock of their own, beside the
  20-minute card packs) and with milestones: finishing the tutorial, every
  tenth level and the first heroic win against each opponent (which used to
  pay a card pack), and, new, all three stars against an opponent, every star
  on the circuit, every heroic rematch won, and one of every card of a tribe.
  A milestone you reached before this update pays at your first login. Card
  packs are unchanged.
- Point at a card that counts a tribe (Worg Packleader, Call of the Wild) and
  the units it counts light up on the board.
- Cards tab: a Tribe filter of its own (its tooltip shows how much of each
  tribe you have), and the Type filter has items. With a tribe filtered, the
  header counts that tribe.
- `balance tribes` in the test harness plays decks of one tribe against each
  other.
- Cards are never deleted any more. Cards this version doesn't know (from a
  newer version, if you go back to this one) are kept aside, with the decks
  and trade offers that use them, and come back when you update again. Chat
  says so when it happens. Before, they were deleted at login.
- Boats and zeppelins: the window no longer stays closed after the loading
  screen halfway across. The game closes open windows when you arrive, so a
  match started on the boat ended at the loading screen. If the window was
  open, it now opens again on the far side (a window you closed yourself
  stays closed). For 15 seconds after a loading screen, standing still no
  longer counts as docking.

## 0.16.0

Rules update: a match in progress from an earlier version ends when you log
in, without counting (as with every rules change). Games against players
need you both on this version.

- Units that die at the same moment now have their Fallen effects at the
  same moment, so who has initiative no longer changes what happens. A unit
  that a Fallen effect summons (Ravaged Corpse's Skeleton) arrives after all
  of them. Before, a Corpse and a Harvest Watcher trading in the same lane
  left a Skeleton or not depending on initiative. Likewise, every unit still
  standing sees all the deaths (King Bangalash, Carrion Vulture), even if a
  Fallen effect in the same moment hurts it.
- A unit with both Pierce and Drain restores the damage it deals, no longer
  counting the part that carries on to Morale twice. No card has both yet.
- An enemy tactic can no longer be aimed at a unit with Stealth when it would
  do nothing there (Fireball, Eviscerate, Polymorph and the like). Tactics
  that also hit the lanes beside it (Chain Lightning, Flame Breath, War
  Stomp) still can.
- The replay now shows damage that's undone or never lands, instead of
  leaving a gap:
  - Regenerate healing at the end of a round gets a callout, the health it
    got back and a line in the log. Before, the unit only flashed, so the
    damage looked like it had never happened.
  - A Fallen effect with nothing across (the unit it would hit died at the
    same time) says "No target".
  - A tactic that lands on a unit with Stealth (one played this round, or
    given Stealth by a tactic that went first) says so.
- A unit marked "dies" or "may die" while you plan still shows that it's
  Frozen or has Stealth.

## 0.15.1

- Fixed: planning a unit that brings others with it (Hogger's Riverpaw
  Runts, for example) beside an empty lane could freeze the board while you
  planned. Cards you had placed stayed in your hand, playing one again put
  it in the plan twice, and Lock In then kept saying "That card isn't in
  your hand." The lane markers now name those units, and a planned card
  can't be picked a second time.
- Cards you've placed but not locked in yet are saved with the match. After
  a /reload or a logout, or when you come back to a game from the opponent
  list, they're still placed and the Supply counter still counts them.
  Before, they went quietly back to your hand and the counter showed your
  full Supply again.

## 0.15.0

- **Trade cards with your friends.** Click **Trade** under your deck in the
  Cards tab (or `/tradewinds trade Name`). While the trade is open, the deck
  panel shows what each of you gives and who has accepted; click your cards
  in the binder to offer them, up to 8 a side (or nothing, for a gift).
  Cards you'd get are marked New, +N shards (past your limit) or Holo. The
  trade happens once you've both accepted, and any change takes both
  acceptances back.
- Trades are safe against lost messages, reloads and logouts: a deal that
  hasn't been answered is saved and sent again until it is, and no cards
  change hands unless both sides carry it out.
- Cards you trade away come out of your decks; the panel warns you first.
- Your holographic copy of a card only goes if you shift-click it, or when
  it's the last copy you have to offer.
- New files (`Trade.lua`, `UI/Trading.lua`): restart the game, a /reload
  isn't enough.
- The card back, the addon icon and the logo carry a wind rose for the new
  name, in place of Deckhand's anchor.

## 0.14.0

- **The addon is now called Tradewinds** (it was Deckhand: another WoW
  Forever card game already has that name). The command is `/tradewinds`,
  and it has a logo and its own icon. To keep progress from Deckhand: with
  the game closed, rename
  `WTF\Account\<account>\<realm>\<character>\SavedVariables\Deckhand.lua`
  to `Tradewinds.lua`, and inside it change `DeckhandCharDB` to
  `TradewindsCharDB`.
- A new card face, bigger and easier to read:
  - Every card names its type on a line under its name ("Beast unit",
    "Tactic: enemy lane"), so you no longer need the tooltip to tell.
  - Units and tactics have different frames: units are bronze and
    parchment; tactics are indigo, silver and pale vellum.
  - Larger text (names 11, rules 10, type 9; it shrinks only when it has
    to), full-colour cost, attack and health badges, and a rarity gem.
  - A unit with no rules text shows its flavour line instead of an empty box.
  - The card's icon is shown whole, in a small frame in the middle of the
    picture, instead of cropped and stretched (the game's icons are small
    and looked blocky stretched).
  - Selected and hovered cards glow; tags like "dies" sit on a dark bar.
- Cards are bigger everywhere: 112 x 156 on the board and in your hand (was
  92 x 128), 5 to a row in the Cards tab, larger in packs.
- The board is laid out around the bigger cards: the log moved to the right
  column under the controls, and your hand sits under the lanes. A full hand
  of seven uses the whole width. The tutorial's coach is now a tall box on
  the right.
- The Cards tab's deck panel is redone: each card in the deck is a strip
  (bronze for units, indigo for tactics) with its cost gem, icon and name;
  then how many units and tactics and the average cost; the three curve rules
  as green or orange chips; a cost chart that splits units from tactics, with
  a line at each rule's minimum; and a green "ready" or orange "what's
  missing" banner.
- The mouse wheel scrolls the Cards tab a row at a time; the arrows still
  turn a whole page.
- The round is shown big at the top right, beside your Supply ("Round 3/8",
  turning orange near the end); the line under the opponent's panel now says
  how many rounds are left after this one.
- New textures: the first time after updating, restart the game rather than
  using /reload.

## 0.13.0

- Tradewinds now speaks German, French, Spanish (Spain and Latin America),
  Italian, Brazilian Portuguese, Russian, Korean and Chinese (simplified and
  traditional), following the game client's language. Card names, spells,
  creatures and places use the client's official names where there are some.
  Chat commands stay in English.
- Text that's too long for its space shrinks to fit: card names, card text
  and buttons.
- The creature portrait option beside card tooltips is gone; the card art
  already shows the creature.
- A saved match that can't be read is ended with its own message, instead of
  the one about a rules update.
- Packaging for release (`tools/package.py`, `.pkgmeta`) and this changelog.

## 0.12.0

- A "3, 2, 1, Reveal!" countdown before each new round plays out.
- The round counter shows how many rounds are left; the last round is
  announced as the final one.
- Lights flow along each lane the way its damage will go, while you plan and
  as the round plays out.

## 0.11.0

- Combat effects that show who hits whom: strikes one at a time with a
  projectile, impacts and damage numbers, keyword callouts (Guard, Ranged,
  Pierce, Cleave, Swift, Venom, Drain), units fading out as they die, and
  round and combat banners.

## 0.10.0

- Several games against players at once, each at its own pace. The Play tab
  lists your games and shows which wait for your move.

## 0.9.0

- Play against friends and guildmates who have Tradewinds: challenges over
  whispers, no time limit, plans sent when you lock in.

## 0.8.0

- Smarter computer opponents (easy to heroic) with their own play styles.
- Heroic rematches once the whole circuit is beaten, with holographic
  signature cards as rewards.
- Boat and zeppelin rides count as travel.
- Card balance changes (rules version 3).

## 0.7.0

- A guided tutorial match with Flightmaster Dorn, the Guide tab with a
  diagram for every keyword, first-time keyword tips and opponent lines.

## 0.6.0

- Holographic cards, legendaries in packs (very rarely), and the computer
  always opens with a unit.

## 0.5.0

- A rebuilt board and card face, short rules text on every card, the round
  log and replay saved with the match, binder filters, three deck slots and
  the Options tab.

## 0.4.0

- The second set, Roads of Azeroth (five tribes), eight opponents on a
  ladder with three stars each, crafting with shards and a daily task.

## 0.3.0

- First version kept under version control: the battle-line card game
  against the computer, packs earned on flights.
