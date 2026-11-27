# CurseForge listing: Tradewinds

What to put in each field when creating the project. The logo is
`media/logo.png` (512 x 512; `media/logo-1024.png` if a bigger one is
wanted), made by `tools/gen_logo.py`. Nothing in `media/` ships in the addon.

## Fields

| Field | Value |
|---|---|
| Project name | **Tradewinds: A Travel Card Game** |
| Slug (URL) | `tradewinds-card-game` (https://www.curseforge.com/wow/addons/tradewinds-card-game) |
| Summary | A Warcraft card game for flights and boat rides. Earn card packs as you travel, build a deck, beat the tavern regulars and challenge your friends. |
| Game | World of Warcraft, the WoW Forever flavor (game version 1.60.1, `## Interface: 16001`) |
| Main category | Minigames |
| Other categories | Miscellaneous |
| Logo / avatar | `media/logo.png` |
| Licence | MIT License (the repo's `LICENSE`, which also ships in the zip) |
| Source | GitHub, `https://github.com/jwest33/wow_addon_tradewinds` |
| Automatic packaging | Off: upload `dist/Tradewinds-<version>.zip` by hand and pick WoW Forever 1.60.1 as the game version |
| Changelog | `CHANGELOG.md` (the packager reads it, see `.pkgmeta`) |

Name check (2026-11-20): "Deckhand" (`/wow/addons/deckhand`, a different
author's WoW Forever card game), "Stowaway" and "FlightDeck" are taken on
CurseForge. No addon called Tradewinds turned up. CurseForge will tell you
when you create the project if the slug is free after all.

## Shot list

Put the GIF first in the description, then the screenshots in this order,
each with its caption.

| # | Shot | Caption |
|---|---|---|
| GIF | Lock In, "3, 2, 1, Reveal!", the whole combat of a busy round (8-12 s) | Plan in secret, reveal at once |
| 1 | The board mid-planning on a flight, lane markers and forecast showing | Eight rounds, four lanes, one flight |
| 2 | A pack with a holographic or epic card just turned over | Packs for the miles you travel |
| 3 | Hovering a tribe card so its kin light up on the board | Six tribes that fight better together |
| 4 | The Cards tab with a deck built and a tribe filtered | 168 cards to collect |
| 5 | The tavern circuit with some stars earned | Eight opponents, three stars each |
| 6 | The tutorial coach pointing at a lane | Dorn teaches you in four rounds |
| 7 | "Your games" with several games against players | Play friends at your own pace |
| 8 | The trade panel with cards on both sides | Trade with friends |
| 9 | The Guide tab on a keyword diagram | Every rule, with diagrams |

## Description

Paste this into the description editor (it takes Markdown).

---

**Your flight is six minutes. A game is eight rounds.**

Tradewinds is a Warcraft card game made for flights, boats and zeppelins.
Both players plan at the same time, so nobody waits on a turn, and the
miles you travel pay you in card packs.

### What's different

- **No turns to wait on.** Both sides plan in secret and reveal at once.
- **Fits the trip.** Eight rounds at most, saved after every round.
- **Earned, never bought.** Packs come from travelling and playing.
- **Play friends at your own pace**: up to eight games going at once.
- **Trade cards** with friends and guildmates.

### How a game goes

- Both sides start with **12 Morale**. Games last **at most 8 rounds**, so a
  match fits in one flight.
- Each round you get a little more **Supply** to spend. Play **units** into
  your four lanes and **tactics** at the enemy's lanes or your own units.
- Both players plan at the same time, then everything is **revealed at once**.
  Every unit strikes the enemy across from it, or the enemy's Morale if its
  lane is open. Guessing where your opponent will play is half the game.
- Run their Morale down to 0, or have more of it after round 8.

### What's in it

- **168 cards** in three sets, with keywords like Guard, Swift, Ranged,
  Pierce, Venom and Drain, and six tribes that reward being played
  together: Beasts, Humanoids, Murlocs, Undead, Defias and Dragonkin.
- **Items**: potions, bombs and gear, from Iron Grenade to Thunderfury.
- **A tutorial** with Flightmaster Dorn that teaches you the game in four
  rounds.
- **A circuit of eight opponents** with their own decks and personalities,
  each with stars to earn, signature cards to win, and heroic rematches once
  you beat them all.
- **Card packs** for every 20 minutes of travel and your first win of the
  day. Wins, new flight paths and spare copies give shards for crafting the
  cards you want.
- **Windfall packs**: five cards, one always rare or better, for every 45
  minutes of travel and for milestones such as finishing the tutorial,
  every tenth level and collecting a whole tribe.
- **Rare holographic cards**: they play the same, they just shine.
- **Games against friends and guildmates**, several at once, played whenever
  you're both online. Plans are sent quietly over addon whispers.
- **Trade cards with friends**: both put up cards, both accept, done. Safe
  against lost messages and disconnects.
- **Saved after every round.** Land, log off, pick it up on the next trip.
- **Ten languages**: English, German, French, Spanish, Italian, Brazilian
  Portuguese, Russian, Korean, and Simplified and Traditional Chinese.

### Getting started

Type **/tradewinds** (or click the minimap button) and accept Dorn's offer of
a guided first game. The Guide tab explains every rule with diagrams.

| Command | What it does |
|---|---|
| `/tradewinds` | Open or close the window |
| `/tradewinds tutorial` | Play the guided first match again |
| `/tradewinds rules` | Open the Guide |
| `/tradewinds challenge Name` | Challenge a friend (or target them first) |
| `/tradewinds trade Name` | Trade cards with a friend (or target them first) |
| `/tradewinds scale 1.2` | Make the window bigger or smaller |
| `/tradewinds reset` | Move the window back to the middle |

Both players need the same version of Tradewinds to play or trade with each other.

*Tradewinds is a fan-made addon and isn't affiliated with or endorsed by
Blizzard Entertainment.*
