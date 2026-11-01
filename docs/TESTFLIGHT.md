# TestFlight — fully automated, no Mac

The native app builds, signs, and ships to TestFlight entirely on GitHub's macOS
CI runners (`store-build` and `testflight` in `.github/workflows/ci.yml`, driven
by `fastlane/Fastfile`). Your Linux/Windows machines never touch it: you push to
`main`, the cloud does the rest, and the build shows up in the TestFlight app on
your phone.

The pipeline requires the one-time Apple setup below. Once semantic-release
publishes a tag, the signed IPA has already been built, code-signature checked,
version checked, SHA-256 sealed, and retained as an immutable Actions artifact.
The GitHub release and TestFlight independently promote those exact bytes;
neither publisher contains a build step. Missing Apple or signing configuration
therefore fails before a version tag is created. An `uploads.github.com` outage
cannot suppress TestFlight.

## One-time setup (≈ 30–45 min, mostly waiting on Apple)

### 1. Apple Developer Program — $99/yr
Enroll at <https://developer.apple.com/programs/> (individual is fine). Activation
can take a few hours to ~2 days. Note your **Team ID** (Membership details — a
10-character string like `A1B2C3D4E5`).

### 2. App Store Connect API key (the credential that makes this headless)
App Store Connect → **Users and Access → Integrations → App Store Connect API →
Team Keys** → generate a key with the **App Manager** role. Save:
- **Issuer ID** (UUID at the top of the page)
- **Key ID** (the key's ID)
- the **`.p8` file** (downloadable once — keep it)

### 3. A private repo to hold signing certs (for fastlane match)
Create an empty **private** GitHub repo, e.g. `cadence-certs`. fastlane stores the
encrypted distribution certificate + provisioning profile there and CI fetches
them each run. You never generate certs by hand.

Create a **fine-grained PAT scoped to ONLY the certs repo** with **Contents:
read-only** access and an expiry — steady-state CI only ever *fetches* the
certs (`match` runs read-only by default; see the Matchfile), so the token in
CI can't rewrite your signing material even if a job is compromised. CI
authenticates via `MATCH_GIT_BASIC_AUTHORIZATION` =
`base64("<github-username>:<PAT>")` — with no newline anywhere, so strip the
trailing one `base64` emits:
`printf 'madhakish:github_pat_xxx' | base64 | tr -d '\n'`

The certs repo's default branch is `main` (the Matchfile sets
`git_branch("main")`; match would otherwise default to `master`). Protect it:
changes land only by pull request, with linear history.

For the **first run only** (when `match` must *create* the cert + profiles) you
need write access: temporarily use a fine-grained PAT with Contents and Pull
requests **read-and-write** and set the repo variable `MATCH_READONLY=false`.
Once the certs exist in the repo, delete that variable and swap the secret back
to a read-only PAT.

### 4. Register the App ID + app record (one-time, ~3 min)
Two quick browser steps (more reliable than doing it headless):
1. **Developer portal → Certificates, IDs & Profiles → Identifiers → +** →
   App IDs → App → description "Cadence", Bundle ID **explicit**
   `com.madhakish.Cadence`, and tick **HealthKit** under Capabilities. Register.
2. **App Store Connect → Apps → + → New App** → iOS, name "Cadence", the
   bundle id above, SKU `cadence`, your primary language. Create.

The **rest Live Activity** ships in an embedded widget extension with its own
App ID, `com.madhakish.Cadence.Widgets`. Register it by hand (match mints
profiles but never registers App IDs):
**Identifiers → + → App IDs → App**, explicit Bundle ID
`com.madhakish.Cadence.Widgets`, no extra capabilities. A provisioning run
(`MATCH_READONLY=false`) then mints its profile. (No separate ASC *app
record* — the extension ships inside the Cadence app.)

