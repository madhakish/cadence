# TestFlight — fully automated, no Mac

The native app builds, signs, and ships to TestFlight entirely on GitHub's macOS
CI runners (`testflight` job in `.github/workflows/ci.yml`, driven by
`fastlane/Fastfile`). Your Linux/Windows machines never touch it: you push to
`main`, the cloud does the rest, and the build shows up in the TestFlight app on
your phone.

The pipeline requires the one-time Apple setup below. Once semantic-release
publishes a tag, TestFlight must upload it; missing Apple or signing
configuration fails the workflow visibly instead of silently skipping it.

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

For the **first run only** (when `match` must *create* the cert + profiles) you
need write access: temporarily use a Contents **read-and-write** fine-grained
PAT and set the repo variable `MATCH_READONLY=false`. Once the certs exist in
the repo, delete that variable and swap the secret back to a read-only PAT.

### 4. Register the App ID + app record (one-time, ~3 min)
Two quick browser steps (more reliable than doing it headless):
1. **Developer portal → Certificates, IDs & Profiles → Identifiers → +** →
   App IDs → App → description "Cadence", Bundle ID **explicit**
   `com.madhakish.Cadence`, and tick **HealthKit** under Capabilities. Register.
2. **App Store Connect → Apps → + → New App** → iOS, name "Cadence", the
   bundle id above, SKU `cadence`, your primary language. Create.

The **rest Live Activity** ships in an embedded widget extension with its own
App ID, `com.madhakish.Cadence.Widgets`. `fastlane match` (while
`MATCH_READONLY=false` during first-run provisioning) will register it and mint
its profile on the next CI run — but if your App Store Connect API key can't
create identifiers, register it by hand too:
**Identifiers → + → App IDs → App**, explicit Bundle ID
`com.madhakish.Cadence.Widgets`, no extra capabilities. (No separate ASC *app
record* — the extension ships inside the Cadence app.)

(`fastlane match` then makes the signing cert + profiles for both App IDs
automatically on the first CI run.)

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
validation jobs pass, semantic-release creates the version tag and the
`testflight` job runs `xcodegen generate` → `match` → signed Release archive →
upload. Non-release commits such as `docs:` and `ci:` do not waste time creating
duplicate TestFlight builds.

If a release tag was created but its upload failed or never started, run the
**CI** workflow manually on `main` with `force_testflight=true`. That explicit
recovery option uploads the latest existing release tag even when the manual
run does not create another release. Set `full_migrations=true` only when you
also need to force regeneration/verification of every shipped-store upgrade
path.

The build then appears in **App Store Connect → TestFlight** and the
**TestFlight app** on your phone (install TestFlight from the App Store and sign
in with the same Apple ID). Builds last **90 days**.

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
