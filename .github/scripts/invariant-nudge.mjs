// Advisory nudge for pull requests that carry `fix:` commits without touching
// the invariant registry (#95). A fix encodes a rule that should not silently
// revert; the registry is where that rule has to argue with future changes.
// This never blocks a merge: it drafts one comment, updated in place, and the
// author either registers the rule or says why it is not one.
//
// Library: draftNudge({ commits, files }) → { fixes, registryTouched, comment }
// CLI:     echo '{"commits":[{"sha","message"}],"files":[]}' | node invariant-nudge.mjs
//          prints the comment body (empty output when no comment is needed).
import { readFileSync } from "node:fs";

export const MARKER = "<!-- invariant-nudge -->";
export const REGISTRY = "docs/reference/invariants.md";

const FIX_SUBJECT = /^fix(\([^)]*\))?!?:\s*(.+)$/;

function firstParagraph(body) {
  const paragraphs = body.split(/\n\s*\n/).map((p) => p.replace(/\s+/g, " ").trim()).filter(Boolean);
  const prose = paragraphs.find((p) => !/^(Refs|Closes|Fixes|Co-Authored-By|Claude-Session|BREAKING CHANGE)/i.test(p));
  return prose ?? "";
}

function ruleId(subject) {
  const words = subject.toLowerCase().replace(/[^a-z0-9 ]+/g, " ").split(/\s+/).filter(Boolean)
    .filter((w) => !["the", "a", "an", "of", "on", "in", "to", "for", "and", "its", "with", "from", "into", "never", "not", "when"].includes(w));
  return `INV-${words.slice(0, 4).join("-").toUpperCase() || "RULE"}`;
}

/// Commits whose subject is a Conventional Commit fix, with the subject and
/// the first prose paragraph of the body pulled out for the draft.
export function fixCommits(commits) {
  return commits.flatMap((commit) => {
    const [subjectLine, ...rest] = commit.message.split("\n");
    const match = subjectLine.match(FIX_SUBJECT);
    if (!match) return [];
    return [{ sha: commit.sha, subject: match[2].trim(), breaking: subjectLine.includes("!:"), rationale: firstParagraph(rest.join("\n")) }];
  });
}

export function draftNudge({ commits, files }) {
  const fixes = fixCommits(commits);
  const registryTouched = files.includes(REGISTRY);
  if (fixes.length === 0) return { fixes, registryTouched, comment: null };
  if (registryTouched) {
    return { fixes, registryTouched, comment: `${MARKER}\n**Invariant registry:** this PR carries ${fixes.length} fix commit${fixes.length === 1 ? "" : "s"} and updates \`${REGISTRY}\`. Nothing to do.` };
  }
  const list = fixes.map((fix) => `- \`${fix.sha.slice(0, 7)}\` ${fix.subject}`).join("\n");
  const drafts = fixes.map((fix) => [
    `### ${ruleId(fix.subject)}`,
    "*platforms: core | web | native — pick the ones the rule applies to*",
    "",
    fix.rationale ? `${fix.subject[0].toUpperCase()}${fix.subject.slice(1)}. ${fix.rationale}` : `${fix.subject[0].toUpperCase()}${fix.subject.slice(1)}.`,
    "",
    "What going wrong cost: _say what the old behaviour did to a lifter's log._",
  ].join("\n")).join("\n\n");
  return {
    fixes,
    registryTouched,
    comment: [
      MARKER,
      `**Invariant registry:** this PR carries ${fixes.length} fix commit${fixes.length === 1 ? "" : "s"} and does not touch \`${REGISTRY}\`.`,
      "",
      list,
      "",
      "If one of these encodes a rule that must not silently revert, register it and cite the ID from a test on every platform it names. If none is a rule (one-offs, typos, build fixes), reply saying so — this comment never blocks a merge.",
      "",
      "<details><summary>Draft entries (from the commit messages; the rationale is yours to write)</summary>",
      "",
      drafts,
      "",
      "</details>",
    ].join("\n"),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = JSON.parse(readFileSync(0, "utf8"));
  const { comment } = draftNudge({ commits: input.commits ?? [], files: input.files ?? [] });
  if (comment) process.stdout.write(comment);
}
