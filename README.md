# ZugZug — WoW Talent Builds for Raid & Mythic+

**Top talent builds from WarcraftLogs, in your talent frame. One-click import for raid bosses and Mythic+ dungeons. Updated daily.**

Stop alt-tabbing to Wowhead, Icy Veins, or Raidbots to find the right talents. ZugZug brings the most popular talent builds from [zugzug.info](https://zugzug.info) — sourced from thousands of top WarcraftLogs parses across every spec — directly into your in-game talent UI.

> *Keywords: WoW talent builds, World of Warcraft addon, Mythic+ builds, raid builds, talent loadouts, WarcraftLogs builds, talent import strings, Midnight builds, talent calculator alternative*

## What It Does

ZugZug adds a build bar to the bottom of your talent window showing the dominant raid and M+ talent builds for your current class, spec, and role. Click any build to apply it instantly — no copy/paste of import strings, no leaving the game.

- **Raid builds** with per-boss recommendations — see which build is best for each encounter
- **Mythic+ builds** with per-dungeon recommendations — know which build dominates each key
- **All classes, all roles** — DPS, Healer, and Tank builds for every spec
- **One-click apply** — click a build to load it into your talent config and Apply
- **Shift+click to copy** the raw import string for use in Raidbots or wowhead
- **Leveling guide** with recommended builds and talent ordering below max level

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

1. Download the latest release from [CurseForge](https://www.curseforge.com/wow/addons/zugzugcompanion) or [Releases](https://github.com/BAThomp24/zugzug-addon/releases)
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
- 📦 CurseForge: **[zugzugcompanion](https://www.curseforge.com/wow/addons/zugzugcompanion)**
- 🐛 Issues / feedback: [GitHub Issues](https://github.com/BAThomp24/zugzug-addon/issues)
- ☕ Support: [Buy me a coffee](https://buymeacoffee.com/bathomp24)
