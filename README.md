# ZugZug — WoW Talent Builds for Leveling, Raid & Mythic+

**Talent guidance from level 10 to 80 — a step-by-step leveling talent picker, plus top raid and Mythic+ builds from WarcraftLogs, all in your talent frame. One-click import. Updated daily.**

Stop alt-tabbing to Wowhead, Icy Veins, or Raidbots to find the right talents. ZugZug brings level-by-level talent guidance for every spec and the most popular endgame talent builds from [zugzug.info](https://zugzug.info) — sourced from thousands of top WarcraftLogs parses — directly into your in-game talent UI.

> *Keywords: WoW leveling guide, talent builds, World of Warcraft leveling addon, Mythic+ builds, raid builds, talent loadouts, WarcraftLogs builds, talent import strings, Midnight builds, leveling talents, talent calculator alternative*

## What It Does

ZugZug guides your talent choices through your **entire character lifecycle**:

- 🌱 **Leveling (10–79):** A floating banner shows the next talent to pick at every level, following a curated build order through your class, spec, and hero trees
- 🏰 **Raid (80):** Per-boss talent build recommendations from top WarcraftLogs parses, with one-click import
- ⚔️ **Mythic+ (80):** Per-dungeon and per-key-level build recommendations, also one-click import

Click any build to apply it instantly — no copy/paste of import strings, no leaving the game.

## Leveling Guide

Below max level, ZugZug shows a **"next talent to pick"** banner with a curated talent order specific to your spec. The pick order follows community leveling guides (Wowhead, Icy Veins) and respects WoW's tree gate rows and prerequisite chains:

- **Phase 1 (10–20):** Class tree
- **Phase 2 (~20–70):** Spec tree
- **Phase 3 (71–80):** Hero tree

Every WoW class and spec is supported — 39 specs total, all with hand-tuned leveling pick orders.

## Endgame Builds

- **Raid builds** with per-boss recommendations — see which build is best for each encounter
- **Mythic+ builds** with per-dungeon and per-key-level recommendations
- **All classes, all roles** — DPS, Healer, and Tank builds for every spec
- **One-click apply** — click a build to load it into your talent config and Apply
- **Shift+click to copy** the raw import string for use in Raidbots or Wowhead

## Why ZugZug

| Compared to... | ZugZug advantage |
|---|---|
| Wowhead / Icy Veins guides | Always current — data refreshed daily from live WarcraftLogs rankings, not written once a patch |
| Manually pasting import strings | No alt-tabbing — apply with one click directly from the talent frame |
| Raidbots Top Gear | Real builds played by real top parsers, not theorycraft simulations |

## Features

- Auto-detects your class, spec, and role on login
- Builds appear when you open your talent frame — no extra windows to manage
- **Movable bar** — drag it anywhere on screen with a lock toggle and reset
- **Raid difficulty toggle** — switch between Heroic and Mythic builds
- **M+ key level filter** — All / 15+ / 18+ / 20+ keys
- **Hover tooltips** show which bosses or dungeons each build is best for
- **Popularity %** and **trend indicators** (NEW / ▲ / ▼) on every build
- **Talent diff** in tooltip — see how many talents differ from your current loadout
- **Favorites** — star builds to pin them to the top
- **Smart Suggest** — auto-recommend a build when you target a raid boss or enter a dungeon
- Saved settings between sessions

## Installation

1. Download the latest release from [CurseForge](https://www.curseforge.com/wow/addons/zugzug-companion) or [Releases](https://github.com/BAThomp24/zugzug-addon/releases)
2. Extract the `ZugZug` folder into `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`

## Slash Commands

- `/zz` or `/zugzug` — show help
- `/zz show` — toggle the build bar (standalone, without opening the talent frame)
- `/zz settings` — open the settings panel
- `/zz status` — show current class, spec, settings, and data status
- `/zz diff heroic` or `/zz diff mythic` — set raid difficulty
- `/zz key all` or `/zz key 15+` or `/zz key 18+` or `/zz key 20+` — set M+ key level filter
- `/zz suggest` — toggle Smart Suggest on/off
- `/zz minimap` — toggle the minimap button

## Data Source

Build data comes from **[ZUGZUG.io](https://zugzug.info)** — a web companion that analyzes top WarcraftLogs V2 rankings across every spec, clusters players by talent fingerprint, and identifies the dominant builds for every raid boss and Mythic+ dungeon. Data refreshes daily, and the addon ships with each day's snapshot bundled in.

You can also browse the same builds on the web:
- **Raid builds:** [zugzug.info/warlock/raid](https://zugzug.info/warlock/raid), [/mage/raid](https://zugzug.info/mage/raid), etc.
- **Mythic+ builds:** [zugzug.info/warlock/mythic-plus](https://zugzug.info/warlock/mythic-plus), etc.

## Links

- 🌐 Website: **[zugzug.info](https://zugzug.info)**
- 📦 CurseForge: **[zugzug-companion](https://www.curseforge.com/wow/addons/zugzug-companion)**
- 🐛 Issues / feedback: [GitHub Issues](https://github.com/BAThomp24/zugzug-addon/issues)
- ☕ Support: [Buy me a coffee](https://buymeacoffee.com/bathomp24)