The **Apple Watch app** ships embedded in the iPhone app with its own App ID,
`com.madhakish.Cadence.watchkitapp` (explicit, **HealthKit** ticked). It needs a
`match` App Store profile like the other two; follow
[new App IDs](#signing-preflight-and-new-app-ids) so the profile exists before
anything depends on it. This is an owner action; routine CI stays read-only.

(`fastlane match` then makes the signing cert + profiles for all three App IDs
automatically on the first CI run.)

## Signing preflight and new App IDs

Every main run and manual dispatch runs the **Signing preflight** job
(`.github/scripts/check-signing-material.rb`) on Ubuntu right after the
repository preflight. In about a minute it proves what the signed build needs:
the certs token can read the certs repo, every App ID that ships in the app has
an App Store profile there, the App Store Connect key is accepted, Apple is not
blocking the account on an unaccepted agreement, and every App ID is registered
(match cannot register one). On a provisioning run (`MATCH_READONLY=false`) it
also proves the token can push a branch, by creating and deleting a scratch
branch, and can use pull requests. The signed build and the `App build (macOS)`
aggregate wait on it, so a broken token, a missing profile or a pending Program
License Agreement fails in a minute instead of 25 minutes into the release
build.

Signing secrets never reach pull-request code, so pull requests don't run the
live check. Run it yourself before pushing a signing change: `make signing`
(also the pre-push hook for `project.yml`, `fastlane/` and entitlements
changes) uses your `gh` login for the certs checks and runs the Apple checks
when `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_CONTENT` are exported.

The offline half (`check-signing-coverage.rb`, part of `make check` and the
CI preflight on every PR) keeps `project.yml`, the Fastfile and the Matchfile
in step: every embedded target is signed by `match`,
`update_code_signing_settings` and the export `provisioningProfiles`;
`build_beta` reads `MATCH_READONLY` before `setup_ci` forces it to true; the
certs branch is `main`; and provisioning goes through a branch and a PR.

To add a target with its own App ID (an extension, a watch app):

1. Register the App ID in the developer portal (**Identifiers → +**, explicit
   bundle ID, its capabilities). match cannot register App IDs; it stops with
   "Couldn't find bundle identifier". Then add the target to `project.yml` and
   its App ID to the Fastfile and Matchfile. `make check` fails until all three
   agree.
2. Open the PR. `make signing` reports "no App Store provisioning profile for
   …". Do not merge yet.
3. Set the repository variable `MATCH_READONLY=false` and give the certs token
   **Contents: Read and write** and **Pull requests: Read and write**.
4. Merge. The main run's Signing preflight confirms the token can push a branch
   and use pull requests, then the lane starts a `match/provision-<run>` branch
   from the certs repo's `main`, `match` writes the new profile there, and the
   lane lands it on `main` by pull request (rebase merge of exactly that
   commit), then fails the run if any profile is still missing. Nothing pushes
   to the protected `main` directly.
5. Once `make signing` passes, delete `MATCH_READONLY` and return the token to
   **Contents: Read-only**. The preflight then guards the steady state again.

## Configure the repo

**Settings → Secrets and variables → Actions.**

Repository **variables**:
| Name | Value |
|------|-------|
| `APP_IDENTIFIER` | `com.madhakish.Cadence` (or your own reverse-DNS id) |
| `MATCH_READONLY` | `false` **only during first-run provisioning** (with a read/write PAT), then delete — unset means read-only |

Repository **secrets**:
| Name | Value |
|------|-------|
| `DEVELOPER_TEAM_ID` | your 10-char Team ID |
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | API Issuer ID |
| `ASC_KEY_CONTENT` | **base64** of the `.p8` file — Linux/macOS: `base64 -w0 AuthKey_XXXX.p8` (macOS: `base64 -i AuthKey_XXXX.p8`); Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))` |
| `MATCH_GIT_URL` | HTTPS URL of the private certs repo |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("user:PAT")` for that repo |
| `MATCH_PASSWORD` | a passphrase you choose (encrypts the certs) |

## Run it
Merge a release-producing Conventional Commit to `main`. After the parallel
validation jobs pass, `store-build` runs `xcodegen generate` → `match` → signed
Release archive exactly once. CI verifies and caches that IPA, semantic-release
creates the version tag, and the `testflight` job downloads, re-verifies, and
uploads the cached file without compiling. The GitHub release receives the same
IPA and its checksum. Non-release commits such as `docs:` and `ci:` build no
release artifacts.

