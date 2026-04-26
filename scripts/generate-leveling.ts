/**
 * Generate leveling talent pick orders from curated import strings.
 *
 * Usage:  npx tsx scripts/generate-leveling.ts
 *
 * 1. Reads leveling-builds.json (curated import strings per spec)
 * 2. Fetches the Raidbots talent tree topology (nodes, positions, prereqs)
 * 3. Decodes each import string to find selected nodes
 * 4. Topologically sorts nodes by tree position + prerequisite chains
 * 5. Splits into class / spec / hero phases
 * 6. Writes LevelingData.lua
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ─── WoW Base64 import string decoding ──────────────────────────────────────

const B64_CHARS =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_LOOKUP: Record<string, number> = {};
for (let i = 0; i < 64; i++) B64_LOOKUP[B64_CHARS[i]!] = i;

const BITS_PER_CHAR = 6;

class ImportStream {
  private values: number[];
  private idx = 0;
  private extracted = 0;
  private remaining: number;

  constructor(b64: string) {
    this.values = [];
    for (let i = 0; i < b64.length; i++) {
      this.values.push(B64_LOOKUP[b64[i]!] ?? 0);
    }
    this.remaining = this.values[0] ?? 0;
  }

  extractValue(bitWidth: number): number {
    if (this.idx >= this.values.length) return 0;
    let value = 0;
    let bitsNeeded = bitWidth;
    let extractedBits = 0;

    while (bitsNeeded > 0) {
      const avail = BITS_PER_CHAR - this.extracted;
      const take = Math.min(avail, bitsNeeded);
      const mask = (1 << take) - 1;
      value += (this.remaining & mask) << extractedBits;
      this.remaining >>>= take;
      this.extracted += take;
      extractedBits += take;
      bitsNeeded -= take;

      if (take >= avail) {
        this.idx++;
        this.extracted = 0;
        this.remaining = this.values[this.idx] ?? 0;
      }
    }
    return value;
  }

  totalBits(): number {
    return this.values.length * BITS_PER_CHAR;
  }
}

interface DecodedNode {
  isSelected: boolean;
  isGranted: boolean;
  isPurchased: boolean;
  isPartiallyRanked: boolean;
  partialRanks: number;
  isChoiceNode: boolean;
  choiceEntryIndex: number;
}

function decodeImportString(b64: string): {
  specId: number;
  nodes: DecodedNode[];
} | null {
  const stream = new ImportStream(b64);
  if (stream.totalBits() < 152) return null; // header = 8+16+128

  const version = stream.extractValue(8);
  if (version !== 2) return null;

  const specId = stream.extractValue(16);
  for (let i = 0; i < 16; i++) stream.extractValue(8); // tree hash

  const nodes: DecodedNode[] = [];
  while (nodes.length < 400) {
    const selBit = stream.extractValue(1);
    const isSelected = selBit === 1;
    let isGranted = false;
    let isPurchased = false;
    let isPartiallyRanked = false;
    let partialRanks = 0;
    let isChoiceNode = false;
    let choiceEntryIndex = 0;

    if (isSelected) {
      const purchasedBit = stream.extractValue(1);
      isPurchased = purchasedBit === 1;
      isGranted = !isPurchased;

      if (isPurchased) {
        isPartiallyRanked = stream.extractValue(1) === 1;
        if (isPartiallyRanked) {
          partialRanks = stream.extractValue(6);
        }
        isChoiceNode = stream.extractValue(1) === 1;
        if (isChoiceNode) {
          choiceEntryIndex = stream.extractValue(2);
        }
      }
    }

    nodes.push({
      isSelected,
      isGranted,
      isPurchased,
      isPartiallyRanked,
      partialRanks,
      isChoiceNode,
      choiceEntryIndex,
    });
  }

  return { specId, nodes };
}

// ─── Raidbots tree types ────────────────────────────────────────────────────

interface RbEntry {
  id: number;
  name?: string;
  maxRanks: number;
  type?: string;
}

interface RbNode {
  id: number;
  posX: number;
  posY: number;
  type: "single" | "choice" | "tiered" | "subtree";
  maxRanks: number;
  entries: RbEntry[];
  next?: number[];
  prev?: number[];
  freeNode?: boolean;
  entryNode?: boolean;
}

interface RbTreeSpec {
  specId: number;
  classId: number;
  className: string;
  specName: string;
  classNodes: RbNode[];
  specNodes: RbNode[];
  heroNodes: RbNode[];
  subTreeNodes: RbNode[];
  fullNodeOrder: number[];
}

// ─── Leveling builds input ──────────────────────────────────────────────────

interface LevelingBuildInput {
  class: string;
  classToken: string;
  spec: string;
  importString: string;
}

interface LevelingBuildsFile {
  source: string;
  lastUpdated: string;
  specs: LevelingBuildInput[];
}

// ─── Topological sort ───────────────────────────────────────────────────────

interface PickNode {
  nodeID: number;
  name: string;
  posY: number;
  section: "class" | "spec" | "hero";
  ranks: number;
  maxRanks: number;
  choiceIndex?: number;
  prev: number[]; // prerequisite node IDs
}

/**
 * Gate rows: WoW requires spending N total points in a tree section before
 * nodes below certain posY thresholds unlock.
 *
 * Class tree gates (roughly):
 *   - Rows 1-4 (posY ~1800-3600): free (first 8 class points)
 *   - Gate 1 around posY ~4200: need 8 class points spent
 *   - Gate 2 around posY ~6600: need 20 class points spent
 *
 * Spec tree gates (roughly):
 *   - Gate 1 around posY ~4200: need 8 spec points spent
 *   - Gate 2 around posY ~6600: need 20 spec points spent
 *
 * These vary slightly by class. Instead of hardcoding exact thresholds,
 * we use a greedy approach: sort by posY and process top-to-bottom,
 * which naturally satisfies gate requirements. The prerequisite chains
 * (prev/next) handle the rest.
 */

