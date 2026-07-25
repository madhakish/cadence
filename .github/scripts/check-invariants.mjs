#!/usr/bin/env node
// Requirements traceability for docs/reference/invariants.md.
//
// The registry is the readable specification; this makes it enforceable. It
// checks that every rule is asserted by at least one test on every platform it
// claims, and that no test cites a rule that does not exist. A rule losing its
// coverage is how a fixed bug quietly comes back.
//
// Deliberately dependency-free and harness-agnostic: it greps for [INV-*]
// tokens, so Swift XCTest and the plain-node web assertions are treated alike
// and neither suite needs a framework it does not already have.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = new URL("../../", import.meta.url).pathname.replace(/\/$/, "");
const REGISTRY = join(ROOT, "docs/reference/invariants.md");
const TOKEN = /\[(INV-[A-Z0-9-]+)\]/g;

// Where each platform's assertions live.
const SOURCES = {
  core: ["CadenceCore/Tests/CadenceCoreTests", "web/tests"],
  web: ["web/tests"],
  native: ["CadenceMigrationTests", "CadenceCore/Tests/CadenceCoreTests"],
};

const walk = (dir) => {
  let out = [];
  let entries;
  try { entries = readdirSync(dir); } catch { return out; }
  for (const name of entries) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out = out.concat(walk(full));
    else if (/\.(mjs|js|swift)$/.test(name)) out.push(full);
  }
  return out;
};

// ---- parse the registry ----
const registry = readFileSync(REGISTRY, "utf8");
const rules = [];
const headingRe = /^### (INV-[A-Z0-9-]+)\s*$/gm;
let match;
while ((match = headingRe.exec(registry))) {
  const id = match[1];
  const rest = registry.slice(match.index + match[0].length);
  const meta = /^\s*\*platforms:\s*([^*]+)\*/m.exec(rest.split(/^### /m)[0]);
  if (!meta) {
    console.error(`FAIL ${id}: no *platforms:* line — every rule must say where it applies`);
    process.exitCode = 1;
    continue;
  }
  const raw = meta[1].trim();
  const unverifiable = /unverifiable/.test(raw);
  const platforms = raw.replace(/·.*/, "").split(",").map((p) => p.trim()).filter((p) => p && p !== "unverifiable");
  rules.push({ id, platforms, unverifiable });
}

if (!rules.length) {
  console.error("FAIL: no rules parsed from the registry — has its format changed?");
  process.exit(1);
}

// ---- collect citations ----
const citations = new Map(); // id -> Set(file)
const filesByPlatform = new Map();
for (const [platform, dirs] of Object.entries(SOURCES)) {
  const files = dirs.flatMap((d) => walk(join(ROOT, d)));
  filesByPlatform.set(platform, files);
  for (const file of files) {
    const text = readFileSync(file, "utf8");
    let m;
    TOKEN.lastIndex = 0;
    while ((m = TOKEN.exec(text))) {
      if (!citations.has(m[1])) citations.set(m[1], new Set());
      citations.get(m[1]).add(file);
    }
  }
}

// ---- check ----
const known = new Set(rules.map((r) => r.id));
let failures = 0;
let covered = 0;
let skipped = 0;

for (const rule of rules) {
  if (rule.unverifiable) {
    skipped += 1;
    continue;
  }
  for (const platform of rule.platforms) {
    const files = filesByPlatform.get(platform) || [];
    const cited = citations.get(rule.id) || new Set();
    const hit = [...cited].some((f) => files.includes(f));
    if (!hit) {
      console.error(`FAIL ${rule.id}: registered for "${platform}" but no test there cites it`);
      failures += 1;
    } else {
      covered += 1;
    }
  }
}

for (const [id, files] of citations) {
  if (!known.has(id)) {
    const where = [...files].map((f) => relative(ROOT, f)).join(", ");
    console.error(`FAIL ${id}: cited in ${where} but not registered in docs/reference/invariants.md`);
    failures += 1;
  }
}

const verified = rules.length - skipped;
console.log(
  `invariants: ${verified} enforced (${covered} platform assertions), ` +
  `${skipped} documented but unverifiable here, ${failures} failing`,
);
if (failures) {
  console.error("\nEvery rule in the registry must be asserted by a test, and every cited rule must be registered.");
  process.exit(1);
}