To exercise signing or Fastlane changes without creating a release, manually
dispatch **CI** on `main` with `verify_signed_artifact=true`. That path builds,
signs, verifies, and caches only the store IPA; it skips the simulator,
semantic-release, GitHub publishing, and TestFlight. It cannot be combined with
`force_testflight`.

The release tag is the durable handoff, not permission to build again. Rerun a
failed publishing job in the original workflow run so it reuses that run's
immutable artifact. A later whole-workflow recovery downloads the versioned IPA
and checksum already attached to the GitHub release.

If a release tag was created but its upload failed or never started, run the
**CI** workflow manually on `main` with `force_testflight=true`. That explicit
recovery option downloads and uploads the latest release's exact signed IPA; it
does not rebuild current `main` under an old version. If the GitHub release asset
itself is missing, rerun the failed publisher in the original release workflow
while its retained Actions artifact is available. Set `full_migrations=true`
only when you also need to force regeneration/verification of every
shipped-store upgrade path.

### Release queue

Every push to `main` and manual production dispatch joins the
`cadence-production-release` concurrency queue before validation begins. The
queue uses GitHub Actions' maximum pending depth, so a newer commit cannot
replace an older pending run after that run has already started working toward
a release. The semantic-release job also uses its own maximum-depth queue as a
second serialization boundary. GitHub currently caps a concurrency queue at
100 pending runs; if Cadence ever approaches that limit, stop merging and clear
the release backlog rather than accepting a skipped production candidate.

Queueing does not freeze the remote `main` branch. If another PR merges while
an older candidate builds, semantic-release can complete successfully but
decline to publish that older commit because it is behind remote `main`.
The reconciliation step reports the presence or absence of an exact release
tag; it cannot infer why an untagged candidate was not published. Check the
final combined head's release, asset-upload, and TestFlight jobs separately
from its test/build checks. A green validation run alone is not a new release.

The TestFlight upload lane does not wait for Apple's build processing. A
successful upload proves App Store Connect accepted the binary, not that it
has finished processing or is already visible to every tester.

The build then appears in **App Store Connect → TestFlight** and the
**TestFlight app** on your phone (install TestFlight from the App Store and sign
in with the same Apple ID). Builds last **90 days**.

## Recruiting testers

Uploading a build is not the same as letting anyone else install it. Two
audiences, and only one of them needs Apple's review:

- **Internal testers** — people on your App Store Connect team (currently up to
  100). They get every build immediately, with no review step. This is the right
  setting for you and anyone you'd add to the account.
- **External testers** — everyone else (currently up to 10,000). The *first build
  of each version* needs to pass **Beta App Review**, which is lighter than App
  Store review but not instant. Submit it from the build's page in TestFlight.

For external testing, prefer a **public link** over emailing invitations:
**TestFlight → your external group → Enable Public Link**. Apple hosts the
`https://testflight.apple.com/join/XXXXXXXX` page, so you never collect a
tester's email address — which matters for a project whose whole pitch is that it
doesn't collect anything. You can cap how many people the link admits.

Beta App Review will ask for a beta description, what to test, and a contact
email. Because the app declares HealthKit, say plainly that the toggle is
off by default and that Cadence only ever *writes* workouts and bodyweight.

**Then put the link on the site.** `web/ios.html` has a marked comment above the
"Ask for beta access" button in the *How to get in* card. Replace that button's
`href` with the public link and change its label to "Join the TestFlight beta".
Merging that to `main` redeploys Pages. Until the link exists the button opens a
pre-filled GitHub issue instead, so the page is never a dead end.

## Notes / first-run gotchas
- First run with `match` must be able to **create** the cert: set the repo
  variable `MATCH_READONLY=false` and use a read/write PAT for that run, then
  revert both (read-only is the default and the steady state). Apple allows a
  limited number of distribution certs per account; if you hit the cap, revoke
  an unused one in the Developer portal.
- The in-app marketing version comes from the semantic-release tag. The build
  number increments from TestFlight automatically; do not hand-edit either one
  for routine releases.
- This is signing/registration work that can only be exercised with a real Apple
  account, so expect to iterate on the first run via the Actions logs (same
  "CI is the compiler" loop we use for the app build).
- Going from TestFlight to a public **App Store** release later is one extra
  fastlane lane (`deliver`) plus Apple's review — not needed for personal use.
