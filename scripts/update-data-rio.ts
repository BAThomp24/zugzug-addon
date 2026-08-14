/**
 * Generate DataRIO.lua from Raider.IO's spec-loadout statistics.
 *
 * Usage:  npx tsx scripts/update-data-rio.ts
 * Env:    RIO_SEASON  (default season-mn-1)    RIO_RAID (default tier-mn-1)
 *         RIO_EXPANSION (default 11)           SPEC_FILTER (debug: substring, e.g. "evoker")
 *
 * Sources:
 *  - raider.io internal /api/statistics/tier/talents (the /specs pages' data):
 *    per-spec build variants with import strings, run counts, key-level stats,
 *    RIO's recommendation verdicts, confidence tiers, and semantic themes.
 *    Queried per key bracket (all/15+/18+/20+ — matches the addon's existing
 *    keystoneToBucket), per dungeon×bracket (zone_id → per-dungeon top
 *    builds), and per raid difficulty. Non-default brackets are lazily
 *    materialized server-side ("generating") — a warm pass requests
 *    everything first, then the main pass polls until built.
 *  - raider.io documented /api/v1/mythic-plus/static-data: season dungeon ids.
 *  - Raidbots talents.json: spec list, talent-pool tags (class/spec/hero —
 *    RIO flattens trees so pools aren't derivable from its payload alone),
 *    and hero sub-tree names.
 *
 * Output schema mirrors Data.lua (classes[TOKEN][role].raid.{heroic,mythic} /
 * .mythicPlus[bucket] with the same build fields) so the addon can swap
 * sources through one accessor, plus RIO-only extensions per build:
 *   recommended, confidence, players, keyAvg, themes
 * and a spec-level per-dungeon top-build table (complete import strings —
 * NOT talent-delta "swaps"; deltas proved unapplyable when they crossed a
 * tree point-gate, e.g. Aug's Twin Guardian req23 funded by an above-gate
 * drop). The dungeon-entry popup recommends this build whole:
 *   ZugZugDataRIO.dungeonBuilds[TOKEN][role][specName][bucket][dungeonName] = Build
 */

import { writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const RIO = "https://raider.io";
// Resolved from RIO's own static data at startup unless pinned by env —
// a hardcoded season silently starves the dataset the moment Blizzard
// rolls one over (season-mn-1 → season-mn-2 on 2026-08-18), because
// every aggregate for a finished season decays to nothing.
let SEASON = process.env.RIO_SEASON || "";
let RAID = process.env.RIO_RAID || "";
/** ISO start of the resolved season — shipped so the addon can say "week 1". */
let SEASON_START = "";
const EXPANSION = Number(process.env.RIO_EXPANSION || 11);
const SPEC_FILTER = (process.env.SPEC_FILTER || "").toLowerCase();
const SCOPE = "last-3-resets";
const UA = "zugzug-addon data generator (github.com/BAThomp24/zugzug-addon; bathomp24@gmail.com)";

const PACE_MS = 700;
const MAX_BUILDS = 8;
const MIN_DUNGEON_SAMPLE = 100; // runs; below this a dungeon×bracket top build is noise

/** Buckets mirror Suggest.lua's keystoneToBucket exactly. */
const BRACKETS = [
  { key: "all", min: 10, max: 99 },
  { key: "15+", min: 15, max: 99 },
  { key: "18+", min: 18, max: 99 },
  { key: "20+", min: 20, max: 99 },
] as const;

// ─── tiny utils ───────────────────────────────────────────────────────────────

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const classToken = (className: string) => className.toUpperCase().replace(/[^A-Z]/g, "");

let lastFetch = 0;
async function rioFetch(url: string): Promise<any> {
  for (let attempt = 0; ; attempt++) {
    const wait = lastFetch + PACE_MS - Date.now();
    if (wait > 0) await sleep(wait);
    lastFetch = Date.now();
    const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "application/json" } });
    if (res.status === 429 && attempt < 2) {
      console.warn(`  429 — backing off 65s (${url.slice(0, 90)}…)`);
      await sleep(65_000);
      continue;
    }
    // Transient upstream hiccups (502/503/504) cost a whole spec when they
    // hit the overall aggregate — retry a couple of times before giving up.
    if (res.status >= 500 && attempt < 2) {
      console.warn(`  ${res.status} — retrying in 10s (${url.slice(0, 90)}…)`);
      await sleep(10_000);
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${url.slice(0, 120)}`);
    return res.json();
  }
}

// ─── Raidbots: spec list + talent pools + hero names ─────────────────────────

interface SpecDef {
  className: string;
  specName: string;
  specId: number;
  classSlug: string;
  specSlug: string;
  token: string;
}

interface PoolInfo {
  entryPool: Map<number, "class" | "spec" | "hero">;
  entryName: Map<number, string>;
  heroName: Map<number, string>; // traitSubTreeId → hero tree name
  trees: Map<number, TreeDef>; // specId → live tree shape (import-string fitness)
}

/**
 * The live shape of one spec's talent tree, straight from Raidbots'
 * `live` dump (which tracks the shipped build):
 *   order  — C_Traits.GetTreeNodes order; loadout strings are POSITIONAL
 *            against exactly this list
 *   owned  — the node IDs this spec may actually select
 *   nodes  — per-node rank/entry limits
 */
interface TreeDef {
  order: number[];
  owned: Set<number>;
  nodes: Map<number, { maxRanks: number; entries: number }>;
}

// ─── import-string fitness ────────────────────────────────────────────────────

const EXPORT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/** Blizzard's ExportUtil stream: 6 bits per character, LSB first. */
function bitReader(s: string) {
  const bits: number[] = [];
  for (const ch of s) {
    const v = EXPORT_CHARS.indexOf(ch);
    if (v < 0) continue;
    for (let i = 0; i < 6; i++) bits.push((v >> i) & 1);
  }
  let p = 0;
  return {
    total: bits.length,
    read(w: number) {
      let v = 0;
      for (let i = 0; i < w; i++) v |= (bits[p++] ?? 0) << i;
      return v;
    },
    pos: () => p,
    restNonZero() {
      for (let q = p; q < bits.length; q++) if (bits[q]) return true;
      return false;
    },
  };
}

/**
 * Why this exists: a loadout string identifies nothing about the nodes it
 * describes — bit n is node n of the tree, and every exporter (RIO
 * included) zeroes the 128-bit tree hash that would otherwise catch a
 * mismatch. When a patch reshapes a tree, yesterday's strings still
 * decode cleanly and silently select the WRONG talents from the first
 * changed node onward. Patch 12.1 reworked 40 specs and RIO kept serving
 * pre-patch strings for ten of them, which is how a build ended up
 * applying correctly "halfway through" and then wandering into other
 * specs' talents in-game.
 *
 * Returns null when the string fits the live tree, else a short reason.
 */
function importFitsTree(importString: string, specId: number, tree: TreeDef): string | null {
  const r = bitReader(importString);
  const version = r.read(8);
  if (version !== 2) return `loadout format v${version}`;
  const sid = r.read(16);
  if (sid !== specId) return `encodes spec ${sid}`;
  for (let i = 0; i < 16; i++) r.read(8); // tree hash (zeroed by exporters)

  let foreign = 0;
  let bad = 0;
  for (let i = 0; i < tree.order.length; i++) {
    if (r.pos() >= r.total) return `covers ${i} of ${tree.order.length} nodes (older, smaller tree)`;
    if (r.read(1) === 1) {
      let ranks: number | null = null;
      let choice: number | null = null;
      if (r.read(1) === 1) {
        if (r.read(1) === 1) ranks = r.read(6);
        if (r.read(1) === 1) choice = r.read(2);
      }
      const id = tree.order[i]!;
      if (!tree.owned.has(id)) {
        foreign++;
      } else {
        const meta = tree.nodes.get(id);
        if (meta) {
          if (ranks != null && ranks > meta.maxRanks) bad++;
          if (choice != null && choice >= meta.entries) bad++;
        }
      }
    }
  }
  if (foreign > 0) return `${foreign} node(s) belong to another spec (tree drift)`;
  if (bad > 0) return `${bad} out-of-range rank/choice`;
  if (r.restNonZero()) return "extra set bits past the tree (newer, larger tree)";
  return null;
}

async function loadRaidbots(): Promise<{ specs: SpecDef[]; pools: PoolInfo }> {
  console.log("Fetching Raidbots talents.json (pools + hero names)…");
  const res = await fetch("https://www.raidbots.com/static/data/live/talents.json", {
    headers: { "User-Agent": UA },
  });
  if (!res.ok) throw new Error(`raidbots ${res.status}`);
  const trees = (await res.json()) as any[];

  const specs: SpecDef[] = [];
  const entryPool = new Map<number, "class" | "spec" | "hero">();
  const entryName = new Map<number, string>();
  const heroName = new Map<number, string>();
  const treeDefs = new Map<number, TreeDef>();

  for (const t of trees) {
    if (!t.className || !t.specName || !t.specId) continue;
    if (Array.isArray(t.fullNodeOrder)) {
      const owned = new Set<number>();
      const nodes = new Map<number, { maxRanks: number; entries: number }>();
      for (const arr of [t.classNodes, t.specNodes, t.heroNodes, t.subTreeNodes]) {
        for (const n of arr ?? []) {
          owned.add(n.id);
          nodes.set(n.id, { maxRanks: n.maxRanks ?? 1, entries: (n.entries ?? []).length });
        }
      }
      treeDefs.set(t.specId, { order: t.fullNodeOrder, owned, nodes });
    }
    specs.push({
      className: t.className,
      specName: t.specName,
      specId: t.specId,
      classSlug: slug(t.className),
      specSlug: slug(t.specName),
      token: classToken(t.className),
    });
    const take = (nodes: any[] | undefined, pool: "class" | "spec" | "hero") => {
      for (const n of nodes ?? []) {
        for (const e of n.entries ?? []) {
          if (!e.id) continue;
          entryPool.set(e.id, pool);
          if (e.name) entryName.set(e.id, e.name);
          // Sub-tree selector entries name the hero tree they select.
          if (e.type === "subtree" && e.name && e.traitSubTreeId) heroName.set(e.traitSubTreeId, e.name);
        }
        if (n.subTreeId && n.name) heroName.set(n.subTreeId, n.name);
      }
    };
    take(t.classNodes, "class");
    take(t.specNodes, "spec");
    take(t.heroNodes, "hero");
    take(t.subTreeNodes, "hero");
  }
  console.log(`  ${specs.length} specs, ${entryPool.size} pooled entries, ${heroName.size} hero names,`
    + ` ${treeDefs.size} live trees`);
  return { specs, pools: { entryPool, entryName, heroName, trees: treeDefs } };
}

// ─── RIO static data: this season's dungeons ─────────────────────────────────

/** Started, not an event variant ("…-break-the-meta"), newest first. */
function pickCurrentSeason(seasons: any[]): any | undefined {
  const now = Date.now();
  return seasons
    .filter((s: any) => /^season-[a-z]+-\d+$/.test(s.slug ?? ""))
    .filter((s: any) => {
      const start = Date.parse(s.starts?.us ?? "");
      return Number.isFinite(start) && start <= now;
    })
    .sort((a: any, b: any) => Date.parse(b.starts.us) - Date.parse(a.starts.us))[0];
}

/** Raid tiers running right now; the combined "tier-*" slug wins. */
function pickCurrentRaid(raids: any[]): any | undefined {
  const now = Date.now();
  const live = raids
    .filter((r: any) => {
      const start = Date.parse(r.starts?.us ?? "");
      const end = Date.parse(r.ends?.us ?? "");
      return Number.isFinite(start) && start <= now && (!Number.isFinite(end) || end > now);
    })
    .sort((a: any, b: any) => Date.parse(b.starts.us) - Date.parse(a.starts.us));
  return live.find((r: any) => /^tier-/.test(r.slug ?? "")) ?? live[0];
}

async function resolveRaid(): Promise<void> {
  if (RAID) {
    console.log(`Raid tier pinned by RIO_RAID: ${RAID}`);
    return;
  }
  const j = await rioFetch(`${RIO}/api/v1/raiding/static-data?expansion_id=${EXPANSION}`);
  const raid = pickCurrentRaid(j.raids ?? []);
  if (!raid) throw new Error("no active raid tier in static-data — pin one with RIO_RAID");
  RAID = raid.slug;
  console.log(`Raid tier: ${RAID} (${raid.name}) — auto-detected`);
}

async function loadDungeons(): Promise<{ id: number; name: string }[]> {
  const j = await rioFetch(`${RIO}/api/v1/mythic-plus/static-data?expansion_id=${EXPANSION}`);
  let season = SEASON ? (j.seasons ?? []).find((s: any) => s.slug === SEASON) : pickCurrentSeason(j.seasons ?? []);
  if (!season) throw new Error(`season ${SEASON || "(auto)"} not in static-data`);
  SEASON_START = season.starts?.us ?? "";
  if (!SEASON) {
    SEASON = season.slug;
    console.log(`Season: ${SEASON} — auto-detected (started ${season.starts?.us})`);
  }
  const ds = (season.dungeons ?? []).map((d: any) => ({ id: d.id, name: d.name }));
  console.log(`Season ${SEASON}: ${ds.map((d: any) => d.name).join(", ")}`);
  return ds;
}

// ─── tier/talents fetches ─────────────────────────────────────────────────────

type AggParams = { bracket?: { min: number; max: number }; zoneId?: number; raidDifficulty?: string };

function aggUrl(spec: SpecDef, p: AggParams): string {
  const q = new URLSearchParams({ class: spec.classSlug, spec: spec.specSlug, scope: SCOPE });
  if (p.raidDifficulty) {
    q.set("raid", RAID);
    q.set("difficulty", p.raidDifficulty);
  } else {
    q.set("season", SEASON);
    q.set("minMythicLevel", String(p.bracket?.min ?? 10));
    q.set("maxMythicLevel", String(p.bracket?.max ?? 99));
    if (p.zoneId) q.set("zone_id", String(p.zoneId));
  }
  return `${RIO}/api/statistics/tier/talents?${q}`;
}

/** Fetch an aggregate; polls through server-side snapshot generation. */
async function fetchAgg(spec: SpecDef, p: AggParams, pollMs = 120_000): Promise<any | null> {
  const url = aggUrl(spec, p);
  const deadline = Date.now() + pollMs;
  for (;;) {
    let j: any;
    try {
      j = await rioFetch(url);
    } catch (err) {
      console.warn(`  agg failed: ${err}`);
      return null;
    }
    if (j?.data?.variants) return j.data;
    if (j?.status === "generating" || j?.status === "updating") {
      if (Date.now() > deadline) {
        console.warn(`  still ${j.status} after poll window: ${url.slice(0, 110)}…`);
        return null;
      }
      await sleep(8000);
      continue;
    }
    console.warn(`  unexpected agg response: ${JSON.stringify(j).slice(0, 120)}`);
    return null;
  }
}

// ─── build assembly ───────────────────────────────────────────────────────────

interface RioVariant {
  loadoutText: string;
  quantity: number;
  specId: number;
  heroSubTreeId: number;
  specHeroGroup?: { id?: string };
  mythicKeyLevel?: { avg?: number };
  chosenNodes?: any[];
  nerdStats?: any;
  recommendation?: any;
  semantics?: any;
}

const titleCase = (s: string) => s.replace(/\b[a-z]/g, (c) => c.toUpperCase());

/** "damage/passive" → "Passive Damage", "defensive/mitigation" → "Mitigation". */
function themeText(v: RioVariant): string {
  return (v.semantics?.profile?.dominantThemes ?? [])
    .slice(0, 2)
    .map((t: any) => {
      const cat = String(t.category ?? "").replace(/[-_]/g, " ");
      const sub = String(t.subtype ?? "").replace(/[-_]/g, " ");
      if (!sub || sub === cat) return titleCase(cat);
      return titleCase(cat === "damage" ? `${sub} damage` : sub);
    })
    .filter(Boolean)
    .join(" · ");
}

/** Entry-id set + metadata for a variant's chosen talents. */
function variantEntries(v: RioVariant): Map<number, { row: number }> {
  const out = new Map<number, { row: number }>();
  for (const cn of v.chosenNodes ?? []) {
    const e = cn.node?.entries?.[cn.entryIndex ?? 0];
    if (e?.id) out.set(e.id, { row: cn.node?.row ?? 0 });
  }
  return out;
}

/**
 * One identifying label per variant — the deepest spec-tree talent this
 * build takes that the fewest of its siblings take (RIO's semantic themes
 * are too uniform to identify builds: nearly everything is "passive damage
 * / mitigation"). Mirrors the zugzug pipeline's distinctive-talent labels.
 */
function distinctiveLabels(variants: RioVariant[], pools: PoolInfo): string[] {
  const sets = variants.map(variantEntries);
  return variants.map((v, i) => {
    let best: { name: string; row: number; shared: number; poolRank: number } | null = null;
    for (const [id, meta] of sets[i]!) {
      const name = pools.entryName.get(id);
      if (!name) continue;
      const pool = pools.entryPool.get(id);
      const poolRank = pool === "spec" ? 0 : pool === "hero" ? 1 : 2;
      let shared = 0;
      sets.forEach((s, j) => { if (j !== i && s.has(id)) shared++; });
      if (shared === sets.length - 1) continue; // everyone takes it — says nothing
      if (
        !best ||
        shared < best.shared ||
        (shared === best.shared && (poolRank < best.poolRank ||
          (poolRank === best.poolRank && meta.row > best.row)))
      ) {
        best = { name, row: meta.row, shared, poolRank };
      }
    }
    return best?.name ?? pools.heroName.get(v.heroSubTreeId) ?? "Standard";
  });
}

interface Build {
  spec: string;
  specId: number;
  hero: string;
  label: string;
  importString: string;
  popularity: number;
  trend: string;
  recommended?: boolean;
  confidence?: string;
  players?: number;
  keyAvg?: number;
  themes?: string;
  dungeons?: string[];
}

/** Every variant rejected by importFitsTree this run, for the summary. */
const dropped: { spec: string; why: string }[] = [];
/**
 * specId → the DISTINCT loadout strings withheld for that spec. Shipped
 * to the addon so an empty build list can say why it is empty ("RIO has
 * 5 builds for your spec, all exported before the talent change") rather
 * than looking like the addon lost its data.
 */
const withheldBySpec = new Map<number, Set<string>>();

function buildsFromAgg(
  spec: SpecDef,
  data: any,
  pools: PoolInfo,
  trendByLoadout: Map<string, string>,
): Build[] {
  const all: RioVariant[] = data.variants ?? [];
  // Drop anything that doesn't fit the live tree BEFORE ranking, so a
  // stale variant can't occupy one of the MAX_BUILDS slots. Popularity
  // shares stay computed over everything RIO listed — the percentages
  // describe what players ran, not what survived this filter.
  const tree = pools.trees.get(spec.specId);
  const variants = tree
    ? all.filter((v) => {
        const why = v.loadoutText ? importFitsTree(v.loadoutText, spec.specId, tree) : "no loadout";
        if (why) {
          dropped.push({ spec: `${spec.specName} ${spec.className}`, why });
          if (v.loadoutText) {
            let set = withheldBySpec.get(spec.specId);
            if (!set) { set = new Set(); withheldBySpec.set(spec.specId, set); }
            set.add(v.loadoutText);
          }
        }
        return !why;
      })
    : all;
  const listedTotal = all.reduce((s, v) => s + (v.quantity || 0), 0) || 1;
  const sorted = variants
    .slice()
    .sort((a, b) => {
      const ra = a.recommendation?.isRecommended ? 1 : 0;
      const rb = b.recommendation?.isRecommended ? 1 : 0;
      if (ra !== rb) return rb - ra;
      return (b.quantity || 0) - (a.quantity || 0);
    })
    .slice(0, MAX_BUILDS);

  const out: Build[] = [];
  const labels = distinctiveLabels(sorted, pools);
  const seenLabels = new Map<string, number>();
  for (const [idx, v] of sorted.entries()) {
    const label0 = labels[idx]!;
    const themes = themeText(v);
    // Duplicate labels get a distinguishing suffix (hero tree name).
    const n = (seenLabels.get(label0) ?? 0) + 1;
    seenLabels.set(label0, n);
    const hero = pools.heroName.get(v.heroSubTreeId) ?? "";
    out.push({
      spec: spec.specName,
      specId: spec.specId,
      hero,
      label: n === 1 ? label0 : `${label0} (${hero || n})`,
      importString: v.loadoutText,
      popularity: Math.max(1, Math.round(((v.quantity || 0) / listedTotal) * 100)),
      trend: trendByLoadout.get(v.loadoutText) ?? "flat",
      recommended: v.recommendation?.isRecommended === true || undefined,
      confidence: v.nerdStats?.popularity?.confidenceTier,
      players: v.nerdStats?.sample?.distinctCharacterCount,
      keyAvg: v.mythicKeyLevel?.avg != null ? Math.round(v.mythicKeyLevel.avg * 10) / 10 : undefined,
      themes: themes || undefined,
    });
  }
  return out;
}

// ─── trends from weekly popularity ────────────────────────────────────────────

async function fetchTrends(spec: SpecDef, loadouts: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (loadouts.length === 0) return out;
  try {
    const q = new URLSearchParams({
      season: SEASON,
      scope: SCOPE,
      minMythicLevel: "10",
      maxMythicLevel: "99",
      loadoutTexts: loadouts.join(","),
    });
    const j = await rioFetch(`${RIO}/api/spec-loadout/popularity?${q}`);
    for (const l of j.loadouts ?? []) {
      const weeks = l.weeklyPopularity ?? [];
      if (weeks.length < 2) continue;
      const cur = weeks[weeks.length - 1]?.usage ?? 0;
      const prev = weeks[weeks.length - 2]?.usage ?? 0;
      if (prev <= 0) { out.set(l.loadoutText, cur > 0 ? "up" : "flat"); continue; }
      const rel = (cur - prev) / prev;
      out.set(l.loadoutText, rel > 0.2 ? "up" : rel < -0.2 ? "down" : "flat");
    }
  } catch (err) {
    console.warn(`  trends failed: ${err}`);
  }
  return out;
}

// ─── Lua emission ─────────────────────────────────────────────────────────────

function luaStr(s: string): string {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}
function luaKey(k: string): string {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${luaStr(k)}]`;
}
function luaVal(v: any, indent: string): string {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(Math.round(v * 10) / 10);
  if (typeof v === "boolean") return String(v);
  if (typeof v === "string") return luaStr(v);
  if (Array.isArray(v)) {
    if (v.length === 0) return "{}";
    const inner = v.map((x) => `${indent}  ${luaVal(x, indent + "  ")},`).join("\n");
    return `{\n${inner}\n${indent}}`;
  }
  const keys = Object.keys(v).filter((k) => v[k] !== undefined);
  if (keys.length === 0) return "{}";
  const inner = keys.map((k) => `${indent}  ${luaKey(k)} = ${luaVal(v[k], indent + "  ")},`).join("\n");
  return `{\n${inner}\n${indent}}`;
}

