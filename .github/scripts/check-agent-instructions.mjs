// Intentionally bounded Markdown checks for the repository instruction files.
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

export const budgets = {
  'AGENTS.md': [200, 8192],
  'CLAUDE.md': [20, 1024],
  '.github/copilot-instructions.md': [40, 2048],
  'AGENT-COORDINATION.md': [120, 6144],
};
export const commonFiles = [...Object.keys(budgets), '.agents/torvalds-doctrine.md'];

function prose(text) {
  return text.replace(/<!--[\s\S]*?-->/g, '').replace(/^\s*(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\s*\1\s*$/gm, '');
}

export function anchors(text) {
  const seen = new Map();
  return new Set([...prose(text).matchAll(/^#{1,6}\s+(.+?)\s*#*\s*$/gm)].map((match) => {
    const slug = match[1].replace(/<[^>]*>/g, '').toLowerCase().replace(/[^\p{L}\p{N}_\-\s]/gu, '').replace(/\s/g, '-');
    const n = seen.get(slug) ?? 0;
    seen.set(slug, n + 1);
    return n ? `${slug}-${n}` : slug;
  }));
}

export function validateInstructions(root) {
  root = realpathSync(root);
  const errors = [], sizes = {}, texts = new Map(), imports = new Map();
  const inside = (path) => {
    const rel = relative(root, path);
    return !isAbsolute(rel) && rel !== '..' && !rel.startsWith(`..${sep}`);
  };
  function target(from, raw) {
    const [name, fragment] = raw.replace(/^<|>$/g, '').split('#');
    const path = resolve(root, dirname(from), decodeURIComponent(name || '.').replace(/\?.*$/, ''));
    const actual = name ? path : resolve(root, from);
    if (!inside(actual) || !existsSync(actual) || !inside(realpathSync(actual))) throw new Error(`missing or outside repository: ${raw}`);
    return [relative(root, actual).split(sep).join('/'), fragment && decodeURIComponent(fragment)];
  }
  function read(path) {
    if (!texts.has(path)) {
      const [safe] = target('.', path);
      texts.set(path, readFileSync(resolve(root, safe), 'utf8'));
    }
    return texts.get(path);
  }
  for (const path of commonFiles) {
    try {
      const text = read(path);
      sizes[path] = { lines: text ? text.split('\n').length - Number(text.endsWith('\n')) : 0, bytes: Buffer.byteLength(text) };
      const limit = budgets[path];
      if (limit && (sizes[path].lines > limit[0] || sizes[path].bytes > limit[1])) errors.push(`${path}: exceeds ${limit[0]} lines / ${limit[1]} bytes`);
    } catch (error) { errors.push(`${path}: ${error.message}`); }
  }
  const loaded = new Set(commonFiles);
  const pending = [...commonFiles, 'docs/AGENT-INSTRUCTIONS.md', 'docs/REPOSITORY-HYGIENE.md'];
  if (existsSync(resolve(root, 'docs/AGENT-GUIDE.md'))) pending.push('docs/AGENT-GUIDE.md');
  const checked = new Set();
  for (const path of pending) {
    if (checked.has(path)) continue;
    checked.add(path);
    try {
      const text = prose(read(path));
      const edges = [], destinations = new Set();
      const links = [...text.matchAll(/\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+["'][^)]*["'])?\)/g)].map(m => m[1]);
      links.push(...[...text.matchAll(/^\[[^\]\n]+\]:\s*(\S+)/gm)].map(m => m[1]));
      for (const raw of links) {
        if (/^(https?:|mailto:|\/\/)/i.test(raw)) continue;
        const [dest, fragment] = target(path, raw);
        destinations.add(dest);
        if (fragment && dest.endsWith('.md') && !anchors(read(dest)).has(fragment)) errors.push(`${path}: missing anchor ${raw}`);
      }
      const required = {
        'AGENTS.md': ['AGENT-COORDINATION.md', '.agents/torvalds-doctrine.md'],
        '.github/copilot-instructions.md': ['AGENTS.md', 'AGENT-COORDINATION.md', '.agents/torvalds-doctrine.md'],
      }[path] ?? [];
      for (const dest of required) if (!destinations.has(dest)) errors.push(`${path}: must link ${dest}`);
      for (const match of text.matchAll(/^@([^\s]+)\s*$/gm)) {
        const [dest] = target(path, match[1]);
        edges.push(dest);
        loaded.add(dest);
        pending.push(dest);
      }
      imports.set(path, edges);
    } catch (error) { errors.push(`${path}: ${error.message}`); }
  }
  const active = new Set(), visited = new Set();
  function visit(path) {
    if (active.has(path)) { errors.push(`Import cycle at ${path}`); return; }
    if (visited.has(path)) return;
    active.add(path);
    for (const dest of imports.get(path) ?? []) visit(dest);
    active.delete(path);
    visited.add(path);
  }
  for (const path of imports.keys()) visit(path);
  if (JSON.stringify([...(imports.get('CLAUDE.md') ?? [])].sort()) !== JSON.stringify(['AGENT-COORDINATION.md', 'AGENTS.md'])) {
    errors.push('CLAUDE.md must import AGENTS.md and AGENT-COORDINATION.md exactly once each');
  }
  const totalBytes = [...loaded].reduce((n, path) => n + Buffer.byteLength(texts.get(path) ?? ''), 0);
  if (totalBytes > 20480) errors.push('Common instructions including doctrine and automatic imports exceed 20480 bytes');
  return { errors, sizes, totalBytes, checkedFiles: checked.size };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = validateInstructions(process.cwd());
  console.log(JSON.stringify(result, null, 2));
  if (result.errors.length) process.exitCode = 1;
}
