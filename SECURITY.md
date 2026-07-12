# Security Policy

Cadence is a single-user, local-first workout tracker: the web PWA stores all
data in the browser's IndexedDB and the iOS app in on-device SwiftData. There
is no backend, no account system, and the app makes no network requests of its
own beyond loading its static assets from GitHub Pages.

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub private vulnerability reporting](https://github.com/madhakish/cadence/security/advisories/new)
rather than opening a public issue. You should receive a response within a few
days.

In scope, in rough order of impact:

- Anything that lets a crafted **backup file** (the import/restore bundle —
  the only untrusted input the apps parse) execute script, exfiltrate data, or
  trigger network requests.
- Cross-site scripting or cache poisoning in the deployed PWA
  (`web/`, served at `madhakish.github.io/cadence/`) or its service worker.
- Supply-chain issues in the CI/release pipeline
  (`.github/workflows/`, `fastlane/`).

## Supported versions

Only the latest release (and the live Pages deployment, which tracks `main`)
is supported.
