/**
 * Fetch the ZUGZUG.io API and generate a Lua data file for the WoW addon.
 *
 * Usage:  npx tsx addon/scripts/update-data.ts
 *
 * Reads the live /api/data JSON and writes addon/ZugZug/Data.lua with all
 * builds for every class, role, difficulty, and key-level bucket — plus
 * per-build boss/dungeon "best for" context.
 */

import { writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ─── Config ─────────────────────────────────────────────────────────────────

// Use the worker URL directly — zugzug.info goes through Cloudflare Pages
// which has bot protection that blocks CI fetches.
const API_URL = "https://zugzug-cron.zugzugio.workers.dev/api/data";

// ─── Types (mirror shared/src/types.ts — kept minimal) ─────────────────────

interface Build {
  id: string;
  spec: string;
  hero: string;
  label: string;
  importString: string;
  popularity: number;
  trend: "new" | "up" | "down" | "flat";
}

interface BuildCard {
  label: string;
  spec: string;
  hero: string;
  description: string;
  importString: string;
}

type Difficulty = "heroic" | "mythic";
type KeyLevelBucket = "all" | "15+" | "18+" | "20+";

interface BossResult {
  name: string;
  bestBuildIndexByDifficulty: Record<Difficulty, number>;
}

interface DungeonResult {
  name: string;
  bestBuildIndexByBucket: Record<KeyLevelBucket, number>;
}

interface ClassData {
  color: string;
  raid: {
    builds: Build[];
    bosses: BossResult[];
  };
  mythicPlus: {
    cardsByBucket: Record<KeyLevelBucket, BuildCard[]>;
    builds: Build[];
    dungeons: DungeonResult[];
  };
}

type AllClassData = Record<string, ClassData>;

interface ApiResponse {
  lastUpdate: string;
  classes: AllClassData;
  healerClasses?: AllClassData;
  tankClasses?: AllClassData;
}

// ─── Class name → WoW class token mapping ───────────────────────────────────

const CLASS_TOKENS: Record<string, string> = {
  "Death Knight": "DEATHKNIGHT",
  "Demon Hunter": "DEMONHUNTER",
  Druid: "DRUID",
  Evoker: "EVOKER",
  Hunter: "HUNTER",
  Mage: "MAGE",
  Monk: "MONK",
  Paladin: "PALADIN",
  Priest: "PRIEST",
  Rogue: "ROGUE",
  Shaman: "SHAMAN",
  Warlock: "WARLOCK",
  Warrior: "WARRIOR",
};

// ─── Lua serialization ─────────────────────────────────────────────────────

function luaStr(s: string): string {
  return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}

function indent(depth: number): string {
  return "  ".repeat(depth);
}

/** Serialize a value into Lua table syntax. */
function toLua(value: unknown, depth = 0): string {
  if (value === null || value === undefined) return "nil";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return luaStr(value);

  if (Array.isArray(value)) {
    if (value.length === 0) return "{}";
    const lines = value.map((v) => `${indent(depth + 1)}${toLua(v, depth + 1)},`);
    return `{\n${lines.join("\n")}\n${indent(depth)}}`;
  }

  if (typeof value === "object") {
    const obj = value as Record<string, unknown>;
    const keys = Object.keys(obj);
    if (keys.length === 0) return "{}";
    const lines = keys.map((k) => {
      // Use bracket syntax for keys with special characters
      const luaKey = /^[a-zA-Z_]\w*$/.test(k) ? k : `[${luaStr(k)}]`;
      return `${indent(depth + 1)}${luaKey} = ${toLua(obj[k], depth + 1)},`;
    });
    return `{\n${lines.join("\n")}\n${indent(depth)}}`;
  }

  return "nil";
}

// ─── Build extraction ───────────────────────────────────────────────────────

interface AddonBuild {
  spec: string;
  hero: string;
  label: string;
  importString: string;
  popularity: number;
  trend: string;
  bosses?: string[];
  dungeons?: string[];
}

/**
 * Extract raid builds for a given difficulty, with "best for" boss context.
 * Skips the "other" bucket build.
 */
function extractRaidBuilds(
  classData: ClassData,
  difficulty: Difficulty,
): AddonBuild[] {
  const builds = classData.raid.builds.filter((b) => b.id !== "other" && b.importString);
  const bosses = classData.raid.bosses;

  return builds.map((build, buildIdx) => {
    // Which bosses is this build the best for at this difficulty?
    const bestFor = bosses
      .filter((boss) => boss.bestBuildIndexByDifficulty?.[difficulty] === buildIdx)
      .map((boss) => boss.name);

    return {
      spec: build.spec,
      hero: build.hero,
      label: build.label,
      importString: build.importString,
      popularity: Math.round(build.popularity),
      trend: build.trend,
      bosses: bestFor.length > 0 ? bestFor : undefined,
    };
  });
}

/**
 * Extract M+ builds for a given key-level bucket, with "best for" dungeon context.
 */
function extractMpBuilds(
  classData: ClassData,
  bucket: KeyLevelBucket,
): AddonBuild[] {
  const builds = classData.mythicPlus.builds.filter(
    (b) => b.id !== "other" && b.importString,
  );
  const dungeons = classData.mythicPlus.dungeons;

  return builds.map((build, buildIdx) => {
    const bestFor = dungeons
      .filter((dg) => dg.bestBuildIndexByBucket?.[bucket] === buildIdx)
      .map((dg) => dg.name);

    return {
      spec: build.spec,
      hero: build.hero,
      label: build.label,
      importString: build.importString,
      popularity: Math.round(build.popularity),
      trend: build.trend,
      dungeons: bestFor.length > 0 ? bestFor : undefined,
    };
  });
}

// ─── Role data assembly ─────────────────────────────────────────────────────

interface AddonRoleData {
  raid: Record<Difficulty, AddonBuild[]>;
  mythicPlus: Record<KeyLevelBucket, AddonBuild[]>;
}

function buildRoleData(classData: ClassData): AddonRoleData {
  return {
    raid: {
      heroic: extractRaidBuilds(classData, "heroic"),
      mythic: extractRaidBuilds(classData, "mythic"),
    },
    mythicPlus: {
      all: extractMpBuilds(classData, "all"),
      "15+": extractMpBuilds(classData, "15+"),
      "18+": extractMpBuilds(classData, "18+"),
      "20+": extractMpBuilds(classData, "20+"),
    },
  };
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Fetching ${API_URL} ...`);
  const res = await fetch(API_URL, {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new Error(`API returned ${res.status}: ${await res.text()}`);
  }
  const api = (await res.json()) as ApiResponse;
  console.log(`Got data, lastUpdate = ${api.lastUpdate}`);

  // Collect all role datasets: { classes → dps, healerClasses → healer, tankClasses → tank }
  const roleSources: { role: string; data: AllClassData | undefined }[] = [
    { role: "dps", data: api.classes },
    { role: "healer", data: api.healerClasses },
    { role: "tank", data: api.tankClasses },
  ];

  // Build per-class-token structure: TOKEN → { dps?, healer?, tank? }
  const result: Record<string, Record<string, AddonRoleData>> = {};

  for (const { role, data } of roleSources) {
    if (!data) continue;
    for (const [className, classData] of Object.entries(data)) {
      const token = CLASS_TOKENS[className];
      if (!token) {
        console.warn(`Unknown class name: ${className}, skipping`);
        continue;
      }

      // Skip classes with no builds at all
      const hasRaidBuilds = classData.raid.builds.some(
        (b) => b.id !== "other" && b.importString,
      );
      const hasMpBuilds = classData.mythicPlus.builds.some(
        (b) => b.id !== "other" && b.importString,
      );
      if (!hasRaidBuilds && !hasMpBuilds) {
        console.log(`  ${className} (${role}): no usable builds, skipping`);
        continue;
      }

      if (!result[token]) result[token] = {};
      result[token][role] = buildRoleData(classData);

      const raidCount = classData.raid.builds.filter(
        (b) => b.id !== "other" && b.importString,
      ).length;
      const mpCount = classData.mythicPlus.builds.filter(
        (b) => b.id !== "other" && b.importString,
      ).length;
      console.log(
        `  ${className} (${role}): ${raidCount} raid builds, ${mpCount} M+ builds`,
      );
    }
  }

  // Serialize to Lua
  const luaTable = {
    lastUpdate: api.lastUpdate,
    classes: result,
  };

  const lua = `-- Auto-generated by addon/scripts/update-data.ts\n-- Last update: ${api.lastUpdate}\n-- Do not edit by hand.\n\nZugZugData = ${toLua(luaTable, 0)}\n`;

  const __dirname = dirname(fileURLToPath(import.meta.url));
  const outPath = resolve(__dirname, "..", "Data.lua");
  writeFileSync(outPath, lua, "utf-8");
  console.log(`\nWrote ${outPath} (${(lua.length / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
