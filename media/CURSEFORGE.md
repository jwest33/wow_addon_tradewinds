# CurseForge listing: Tradewinds

What to put in each field when creating the project. The logo is
`media/logo.png` (512 x 512; `media/logo-1024.png` if a bigger one is
wanted), made by `tools/gen_logo.py`. Nothing in `media/` ships in the addon.

## Fields

| Field | Value |
|---|---|
| Project name | **Tradewinds - A Travel Card Game** |
| Slug (URL) | `tradewinds` |
| Summary | A Warcraft card game for flights and boat rides. Earn card packs as you travel, build a deck, beat the tavern regulars and challenge your friends. |
| Game | World of Warcraft, the WoW Forever flavor (game version 1.60.1, `## Interface: 16001`) |
| Main category | Minigames |
| Other categories | Miscellaneous |
| Logo / avatar | `media/logo.png` |
| Licence | Your choice. "All Rights Reserved" keeps every right with you; MIT lets others reuse the code. |
| Source | The git repository's URL, if you make it public |
| Changelog | `CHANGELOG.md` (the packager reads it, see `.pkgmeta`) |

Name check (2026-11-20): "Deckhand" (`/wow/addons/deckhand`, a different
author's WoW Forever card game), "Stowaway" and "FlightDeck" are taken on
CurseForge. No addon called Tradewinds turned up. CurseForge will tell you
when you create the project if the slug is free after all.

Screenshots to upload: the board in the middle of a round, the Cards tab with
a deck built, a pack being opened, and the tutorial coach. Take them after
the rename, so the window's title says Tradewinds.

## Description

Paste this into the description editor (it takes Markdown).

---

**A Warcraft card game for the long trip.** Flights, boats and zeppelins
give you time to kill. Tradewinds turns it into a quick, tactical card game
you can play without leaving your seat, and it pays you card packs for the
miles you travel.

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

- **97 cards** in two sets, with keywords like Guard, Swift, Ranged, Pierce,
  Venom and Drain, and five tribes: Beasts, Murlocs, Undead, Defias and
  Dragonkin.
- **A tutorial** with Flightmaster Dorn that teaches you the game in four
  rounds.
- **A circuit of eight opponents** with their own decks and personalities,
  each with stars to earn, signature cards to win, and heroic rematches once
  you beat them all.
- **Card packs** for every 20 minutes of travel, your first win of the day
  and every tenth level. Wins, new flight paths and spare copies give shards
  for crafting the cards you want.
- **Rare holographic cards**: they play the same, they just shine.
- **Games against friends and guildmates**, several at once, played whenever
  you're both online. Plans are sent quietly over addon whispers.
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
| `/tradewinds scale 1.2` | Make the window bigger or smaller |
| `/tradewinds reset` | Move the window back to the middle |

Both players need the same version of Tradewinds to play each other.

*Tradewinds is a fan-made addon and isn't affiliated with or endorsed by
Blizzard Entertainment.*
