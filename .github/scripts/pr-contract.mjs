// Check metadata structure, not the truth of an author's verification claim.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function validatePullRequest(pr, repository) {
  const errors = [];
  if (!/^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^()\r\n]+\))?!?: \S[^\r\n]*$/.test(pr.title ?? '')) {
    errors.push('Use a Conventional Commit title, for example ci: validate repository instructions.');
  }
  // GitHub authenticates this bot identity; its generated update body is useful already.
  if (pr.user?.login === 'dependabot[bot]' && pr.user?.type === 'Bot') return { errors, task: null };
  const body = (pr.body ?? '').replace(/<!--[\s\S]*?-->/g, '').replace(/^\s*(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\s*\1\s*$/gm, '');
  const values = {};
  for (const field of ['Task', 'Scope', 'Verification']) {
    const matches = [...body.matchAll(new RegExp(`^${field}:[ \t]*([^\\r\\n]*)$`, 'gmi'))];
    const value = matches[0]?.[1].trim() ?? '';
    if (matches.length !== 1 || !value || /^(<.*>|tbd|todo|n\/?a|pending|none)$/i.test(value)) {
      errors.push(`Provide one ${field}: line with a task-specific value; include a reason for pending verification.`);
    }
    values[field] = value;
  }
  const reference = values.Task.match(/^(?:([\w.-]+\/[\w.-]+))?#([1-9]\d*)$/)
    ?? values.Task.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/([1-9]\d*)\/?$/);
  let task = null;
  if (reference) task = { repository: reference[1] || repository, number: Number(reference[2]) };
  else if (!/^none\s+[-—:]\s*\S.+/i.test(values.Task) || /^(?:none\s+[-—:]\s*)(?:<.*>|tbd|todo|n\/?a)$/i.test(values.Task)) {
    errors.push('Task must be #123, owner/repo#123, an issue URL, or none — <maintenance reason>.');
  }
  return { errors, task };
}

export async function checkTask(task, token, request = fetch) {
  const response = await request(`https://api.github.com/repos/${task.repository}/issues/${task.number}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Task issue could not be read (HTTP ${response.status}); check the reference and token access.`);
  if ((await response.json()).pull_request) throw new Error('Task points to a pull request; use its task issue or a reasoned maintenance exemption.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  if (event.pull_request) {
    const result = validatePullRequest(event.pull_request, process.env.GITHUB_REPOSITORY);
    if (result.errors.length) throw new Error(result.errors.join('\n'));
    if (result.task) await checkTask(result.task, process.env.GH_TOKEN);
    console.log('PR contract passed. Verification evidence still requires review.');
  } else console.log('PR contract is not applicable to this event.');
}