// ─── main ─────────────────────────────────────────────────────────────────────

async function main() {
  const { specs, pools } = await loadRaidbots();
  const dungeons = await loadDungeons();
  await resolveRaid();

  const targets = specs.filter(
    (s) => !SPEC_FILTER || `${s.classSlug} ${s.specSlug}`.includes(SPEC_FILTER),
  );
  console.log(`Generating for ${targets.length} specs${SPEC_FILTER ? ` (filter: ${SPEC_FILTER})` : ""}`);

  // Warm pass: request every lazily-materialized aggregate once so the
  // server can build snapshots while we work through the main pass.
  // Dungeon×bracket aggregates are included — they're the bulk of the run.
  console.log("Warm pass (trigger snapshot generation)…");
  for (const spec of targets) {
    for (const b of BRACKETS.slice(1)) {
      try { await rioFetch(aggUrl(spec, { bracket: b })); } catch {}
    }
    for (const d of dungeons) {
      for (const b of BRACKETS) {
        try { await rioFetch(aggUrl(spec, { zoneId: d.id, bracket: b })); } catch {}
      }
    }
  }

  const classes: Record<string, Record<string, any>> = {};
  const dungeonBuilds: Record<string, Record<string, Record<string, any>>> = {};
  let ok = 0;
  const failed: string[] = [];

  for (const spec of targets) {
    const tag = `${spec.className}/${spec.specName}`;
    try {
      console.log(`── ${tag}`);
      const overall = await fetchAgg(spec, { bracket: BRACKETS[0] });
      if (!overall) throw new Error("no overall aggregate");
      const role: string = overall.spec?.role === "healing" ? "healer" : (overall.spec?.role ?? "dps");

      // Trends for the top loadouts (single batched call).
      const topLoadouts = (overall.variants ?? [])
        .slice()
        .sort((a: RioVariant, b: RioVariant) => (b.quantity || 0) - (a.quantity || 0))
        .slice(0, MAX_BUILDS)
        .map((v: RioVariant) => v.loadoutText);
      const trends = await fetchTrends(spec, topLoadouts);

      // M+ buckets
      const mythicPlus: Record<string, Build[]> = {};
      mythicPlus["all"] = buildsFromAgg(spec, overall, pools, trends);
      for (const b of BRACKETS.slice(1)) {
        const agg = await fetchAgg(spec, { bracket: b });
        if (agg) mythicPlus[b.key] = buildsFromAgg(spec, agg, pools, trends);
      }

      // Per-dungeon top builds (spec-level, one per key bucket) + per-build
      // "best dungeons" list. Complete import strings, not talent deltas —
      // the addon recommends and applies these whole.
      const specDungeonBuilds: Record<string, Record<string, Build>> = {}; // bucket → dungeonName → build
      const dungeonTopGroup = new Map<string, string>(); // dungeonName → top variant group id
      for (const d of dungeons) {
        for (const b of BRACKETS) {
          const agg = await fetchAgg(spec, { zoneId: d.id, bracket: b });
          if (!agg) continue;
          const total = (agg.variants ?? []).reduce((s: number, v: RioVariant) => s + (v.quantity || 0), 0);
          if (total < MIN_DUNGEON_SAMPLE) continue; // top-of-noise isn't a recommendation
          const top = buildsFromAgg(spec, agg, pools, new Map())[0];
          if (!top) continue;
          delete top.dungeons; // per-dungeon entry — the tag list is meaningless here
          (specDungeonBuilds[b.key] ??= {})[d.name] = top;
          if (b.key === "all") {
            const topV = (agg.variants ?? []).slice().sort((a: RioVariant, x: RioVariant) => (x.quantity || 0) - (a.quantity || 0))[0];
            if (topV?.specHeroGroup?.id) dungeonTopGroup.set(d.name, topV.specHeroGroup.id);
          }
        }
      }
      // Tag each "all" build with dungeons where it is the top group.
      const groupOf = new Map<string, string>();
      for (const v of overall.variants ?? []) {
        if (v.specHeroGroup?.id) groupOf.set(v.loadoutText, v.specHeroGroup.id);
      }
      for (const b of mythicPlus["all"]) {
        const g = groupOf.get(b.importString);
        const list = [...dungeonTopGroup.entries()].filter(([, gid]) => gid === g).map(([n]) => n);
        if (list.length) b.dungeons = list.sort();
      }

      // Raid difficulties
      const raid: Record<string, Build[]> = {};
      for (const diff of ["heroic", "mythic"]) {
        const agg = await fetchAgg(spec, { raidDifficulty: diff });
        if (agg) raid[diff] = buildsFromAgg(spec, agg, pools, new Map());
      }

      classes[spec.token] = classes[spec.token] ?? {};
      classes[spec.token][role] = classes[spec.token][role] ?? { raid: {}, mythicPlus: {} };
      const slot = classes[spec.token][role];
      // Merge: multiple specs share a class+role slot; builds lists append.
      for (const [k, v] of Object.entries(raid)) slot.raid[k] = [...(slot.raid[k] ?? []), ...v];
      for (const [k, v] of Object.entries(mythicPlus)) slot.mythicPlus[k] = [...(slot.mythicPlus[k] ?? []), ...v];

      if (Object.keys(specDungeonBuilds).length) {
        dungeonBuilds[spec.token] = dungeonBuilds[spec.token] ?? {};
        dungeonBuilds[spec.token][role] = dungeonBuilds[spec.token][role] ?? {};
        dungeonBuilds[spec.token][role][spec.specName] = specDungeonBuilds;
      }
      ok++;
    } catch (err) {
      console.warn(`  FAILED ${tag}: ${err}`);
      failed.push(tag);
    }
  }

  // Re-sort merged per-class lists (recommended first, then popularity).
  for (const cls of Object.values(classes)) {
    for (const roleData of Object.values(cls)) {
      for (const section of [roleData.raid, roleData.mythicPlus]) {
        for (const k of Object.keys(section)) {
          section[k].sort((a: Build, b: Build) =>
            (b.recommended ? 1 : 0) - (a.recommended ? 1 : 0) || b.popularity - a.popularity);
        }
      }
    }
  }

  console.log(`\n${ok}/${targets.length} specs OK${failed.length ? `; failed: ${failed.join(", ")}` : ""}`);
  if (!SPEC_FILTER && ok < targets.length * 0.75) {
    throw new Error(`only ${ok}/${targets.length} specs succeeded — refusing to write a degraded DataRIO.lua`);
  }

  // Tree-fitness summary. A spec listed here is one RIO is still serving
  // pre-patch loadout strings for; shipping those would apply the wrong
  // talents in-game, so they're simply absent until RIO re-exports.
  if (dropped.length) {
    const bySpec = new Map<string, { n: number; why: string }>();
    for (const d of dropped) {
      const e = bySpec.get(d.spec) ?? { n: 0, why: d.why };
      e.n++;
      bySpec.set(d.spec, e);
    }
    console.log(`\nDropped ${dropped.length} variant(s) that don't fit the live talent tree:`);
    for (const [spec, e] of [...bySpec.entries()].sort((a, b) => b[1].n - a[1].n)) {
      console.log(`  ${spec}: ${e.n} (${e.why})`);
    }
  } else {
    console.log("\nAll variants fit the live talent tree.");
  }

  const now = new Date().toISOString();
  const lua = [
    "-- Auto-generated by addon/scripts/update-data-rio.ts",
    `-- Source: Raider.IO spec statistics (raider.io/specs) — ${SEASON} / ${RAID}`,
    `-- Last update: ${now}`,
    "-- Do not edit by hand.",
    "",
    "ZugZugDataRIO = {",
    `  lastUpdate = ${luaStr(now)},`,
    `  source = "raider.io",`,
    `  season = ${luaStr(SEASON)},`,
    `  seasonStart = ${luaStr(SEASON_START)},`,
    // specId → how many DISTINCT builds RIO offered for that spec that
    // were withheld as unfittable. Drives the addon's empty-list copy.
    `  withheld = {${[...withheldBySpec.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([specId, set]) => ` [${specId}] = ${set.size},`)
      .join("")}${withheldBySpec.size ? " " : ""}},`,
    `  classes = ${luaVal(classes, "  ")},`,
    `  dungeonBuilds = ${luaVal(dungeonBuilds, "  ")},`,
    "}",
    "",
  ].join("\n");

  const outPath = resolve(dirname(fileURLToPath(import.meta.url)), "..", "DataRIO.lua");
  writeFileSync(outPath, lua, "utf-8");
  console.log(`Wrote ${outPath} (${(lua.length / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
