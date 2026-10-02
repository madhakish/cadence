#!/usr/bin/env node
// Public-surface parity between CadenceCore and web/app/js for the modules in
// docs/reference/parity-map.json.
//
// Fails when: a public Swift symbol is absent from the map; a map entry names a
// Swift symbol that no longer exists; a mapped JS twin is not exported; a JS
// export the module owns (its whole file, or its `jsSections` of a file several
// modules share) is neither any module's twin nor listed in webOnly; a
// swiftOnly/webOnly entry has no reason. It checks names, not behaviour: shared fixtures and the
// invariant registry own behaviour.
//
// Deliberately dependency-free, like check-invariants.mjs: a regex and
// brace-depth scan that fits this codebase's formatting, not a parser.
// usage: node check-parity.mjs [repo-root] [map-path]
import { readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.argv[2] ?? new URL("../../", import.meta.url).pathname;
const MAP = process.argv[3] ?? join(ROOT, "docs/reference/parity-map.json");

const stripStrings = (line) =>
  line.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/\/\/.*$/, "");

// Public types, initialisers, static members, instance funcs, computed vars,
// typealiases and enum cases. Funcs and inits are keyed by selector with
// external labels, so overloads and relabels are distinct. Stored instance
// properties are kind "field".
function swiftSymbols(path) {
  const lines = readFileSync(path, "utf8").split("\n");
  const out = [];
  const stack = []; // {name, depth, isEnum, isPublic, publicMembers}
  let depth = 0;
  let inBlockComment = false;
  lines.forEach((raw, i) => {
    let line = raw;
    if (inBlockComment) {
      if (!line.includes("*/")) return;
      line = line.slice(line.indexOf("*/") + 2);
      inBlockComment = false;
    }
    if (line.includes("/*") && !line.includes("*/")) inBlockComment = true;
    const owner = stack.length ? stack[stack.length - 1] : null;
    const qual = (n) => (owner ? `${owner.name}.${n}` : n);
    let code = stripStrings(line);
    // A member of a `public extension` is public unless it says otherwise.
    if (owner?.publicMembers && depth === owner.depth + 1 && !/^\s*(?:public|internal|fileprivate|private)\b/.test(code)) code = `public ${code.trimStart()}`;
    let m;
    if ((m = /^\s*(public\s+)?(?:final\s+)?(enum|struct|class|protocol|extension)\s+([A-Za-z_][\w.]*)/.exec(code))) {
      const name = m[3];
      const isExtension = m[2] === "extension"; // extends a type; declares none
      if (m[1] && !isExtension) out.push({ key: qual(name), kind: m[2], line: i + 1 });
      // Types open their brace on the declaration line in this codebase.
      if (code.includes("{")) stack.push({ name: isExtension ? name : qual(name), depth, isEnum: m[2] === "enum", isPublic: !!m[1] || isExtension, publicMembers: !!m[1] && isExtension });
    } else if ((m = /^\s*public\s+(?:static\s+|nonisolated\s+|mutating\s+)*(?:(func|let|var)\s+([A-Za-z_]\w*)|(init)[?!]?\s*[(<])/.exec(code))) {
      const isStatic = /\bstatic\b/.test(code);
      let kind = m[1] ?? m[3];
      if (!isStatic && kind !== "func" && kind !== "init") {
        const computed = kind === "var" && /^[^=]*:\s*[^={]+\{/.test(code); // `var x: T {` with no `=` before the brace
        kind = computed ? "computed" : "field";
      }
      let key = m[2] ?? m[3];
      if (kind === "func" || kind === "init") {
        // The parameter list may span lines; keep each parameter's external label.
        let text = lines.slice(i, i + 12).map(stripStrings).join(" ");
        text = text.slice(text.indexOf("(", text.indexOf(kind)));
        let bal = 0, end = 0;
        for (; end < text.length; end++) { if (text[end] === "(") bal++; else if (text[end] === ")" && --bal === 0) break; }
        const params = text.slice(1, end).split(/,(?![^<\[(]*[>\])])/).map((p) => p.trim()).filter(Boolean);
        key = `${key}(${params.map((p) => `${p.split(":")[0].trim().split(/\s+/)[0]}:`).join("")})`;
      }
      out.push({ key: qual(key), kind: (isStatic ? "static " : "") + kind, line: i + 1 });
    } else if ((m = /^\s*public\s+typealias\s+(\w+)/.exec(code))) {
      out.push({ key: qual(m[1]), kind: "typealias", line: i + 1 });
    } else if (owner?.isEnum && owner.isPublic && (m = /^\s*case\s+([^:(]+?)\s*(?:$|=|\()/.exec(code)) && depth === owner.depth + 1) {
      for (const c of m[1].split(",").map((s) => s.trim().split(/\s|=/)[0]).filter(Boolean)) {
        out.push({ key: `${owner.name}.${c}`, kind: "case", line: i + 1 });
      }
    }
    for (const ch of code) {
      if (ch === "{") depth += 1;
      else if (ch === "}") {
        depth -= 1;
        while (stack.length && depth <= stack[stack.length - 1].depth) stack.pop();
      }
    }
  });
  return out;
}

// export function/const/let/class and export { a, b as c }, each keyed to the
// `// ---- Section ----` header it sits under.
function jsExports(path) {
  const out = new Map();
  let section = "";
  for (const line of readFileSync(path, "utf8").split("\n")) {
    let m;
    if ((m = /^\/\/ -{4} (.+?) -{2,}\s*$/.exec(line))) {
      section = m[1];
    } else if ((m = /^export\s+(?:async\s+)?(?:function\*?|const|let|var|class)\s+([A-Za-z_$][\w$]*)/.exec(line))) {
      out.set(m[1], section);
    } else if ((m = /^export\s*\{([^}]*)\}/.exec(line))) {
      for (const part of m[1].split(",").map((s) => s.trim()).filter(Boolean)) out.set(part.split(/\s+as\s+/).pop(), section);
    }
  }
  return out;
}

// Stored fields and enum cases are values, which fixtures pin; v1 maps
// behaviour. Inits are in scope: one that only assigns stored fields is listed
// swiftOnly in the map, so a new init with logic cannot arrive unmapped.
const IN_SCOPE = (s) => s.kind !== "field" && s.kind !== "case";
const map = JSON.parse(readFileSync(MAP, "utf8"));

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures += 1; };
let checked = 0;

// JS sections do not follow Swift file boundaries one for one, so a twin that
// any module claims accounts for the export in whichever owned section it
// sits. Keyed by file: the same name in another JS file is a different export.
const twinned = new Set();
for (const spec of Object.values(map.modules)) {
  for (const value of Object.values(spec.symbols)) {
    const twin = typeof value === "string" ? value : value.js;
    if (twin) twinned.add(`${spec.js}#${twin}`);
  }
}

for (const [mod, spec] of Object.entries(map.modules)) {
  const swift = new Map(swiftSymbols(join(ROOT, spec.swift)).filter(IN_SCOPE).map((s) => [s.key, s]));
  const exports = jsExports(join(ROOT, spec.js));
  const claimed = new Set();

  for (const [key, sym] of swift) {
    if (!(key in spec.symbols)) fail(`${mod}: public Swift ${key} (${spec.swift}:${sym.line}) is not in the parity map`);
  }
  for (const [key, value] of Object.entries(spec.symbols)) {
    checked += 1;
    if (!swift.has(key)) fail(`${mod}: map entry ${key} matches no public Swift symbol in ${spec.swift}`);
    if (typeof value === "object" && "swiftOnly" in value) {
      if (!String(value.swiftOnly).trim()) fail(`${mod}: ${key} is swiftOnly without a reason`);
      continue;
    }
    const twin = typeof value === "string" ? value : value.js;
    if (!twin) { fail(`${mod}: ${key} has neither a JS twin nor swiftOnly`); continue; }
    if (!exports.has(twin)) fail(`${mod}: ${key} -> ${twin}, but ${spec.js} does not export ${twin}`);
    claimed.add(twin);
  }
  for (const [name, reason] of Object.entries(spec.webOnly ?? {})) {
    if (!exports.has(name)) fail(`${mod}: webOnly ${name} is not exported by ${spec.js}`);
    if (!String(reason).trim()) fail(`${mod}: webOnly ${name} has no reason`);
    claimed.add(name);
  }
  // A module owns its whole JS file unless it names the sections it owns; an
  // empty `jsSections` owns none (its twins sit in sections other modules own).
  const present = new Set(exports.values());
  for (const section of spec.jsSections ?? []) {
    if (!present.has(section)) fail(`${mod}: ${spec.js} has no exports under a "// ---- ${section} ----" header`);
  }
  for (const [name, section] of exports) {
    if (spec.jsSections && !spec.jsSections.includes(section)) continue;
    if (!claimed.has(name) && !twinned.has(`${spec.js}#${name}`)) fail(`${mod}: ${spec.js} exports ${name}, which is neither a Swift twin nor webOnly`);
  }
}

console.log(`parity: ${Object.keys(map.modules).length} modules, ${checked} mapped Swift symbols, ${failures} failing`);
if (failures) {
  console.error("\nAdd the symbol to docs/reference/parity-map.json with its twin, or mark it swiftOnly/webOnly with a reason.");
  process.exit(1);
}
