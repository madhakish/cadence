// `make who`: who is working on what. Lists open pull requests with their
// branch, age and files, flags any that touch files this branch changes, and
// shows what merged recently. Read-only; needs `gh` signed in.
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function age(iso, now) {
  const hours = (now - Date.parse(iso)) / 3_600_000;
  if (hours < 1) return `${Math.max(0, Math.round(hours * 60))}m`;
  if (hours < 48) return `${Math.round(hours)}h`;
  return `${Math.round(hours / 24)}d`;
}

// Files this branch changes that an open PR (other than its own) also changes.
export function overlaps(mine, prs, branch) {
  const changed = new Set(mine);
  return prs
    .filter((pr) => pr.headRefName !== branch)
    .map((pr) => ({ number: pr.number, files: (pr.files ?? []).map((f) => f.path).filter((p) => changed.has(p)) }))
    .filter((o) => o.files.length);
}

export function report({ prs, merged, mine, branch, now }) {
  const lines = [];
  lines.push(prs.length ? `Open pull requests (${prs.length}):` : 'No open pull requests.');
  for (const pr of prs) {
    const files = (pr.files ?? []).map((f) => f.path);
    const shown = files.slice(0, 4).join(', ') + (files.length > 4 ? `, +${files.length - 4} more` : '');
    const mark = pr.headRefName === branch ? ' (this branch)' : '';
    lines.push(`  #${pr.number}${pr.isDraft ? ' draft' : ''}  ${age(pr.updatedAt, now)} ago  ${pr.headRefName}${mark}`);
    lines.push(`      ${pr.title}`);
    if (shown) lines.push(`      ${shown}`);
  }
  const hits = overlaps(mine, prs, branch);
  if (hits.length) {
    lines.push('', `Overlap with ${branch}:`);
    for (const hit of hits) lines.push(`  #${hit.number}: ${hit.files.join(', ')}`);
    lines.push('  Coordinate on that PR before you both edit these files.');
  } else if (mine.length) {
    lines.push('', `No open PR touches the ${mine.length} file(s) ${branch} changes.`);
  }
  if (merged.length) {
    lines.push('', 'Recently merged:');
    for (const pr of merged) lines.push(`  #${pr.number}  ${age(pr.mergedAt, now)} ago  ${pr.title}`);
  }
  return lines.join('\n');
}

function run(command, args) {
  return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const gh = (args) => JSON.parse(run('gh', args));
  const prs = gh(['pr', 'list', '--state', 'open', '--limit', '50', '--json', 'number,title,headRefName,isDraft,updatedAt,files']);
  const merged = gh(['pr', 'list', '--state', 'merged', '--limit', '5', '--json', 'number,title,mergedAt']);
  const branch = run('git', ['branch', '--show-current']);
  let mine = [];
  try {
    const base = run('git', ['merge-base', 'origin/main', 'HEAD']);
    mine = run('git', ['diff', '--name-only', base]).split('\n').filter(Boolean);
  } catch { /* no origin/main yet: nothing to compare */ }
  console.log(report({ prs, merged, mine, branch, now: Date.now() }));
}
