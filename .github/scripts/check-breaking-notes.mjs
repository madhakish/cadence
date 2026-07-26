#!/usr/bin/env node
// Guard against ACCIDENTAL major releases.
//
// v4.0.0 was cut for a change that broke nothing. A commit body explained that
// the new test asserts "...that a breaking change is called out in the body,
// and that no body collapses to a bare header" — and line wrapping happened to
// put `breaking change is called out...` at the START of a line. The
// conventional-commits parser matches its note keywords case-insensitively at
// line start, so ordinary prose became a BREAKING CHANGE footer, semantic-
// release cut a major, and the release notes quoted the sentence fragment back
// as the breaking change.
//
// In this repository a major means something specific and expensive: a
// persisted format that needs conversion, or an old binary that can no longer
// open new data. Spending one by accident tells every future reader to go
// looking for a migration that does not exist.
//
// So: any commit the analyzer grades `major` must SAY SO DELIBERATELY, in one
// of the two forms Conventional Commits defines for it —
//
//   feat!: ...            (or fix!:, feat(scope)!: ...)
//   BREAKING CHANGE: ...  (exact, uppercase, at the start of a footer line)
//
// Anything else grading major is prose that tripped the parser.
import { execFileSync } from "node:child_process";
import { analyzeCommits } from "../release/node_modules/@semantic-release/commit-analyzer/index.js";

const cwd = new URL("../release", import.meta.url).pathname;
const logger = { log() {}, error() {} };

// Deliberate markers. The footer form is deliberately case-SENSITIVE and
// requires the colon: that is the spelling the spec defines, and it is what
// separates an intention from a sentence.
const BANG_HEADER = /^[a-zA-Z]+(\([^)]*\))?!:/;
const EXPLICIT_FOOTER = /^BREAKING[ -]CHANGE:/m;

// %x1f separates hash from body, %x1e terminates each record: both are
// control characters git will never emit inside a commit message.
const FIELD = "\x1f";
const RECORD = "\x1e";

const range = process.argv[2];
if (!range) {
  console.error("usage: check-breaking-notes.mjs <git-range>   e.g. origin/main..HEAD");
  process.exit(2);
}

let raw;
try {
  raw = execFileSync("git", ["log", `--format=%H${FIELD}%B${RECORD}`, range], { encoding: "utf8" });
} catch (error) {
  console.error(`Could not read commits for range ${range}: ${error.message}`);
  process.exit(2);
}

const commits = raw
  .split(RECORD)
  .map((chunk) => chunk.trim())
  .filter(Boolean)
  .map((chunk) => {
    const at = chunk.indexOf(FIELD);
    return { hash: chunk.slice(0, at), message: chunk.slice(at + 1).trim() };
  })
  .filter((c) => c.hash && c.message);

if (!commits.length) {
  console.log("breaking-note guard: no commits in range, nothing to check");
  process.exit(0);
}

let failures = 0;
for (const commit of commits) {
  const type = await analyzeCommits(
    { preset: "conventionalcommits" },
    { cwd, commits: [{ message: commit.message, hash: commit.hash }], logger }
  );
  if (type !== "major") continue;

  const header = commit.message.split("\n")[0];
  if (BANG_HEADER.test(header) || EXPLICIT_FOOTER.test(commit.message)) continue;

  // Graded major without either marker: find the line that did it.
  const culprit = commit.message
    .split("\n")
    .find((line) => /^\s*breaking[ -]change/i.test(line));

  console.error(`\nFAIL ${commit.hash.slice(0, 8)} grades as a MAJOR release but never says so.`);
  console.error(`  ${header}`);
  if (culprit) console.error(`  tripped by: "${culprit.trim()}"`);
  console.error(
    "  A line beginning with \"breaking change\" is read as a footer even mid-sentence.\n" +
    "  If the change really is breaking, mark it with `!:` in the subject or an exact\n" +
    "  `BREAKING CHANGE:` footer. If it is not, reword so the phrase does not start a line."
  );
  failures += 1;
}

console.log(
  `breaking-note guard: ${commits.length} commit(s) checked, ${failures} accidental major(s)`
);
if (failures) {
  console.error(
    "\nA major release in this repository means a persisted format needs conversion or an\n" +
    "old binary cannot open new data. It must never be spent by accident."
  );
  process.exit(1);
}