function topologicalSortPicks(picks: PickNode[]): PickNode[] {
  if (picks.length === 0) return [];

  // Build adjacency: which picks must come before which
  const pickByNodeId = new Map<number, PickNode[]>();
  for (const p of picks) {
    const list = pickByNodeId.get(p.nodeID) ?? [];
    list.push(p);
    pickByNodeId.set(p.nodeID, list);
  }

  // Track which nodes are in the selected set
  const selectedNodeIds = new Set(picks.map((p) => p.nodeID));

  // Kahn's algorithm with posY-based priority
  // For multi-rank nodes, rank 1 must come before rank 2, etc.
  // We encode this by giving each rank an artificial sub-priority.

  // Expand into individual pick entries (one per rank)
  interface RankPick extends PickNode {
    rank: number; // 1-based rank within this node
  }

  const allRankPicks: RankPick[] = [];
  for (const p of picks) {
    for (let r = 1; r <= p.ranks; r++) {
      allRankPicks.push({ ...p, rank: r });
    }
  }

  // Build dependency graph on rank picks
  // Dependencies:
  // 1. prev nodes (any rank of the prerequisite must be fully purchased first)
  // 2. Same node rank ordering (rank N must come before rank N+1)
  const depCount = new Map<RankPick, number>();
  const dependents = new Map<RankPick, RankPick[]>();

  // Index rank picks by (nodeID, rank)
  const rankPickIndex = new Map<string, RankPick>();
  for (const rp of allRankPicks) {
    rankPickIndex.set(`${rp.nodeID}:${rp.rank}`, rp);
    depCount.set(rp, 0);
    dependents.set(rp, []);
  }

  function addDep(from: RankPick, to: RankPick) {
    dependents.get(from)!.push(to);
    depCount.set(to, (depCount.get(to) ?? 0) + 1);
  }

  for (const rp of allRankPicks) {
    // Same-node rank ordering: rank N-1 → rank N
    if (rp.rank > 1) {
      const prevRank = rankPickIndex.get(`${rp.nodeID}:${rp.rank - 1}`);
      if (prevRank) addDep(prevRank, rp);
    }

    // Prerequisite nodes: only rank 1 depends on prereqs
    if (rp.rank === 1) {
      for (const prevNodeId of rp.prev) {
        if (!selectedNodeIds.has(prevNodeId)) continue;
        // Depend on the last rank of the prerequisite node
        const prevPicks = pickByNodeId.get(prevNodeId);
        if (prevPicks && prevPicks.length > 0) {
          const prevNode = prevPicks[0]!;
          const lastRank = rankPickIndex.get(
            `${prevNodeId}:${prevNode.ranks}`,
          );
          if (lastRank) addDep(lastRank, rp);
        }
      }
    }
  }

  // Kahn's with posY + rank priority (lower posY first, then lower rank)
  const ready = allRankPicks.filter((rp) => depCount.get(rp) === 0);
  ready.sort((a, b) => a.posY - b.posY || a.rank - b.rank);

  const result: RankPick[] = [];

  while (ready.length > 0) {
    // Pick the node with lowest posY (highest in tree)
    ready.sort((a, b) => a.posY - b.posY || a.rank - b.rank);
    const current = ready.shift()!;
    result.push(current);

    for (const dep of dependents.get(current) ?? []) {
      const newCount = (depCount.get(dep) ?? 1) - 1;
      depCount.set(dep, newCount);
      if (newCount === 0) {
        ready.push(dep);
      }
    }
  }

  // Convert back to PickNode (one entry per rank pick)
  return result.map((rp) => ({
    nodeID: rp.nodeID,
    name: rp.name,
    posY: rp.posY,
    section: rp.section,
    ranks: 1, // each entry is one rank purchase
    maxRanks: rp.maxRanks,
    choiceIndex: rp.choiceIndex,
    prev: rp.prev,
  }));
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  const __dirname = dirname(fileURLToPath(import.meta.url));

  // 1. Read leveling builds
  const buildsPath = resolve(__dirname, "leveling-builds.json");
  const buildsFile: LevelingBuildsFile = JSON.parse(
    readFileSync(buildsPath, "utf-8"),
  );
  console.log(
    `Loaded ${buildsFile.specs.length} specs from leveling-builds.json`,
  );

  // 2. Fetch raidbots talent tree data
  console.log("Fetching Raidbots talent tree data...");
  const rbUrl = "https://www.raidbots.com/static/data/live/talents.json";
  const rbRes = await fetch(rbUrl, {
    headers: {
      "User-Agent": "Mozilla/5.0 (compatible; zugzug-leveling/1.0)",
      Accept: "application/json",
    },
  });
  if (!rbRes.ok) throw new Error(`Raidbots fetch failed: ${rbRes.status}`);
  const rbData = (await rbRes.json()) as RbTreeSpec[];
  console.log(`Got ${rbData.length} spec trees from Raidbots`);

  // Index raidbots data by specId
  const treeBySpecId = new Map<number, RbTreeSpec>();
  for (const spec of rbData) {
    treeBySpecId.set(spec.specId, spec);
  }

  // Build node maps per spec: nodeId → full node data
  function buildFullNodeMap(
    spec: RbTreeSpec,
  ): Map<number, RbNode & { section: "class" | "spec" | "hero" }> {
    const map = new Map<
      number,
      RbNode & { section: "class" | "spec" | "hero" }
    >();
    for (const n of spec.classNodes ?? [])
      map.set(n.id, { ...n, section: "class" });
    for (const n of spec.specNodes ?? [])
      map.set(n.id, { ...n, section: "spec" });
    for (const n of [...(spec.heroNodes ?? []), ...(spec.subTreeNodes ?? [])])
      map.set(n.id, { ...n, section: "hero" });
    return map;
  }

  // 3. Process each spec
  interface LevelingOrder {
    nodeID: number;
    name: string;
    choiceIndex?: number;
  }

  interface SpecOutput {
    spec: string;
    label: string;
    importString: string;
    order: LevelingOrder[];
  }

  const output: Record<string, SpecOutput[]> = {};
  let totalProcessed = 0;
  let totalSkipped = 0;

  for (const build of buildsFile.specs) {
    if (!build.importString) {
      console.log(`  SKIP ${build.class} ${build.spec} — no import string`);
      totalSkipped++;
      continue;
    }

    // Decode import string
    const decoded = decodeImportString(build.importString);
    if (!decoded) {
      console.log(
        `  SKIP ${build.class} ${build.spec} — failed to decode import string`,
      );
      totalSkipped++;
      continue;
    }

    // Find the matching raidbots tree
    const rbSpec = treeBySpecId.get(decoded.specId);
    if (!rbSpec) {
      console.log(
        `  SKIP ${build.class} ${build.spec} — no Raidbots tree for specId ${decoded.specId}`,
      );
      totalSkipped++;
      continue;
    }

    const nodeMap = buildFullNodeMap(rbSpec);
    const fullNodeOrder = rbSpec.fullNodeOrder;

    // Map decoded nodes back to actual node data
    const picks: PickNode[] = [];
    let heroTreeName: string | undefined;

    for (let i = 0; i < fullNodeOrder.length && i < decoded.nodes.length; i++) {
      const dn = decoded.nodes[i]!;
      if (!dn.isSelected) continue;

      const nodeId = fullNodeOrder[i]!;
      const node = nodeMap.get(nodeId);
      if (!node) continue;

      // Skip granted (free) nodes — they don't cost talent points
      if (dn.isGranted) continue;

      // Determine name and choice
      let name: string;
      let choiceIndex: number | undefined;

      if (dn.isChoiceNode && node.entries.length > dn.choiceEntryIndex) {
        choiceIndex = dn.choiceEntryIndex;
        name = node.entries[dn.choiceEntryIndex]?.name ?? `Node ${nodeId}`;

        // Track hero tree selection from subtree nodes
        if (node.type === "subtree") {
          heroTreeName = name;
          continue; // subtree selection node isn't a talent pick
        }
      } else {
        name = node.entries[0]?.name ?? `Node ${nodeId}`;
      }

      const ranks = dn.isPartiallyRanked ? dn.partialRanks : node.maxRanks;

      picks.push({
        nodeID: nodeId,
        name,
        posY: node.posY,
        section: node.section,
        ranks,
        maxRanks: node.maxRanks,
        choiceIndex,
        prev: (node.prev ?? []).filter((id) => nodeMap.has(id)),
      });
    }

    // Sort by phase, then topologically within each phase
    const classPicks = picks.filter((p) => p.section === "class");
    const specPicks = picks.filter((p) => p.section === "spec");
    const heroPicks = picks.filter((p) => p.section === "hero");

    const sortedClass = topologicalSortPicks(classPicks);
    const sortedSpec = topologicalSortPicks(specPicks);
    const sortedHero = topologicalSortPicks(heroPicks);

    // Interleave class and spec picks like WoW actually awards points:
    // Level 10: 1 class point, Level 11: 1 spec point, Level 12: 1 class point, etc.
    // Pattern: alternating class/spec, starting with class at level 10
    const interleaved: PickNode[] = [];
    let ci = 0;
    let si = 0;
    let isClassTurn = true;

    while (ci < sortedClass.length || si < sortedSpec.length) {
      if (isClassTurn && ci < sortedClass.length) {
        interleaved.push(sortedClass[ci]!);
        ci++;
      } else if (!isClassTurn && si < sortedSpec.length) {
        interleaved.push(sortedSpec[si]!);
        si++;
      } else if (ci < sortedClass.length) {
        interleaved.push(sortedClass[ci]!);
        ci++;
      } else if (si < sortedSpec.length) {
        interleaved.push(sortedSpec[si]!);
        si++;
      }
      isClassTurn = !isClassTurn;
    }

    // Append hero picks after all class/spec (level 71+)
    const finalOrder = [...interleaved, ...sortedHero];

    // Build label
    const label = heroTreeName
      ? `Leveling — ${heroTreeName}`
      : `Leveling — ${build.spec}`;

    // Build output order
    const order: LevelingOrder[] = finalOrder.map((p) => {
      const entry: LevelingOrder = { nodeID: p.nodeID, name: p.name };
      if (p.choiceIndex !== undefined) entry.choiceIndex = p.choiceIndex;
      return entry;
    });

    if (!output[build.classToken]) output[build.classToken] = [];
    output[build.classToken]!.push({
      spec: build.spec,
      label,
      importString: build.importString,
      order,
    });

    const classCount = sortedClass.reduce((s, p) => s + 1, 0);
    const specCount = sortedSpec.reduce((s, p) => s + 1, 0);
    const heroCount = sortedHero.reduce((s, p) => s + 1, 0);
    console.log(
      `  ${build.class} ${build.spec}: ${classCount} class + ${specCount} spec + ${heroCount} hero = ${order.length} total picks`,
    );
    totalProcessed++;
  }

  console.log(
    `\nProcessed ${totalProcessed} specs, skipped ${totalSkipped}`,
  );

  // 4. Write LevelingData.lua
  const luaLines: string[] = [];
  luaLines.push(
    "-- Auto-generated by scripts/generate-leveling.ts",
  );
  luaLines.push(
    `-- Source: ${buildsFile.source} (${buildsFile.lastUpdated})`,
  );
  luaLines.push("-- Do not edit by hand.");
  luaLines.push("");
  luaLines.push("ZugZugLevelingData = {");

  const classTokens = Object.keys(output).sort();
  for (const token of classTokens) {
    const specs = output[token]!;
    luaLines.push(`  ${token} = {`);

    for (const spec of specs) {
      luaLines.push("    {");
      luaLines.push(`      spec = ${luaStr(spec.spec)},`);
      luaLines.push(`      label = ${luaStr(spec.label)},`);
      luaLines.push(`      importString = ${luaStr(spec.importString)},`);
      luaLines.push("      order = {");

      for (const pick of spec.order) {
        const parts = [`nodeID = ${pick.nodeID}`, `name = ${luaStr(pick.name)}`];
        if (pick.choiceIndex !== undefined) {
          parts.push(`choiceIndex = ${pick.choiceIndex}`);
        }
        luaLines.push(`        { ${parts.join(", ")} },`);
      }

      luaLines.push("      },");
      luaLines.push("    },");
    }

    luaLines.push("  },");
  }

  luaLines.push("}");
  luaLines.push("");

  const luaContent = luaLines.join("\n");
  const outPath = resolve(__dirname, "..", "LevelingData.lua");
  writeFileSync(outPath, luaContent, "utf-8");
  console.log(`\nWrote ${outPath} (${(luaContent.length / 1024).toFixed(1)} KB)`);
}

function luaStr(s: string): string {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
