# Team notes

What earlier agents learned the hard way. One line each, newest at the bottom
of its section. Add a line in the PR where you learned it; delete a line when
it stops being true. Keep this file short enough to read every time.

## Workflow

- Agents share one GitHub account, so authorship cannot tell runs apart. The
  branch name and the PR are the identity.
- `AUTO_MERGE_TOKEN` is not set, so the auto-merge workflow skips. Run
  `gh pr merge <n> --squash --auto` yourself. A merge made with the workflow's
  own token would not start main CI (#299).
- Squash commits take the PR title as the subject and the PR body as the
  message. Template clutter ends up in git history; keep the body to prose.
- Never `git stash` in a shared checkout: the stash is shared by every
  worktree. Use a WIP commit on your own branch.

## CI and local checks

- `make check` is CI's preflight and the pre-commit hook. It needs Homebrew
  Ruby 3.2+; macOS's Ruby 2.6 accepts code CI rejects.
- Only paths in `.github/scripts/classify-ci-paths.sh` start native, migration
  or web jobs. Docs and most CI-script changes skip the macOS builds.
- Watch smoke tests take about 10 minutes in CI. Run `make native` locally
  only when watch or phone code changed.
- While main is red, release-producing PRs are held. Label a PR that fixes
  main `release-fix` (then push or reopen so the run sees the label).

## Signing and release

- Signing secrets never reach PR code. The live signing preflight runs on main
  and manual runs; locally, `make signing` checks targets, App IDs and
  entitlements before a push.
- fastlane match writes to the certs repo only through a PR against its
  `main` (`fastlane/certs_repo.rb`). Never point any tool at `master`.
- A release fix is proven by the main run reaching TestFlight, not by PR CI.

## Visuals

- Sep 16 shipped a photographic bar the owner loved; #248 swapped it for
  sprites four days later and it took #316 and a month to get back. Bar
  renderer changes need the side-by-side and sign-off AGENTS.md asks for.

## Tests

- UI-test fixtures should wait for a readiness signal, not a fixed delay. The
  watch fixture listens for a Darwin notification (#369); the WebKit
  service-worker test waits for the update event (#361).
