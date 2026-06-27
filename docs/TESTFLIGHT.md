# TestFlight — fully automated, no Mac

The native app builds, signs, and ships to TestFlight entirely on GitHub's macOS
CI runners (`testflight` job in `.github/workflows/ci.yml`, driven by
`fastlane/Fastfile`). Your Linux/Windows machines never touch it: you push to
`main`, the cloud does the rest, and the build shows up in the TestFlight app on
your phone.

The pipeline is **dormant** until you do the one-time Apple setup below and set
`TESTFLIGHT_ENABLED=true`. Until then the job is skipped and `main` stays green.

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
Create an empty **private** GitHub repo, e.g. `comeback-certs`. fastlane stores the
encrypted distribution certificate + provisioning profile there and CI fetches
them each run. You never generate certs by hand.

Create a **fine-grained PAT** (or classic PAT with `repo`) that can read/write
that certs repo. CI authenticates to it via `MATCH_GIT_BASIC_AUTHORIZATION` =
`base64("<github-username>:<PAT>")` (no newline), e.g.:
`printf 'madhakish:ghp_xxx' | base64`

### 4. (App record) — optional
The pipeline runs fastlane `produce` to create the App ID + App Store Connect
record automatically on first run. You can also create it by hand in App Store
Connect with bundle id `com.comeback.Comeback` if you prefer.

## Configure the repo

**Settings → Secrets and variables → Actions.**

Repository **variables**:
| Name | Value |
|------|-------|
| `TESTFLIGHT_ENABLED` | `true` |
| `APP_IDENTIFIER` | `com.comeback.Comeback` (or your own reverse-DNS id) |

Repository **secrets**:
| Name | Value |
|------|-------|
| `DEVELOPER_TEAM_ID` | your 10-char Team ID |
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | API Issuer ID |
| `ASC_KEY_CONTENT` | the full contents of the `.p8` file (paste as-is) |
| `MATCH_GIT_URL` | HTTPS URL of the private certs repo |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("user:PAT")` for that repo |
| `MATCH_PASSWORD` | a passphrase you choose (encrypts the certs) |

## Run it
Push anything to `main` (or re-run the latest CI). The `testflight` job will
`xcodegen generate` → `match` (creating the cert on first run) → build a signed
Release archive with a TestFlight-incremented build number → upload. In a few
minutes the build appears in **App Store Connect → TestFlight** and the
**TestFlight app** on your phone (install TestFlight from the App Store, sign in
with the same Apple ID).

Builds last **90 days**; every push to `main` ships a fresh one, so it never
expires in practice.

## Notes / first-run gotchas
- First run with `match` must be able to **create** the cert (don't pre-set
  `readonly`). Apple allows a limited number of distribution certs per account; if
  you hit the cap, revoke an unused one in the Developer portal.
- The in-app version shown is `MARKETING_VERSION` in `project.yml` (static today);
  the build *number* auto-increments from TestFlight. Bump `MARKETING_VERSION`
  when you want the displayed version to change.
- This is signing/registration work that can only be exercised with a real Apple
  account, so expect to iterate on the first run via the Actions logs (same
  "CI is the compiler" loop we use for the app build).
- Going from TestFlight to a public **App Store** release later is one extra
  fastlane lane (`deliver`) plus Apple's review — not needed for personal use.
