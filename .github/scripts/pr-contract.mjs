// The squash commit takes the PR title as its subject, and semantic-release
// reads that subject to choose the release. The title is the one thing this
// required check enforces; the body is free prose.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const TITLE = /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^()\r\n]+\))?!?: \S[^\r\n]*$/;

export function validatePullRequest(pr) {
  const errors = [];
  if (!TITLE.test(pr.title ?? '')) {
    errors.push('Use a Conventional Commit title, for example "fix(watch): keep the rest timer running". It becomes the squash subject and sets the release.');
  }
  return { errors };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  if (event.pull_request) {
    const { errors } = validatePullRequest(event.pull_request);
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('PR contract passed.');
  } else console.log('PR contract is not applicable to this event.');
}
