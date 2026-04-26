# Leveling Builds — Design Doc

Addon-only feature (not on the website). Shows a "next talent to pick" suggestion
as the player levels, guiding them through a recommended talent order.

## Data Source

Use community leveling guides (Wowhead, Icy Veins) as the source for each spec's
recommended leveling build. These are curated for the leveling experience — AoE,
sustain, mobility — rather than endgame raid/M+ optimization.

For each of the 39 specs, we need:
- A final-build import string (what the leveling order leads to at 80)
- Or a manually curated talent pick order if the guide specifies one

### Where to find leveling builds
- **Wowhead**: `https://www.wowhead.com/guide/classes/{class}/{spec}/leveling`
  Each guide has a recommended talent order and an import string.
- **Icy Veins**: `https://www.icy-veins.com/wow/{spec}-{class}-leveling-guide`
  Similar structure with talent priorities.
- **Manual curation**: If guides disagree or are outdated, pick the best option.

The import strings from these guides can be fed into the generation script to
compute a valid topological pick order.

## Data Generation (`scripts/generate-leveling.ts`)

Takes a curated import string per spec and computes a valid pick order:

1. Parse the import string to get all selected nodes
2. Use the raidbots tree topology (posY, next/prev connections — already fetched
   weekly by the cron worker) to compute a topological sort
3. Sort by posY ascending (top of tree first), respecting prerequisite chains
   (prev nodes must be picked before next nodes)
4. Split into phases matching WoW's unlock progression:
   - **Phase 1: Class tree** (level 10–20)
   - **Phase 2: Spec tree** (level ~20–70)
   - **Phase 3: Hero tree** (level 71–80)
5. Handle multi-rank talents: add the same node multiple times in order
   (e.g., pick rank 1 early, rank 2 later)
6. Respect gate rows: WoW requires spending N points in a tree section
   before lower rows unlock — the sort must account for these thresholds
7. Output `LevelingData.lua`

### Generated data structure

```lua
ZugZugLevelingData = {
  WARLOCK = {
    {
      spec = "Affliction",
      label = "Leveling — Soul Harvester",
      importString = "CkQA...",  -- final endgame build at 80
      order = {
        -- Phase 1: Class tree (level 10-20)
        { nodeID = 71931, name = "Fel Domination" },
        { nodeID = 71933, name = "Soul Leech" },
        ...
        -- Phase 2: Spec tree (level ~20-70)
        { nodeID = 72068, name = "Conflagrate" },
        ...
        -- Phase 3: Hero tree (level 71-80)
        { nodeID = 91234, name = "Soul Anathema", choiceIndex = 0 },
        ...
      },
    },
  },
}
```

### Node ID compatibility

Raidbots node IDs match WoW's `C_Traits` node IDs (they're pulled from the
game API), so the generated nodeIDs will work directly with `C_Traits.PurchaseRank`.

## Addon UI (`Leveling.lua`)

### Detection

- Listen for `TRAIT_CONFIG_UPDATED` and `PLAYER_LEVEL_UP`
- Check if the player has unspent talent points by walking the order list
  and finding the first unpurchased, purchasable node
- Only show for characters below max level (or with incomplete builds)

### Suggestion banner

Anchored to the talent frame (like the existing ZugZug bar):

```
+--------------------------------------+
| * Next talent: Soul Leech            |
| [Pick]  [Skip]     3 of 42          |
+--------------------------------------+
```

- **"Pick" button**: calls `C_Traits.PurchaseRank(configID, nodeID)` +
  `C_ClassTalents.CommitConfig(configID)`, then advances to next
- **"Skip" button**: moves to the next talent in the order (in case the
  player wants to deviate)
- **Progress indicator**: "3 of 42" showing where they are in the order
- Auto-advances after each pick so the player can click "Pick" repeatedly

### Optional: Node highlight

Add a glow/highlight overlay on the recommended node in the talent tree so
the player can visually find it. This would require hooking into the Blizzard
talent frame's node buttons — possible but more complex.

## Files to Create/Modify

| File | What |
|------|------|
| `scripts/generate-leveling.ts` | Compute pick orders from import strings + tree topology |
| `scripts/leveling-builds.json` | Curated import strings per spec (input to generator) |
| `LevelingData.lua` | Generated per-spec leveling orders |
| `Leveling.lua` | Talent frame hook, "next talent" UI, auto-purchase |
| `ZugZug.toc` | Add LevelingData.lua and Leveling.lua |
| `.github/workflows/update-data.yml` | Run generate-leveling.ts in the daily pipeline |

## Challenges

- **Gate rows**: The topological sort must respect point-spend thresholds
  per tree section, not just prerequisite edges
- **Multi-rank talents**: Same nodeID appears multiple times in the order
  for talents with maxRanks > 1
- **Choice nodes**: Must specify which entry to select (choiceIndex)
- **Hero tree unlock**: Hero talents don't unlock until level 71 — the
  order must defer all hero picks to phase 3
- **Subtree selection**: Player must select which hero tree to use before
  hero talents can be purchased
- **Keeping current**: If leveling guides change between patches, the
  curated import strings in `leveling-builds.json` need manual updates

## Implementation Order

1. Collect community leveling import strings for all 39 specs → `leveling-builds.json`
2. Write `generate-leveling.ts` — parse imports, topological sort, output Lua
3. Write `Leveling.lua` — detection, banner UI, auto-purchase
4. Test in-game with a leveling character
5. Add to CI pipeline
