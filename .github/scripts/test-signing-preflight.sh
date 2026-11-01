#!/usr/bin/env bash
# Regression tests for the signing contract. Each case is a failure that
# reached main on 2026-10-31 and was only found 25+ minutes into a release run.
set -euo pipefail

cd "$(dirname "$0")/../.."
scripts=".github/scripts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- static coverage: check-signing-coverage.rb ----------------------------

ruby "$scripts/check-signing-coverage.rb" >/dev/null || fail "coverage must pass on the real project"

expect_coverage_failure() {
  local label="$1" message="$2" project="$3" fastfile="$4" matchfile="$5" out
  if out="$(ruby "$scripts/check-signing-coverage.rb" "$project" "$fastfile" "$matchfile" 2>&1)"; then
    fail "coverage: $label should fail"
  fi
  [[ "$out" == *"$message"* ]] || fail "coverage: $label should report '$message', got: $out"
}

# A new embedded target the Fastfile does not sign (a third App ID added to
# project.yml alone).
ruby -ryaml -e '
  y = YAML.load_file("project.yml")
  y["targets"]["CadenceIntents"] = { "type" => "app-extension", "platform" => "iOS",
    "settings" => { "base" => { "PRODUCT_BUNDLE_IDENTIFIER" => "com.madhakish.Cadence.Intents" } } }
  y["targets"]["Cadence"]["dependencies"] << { "target" => "CadenceIntents" }
  File.write(ARGV[0], y.to_yaml)' "$work/project-new-target.yml"
expect_coverage_failure "unsigned embedded target" "does not sign com.madhakish.Cadence.Intents" \
  "$work/project-new-target.yml" fastlane/Fastfile fastlane/Matchfile

# The watch App ID dropped from match.
sed 's/app_identifier: \[APP_ID, WIDGET_ID, WATCH_ID\]/app_identifier: [APP_ID, WIDGET_ID]/' fastlane/Fastfile > "$work/Fastfile-no-watch"
expect_coverage_failure "watch missing from match" "Fastfile match does not sign com.madhakish.Cadence.watchkitapp" \
  project.yml "$work/Fastfile-no-watch" fastlane/Matchfile

# The watch App ID dropped from the Matchfile.
grep -v 'watchkitapp' fastlane/Matchfile | sed 's/\.Widgets", # Live/.Widgets" # Live/' > "$work/Matchfile-no-watch"
expect_coverage_failure "watch missing from Matchfile" "Matchfile app_identifier does not sign com.madhakish.Cadence.watchkitapp" \
  project.yml fastlane/Fastfile "$work/Matchfile-no-watch"

# #350: MATCH_READONLY read after setup_ci, so provisioning stayed read-only.
ruby -e '
  s = File.read("fastlane/Fastfile")
  read = s[/^    match_readonly = .*\n/] or abort "fixture: match_readonly line not found"
  s = s.sub(read, "").sub("    setup_ci\n", "    setup_ci\n" + read)
  File.write(ARGV[0], s)' "$work/Fastfile-late-readonly"
expect_coverage_failure "MATCH_READONLY read after setup_ci" "before setup_ci" \
  project.yml "$work/Fastfile-late-readonly" fastlane/Matchfile

# match pointed straight at the protected certs branch (no provisioning branch).
sed 's/git_branch: provision_branch || CERTS_BRANCH/git_branch: CERTS_BRANCH/' fastlane/Fastfile > "$work/Fastfile-direct-push"
expect_coverage_failure "provisioning pushes to the protected branch" "git_branch: provision_branch || CERTS_BRANCH" \
  project.yml "$work/Fastfile-direct-push" fastlane/Matchfile

# The certs branch left to match's default (master).
grep -v '^git_branch(' fastlane/Matchfile > "$work/Matchfile-no-branch"
expect_coverage_failure "Matchfile without git_branch" 'git_branch("main") is required' \
  project.yml fastlane/Fastfile "$work/Matchfile-no-branch"
sed 's/^git_branch("main")/git_branch("master")/' fastlane/Matchfile > "$work/Matchfile-master"
expect_coverage_failure "Matchfile on master" 'git_branch("main") is required' \
  project.yml fastlane/Fastfile "$work/Matchfile-master"

# --- live preflight: check-signing-material.rb with canned responses -------

all_paths='["certs/distribution/ABC.cer","certs/distribution/ABC.p12",
  "profiles/appstore/AppStore_com.madhakish.Cadence.mobileprovision",
  "profiles/appstore/AppStore_com.madhakish.Cadence.Widgets.mobileprovision",
  "profiles/appstore/AppStore_com.madhakish.Cadence.watchkitapp.mobileprovision"]'
no_watch_paths='["certs/distribution/ABC.cer",
  "profiles/appstore/AppStore_com.madhakish.Cadence.mobileprovision",
  "profiles/appstore/AppStore_com.madhakish.Cadence.Widgets.mobileprovision"]'
all_ids='["com.madhakish.Cadence","com.madhakish.Cadence.Widgets","com.madhakish.Cadence.watchkitapp"]'

write_fixture() { # name repo_status push(true|false) tree_paths asc_status asc_body [pulls_status]
  local tree
  tree="$(ruby -rjson -e 'puts({ "tree" => JSON.parse(ARGV[0]).map { |p| { "path" => p } } }.to_json)' "$4")"
  printf '{"certs_repo":{"status":%s,"body":{"permissions":{"pull":true,"push":%s}}},"certs_pulls":{"status":%s,"body":{}},"certs_tree":{"status":200,"body":%s},"asc_bundle_ids":{"status":%s,"body":%s}}\n' \
    "$2" "$3" "${7:-200}" "$tree" "$5" "$6" > "$work/$1.json"
}

bundle_ids() { ruby -rjson -e 'puts({ "data" => JSON.parse(ARGV[0]).map { |i| { "attributes" => { "identifier" => i } } } }.to_json)' "$1"; }

run_preflight() { # fixture readonly(true|false) [mode]
  env -i PATH="$PATH" HOME="$HOME" \
    MATCH_GIT_URL="https://github.com/example/certs.git" MATCH_GIT_BASIC_AUTHORIZATION="Zm9vOmJhcg==" \
    MATCH_READONLY="$([[ "$2" == true ]] && echo true || echo false)" \
    ASC_KEY_ID=K ASC_ISSUER_ID=I ASC_KEY_CONTENT=C SIGNING_PREFLIGHT="${3:-required}" \
    SIGNING_HTTP_FIXTURES="$work/$1.json" ruby "$scripts/check-signing-material.rb"
}

expect_pass() { # label fixture readonly [expected-text]
  local out
  out="$(run_preflight "$2" "$3" 2>&1)" || fail "preflight: $1 should pass, got: $out"
  [[ -z "${4:-}" || "$out" == *"$4"* ]] || fail "preflight: $1 should report '$4', got: $out"
}

expect_fail() { # label fixture readonly expected-text
  local out
  if out="$(run_preflight "$2" "$3" 2>&1)"; then fail "preflight: $1 should fail"; fi
  [[ "$out" == *"$4"* ]] || fail "preflight: $1 should report '$4', got: $out"
}

write_fixture ok 200 false "$all_paths" 200 "$(bundle_ids "$all_ids")"
expect_pass "everything in place" ok true "Signing preflight passed"

# A wrong token pasted into MATCH_GIT_BASIC_AUTHORIZATION.
write_fixture bad-token 401 false "$all_paths" 200 "$(bundle_ids "$all_ids")"
expect_fail "invalid certs token" bad-token true "cannot read example/certs (HTTP 401)"

# The watch App ID shipped before its profile existed, while match was read-only.
write_fixture no-watch-profile 200 false "$no_watch_paths" 200 "$(bundle_ids "$all_ids")"
expect_fail "missing watch profile, read-only" no-watch-profile true \
  "no App Store provisioning profile for com.madhakish.Cadence.watchkitapp. Read-only match cannot create it"

# The same gap is fine on a provisioning run with a write token...
write_fixture provision 200 true "$no_watch_paths" 200 "$(bundle_ids "$all_ids")"
expect_pass "provisioning run creates the profile" provision false "this provisioning run will create it"

# ...but not with a read-only token, where match cannot push what it creates.
write_fixture provision-ro-token 200 false "$no_watch_paths" 200 "$(bundle_ids "$all_ids")"
expect_fail "provisioning run without a write token" provision-ro-token false "cannot write to example/certs"

# Provisioning lands by pull request; a token without PR access cannot land it.
write_fixture provision-no-pulls 200 true "$no_watch_paths" 200 "$(bundle_ids "$all_ids")" 403
expect_fail "provisioning run without pull request access" provision-no-pulls false "cannot use pull requests"

# Apple's new Program License Agreement, not yet accepted by the Account Holder.
write_fixture pla 200 false "$all_paths" 403 \
  '{"errors":[{"code":"FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED","detail":"PLA Update available - the Account Holder must agree to the latest Program License Agreement"}]}'
expect_fail "unaccepted Apple agreement" pla true "Account Holder accepts the latest agreement"

write_fixture bad-key 200 false "$all_paths" 401 '{"errors":[{"code":"NOT_AUTHORIZED","detail":"Authentication credentials are missing or invalid."}]}'
expect_fail "revoked App Store Connect key" bad-key true "App Store Connect key was refused (HTTP 401"

write_fixture unregistered 200 false "$all_paths" 200 \
  "$(bundle_ids '["com.madhakish.Cadence","com.madhakish.Cadence.Widgets"]')"
expect_fail "watch App ID not registered" unregistered true "App ID com.madhakish.Cadence.watchkitapp is not registered"
# match cannot register an App ID even on a provisioning run.
write_fixture unregistered-provision 200 true "$no_watch_paths" 200 \
  "$(bundle_ids '["com.madhakish.Cadence","com.madhakish.Cadence.Widgets"]')"
expect_fail "unregistered App ID on a provisioning run" unregistered-provision false "match cannot register it"

# No credentials at all: a notice on fork/Dependabot PRs, a failure elsewhere.
out="$(env -i PATH="$PATH" HOME="$HOME" SIGNING_PREFLIGHT=optional ruby "$scripts/check-signing-material.rb" 2>&1)" \
  || fail "optional preflight without credentials should pass, got: $out"
[[ "$out" == *"skipped"* ]] || fail "optional preflight should say it skipped, got: $out"
if out="$(env -i PATH="$PATH" HOME="$HOME" SIGNING_PREFLIGHT=required ruby "$scripts/check-signing-material.rb" 2>&1)"; then
  fail "required preflight without credentials should fail"
fi
[[ "$out" == *"missing MATCH_GIT_BASIC_AUTHORIZATION"* ]] || fail "required preflight should name the missing secret, got: $out"

# --- provisioning lands by pull request: fastlane/certs_repo.rb -------------

ruby -e '
  load ARGV[0]
  calls = []
  responses = {
    [:get, "git/ref/heads/main"] => [200, { "object" => { "sha" => "abc123" } }],
    [:post, "git/refs"] => [201, {}],
    [:get, "compare/main...match/provision-7"] => [200, { "ahead_by" => 1 }],
    [:post, "pulls"] => [201, { "number" => 9, "html_url" => "https://github.com/o/certs/pull/9" }],
    [:put, "pulls/9/merge"] => [200, { "merged" => true }],
    [:delete, "git/refs/heads/match/provision-7"] => [422, { "message" => "Reference does not exist" }],
  }
  http = lambda do |verb, url, payload, auth|
    path = url.sub("https://api.github.com/repos/o/certs/", "")
    calls << [verb, path, payload]
    abort "auth #{auth}" unless auth == "Basic dTp0"
    responses.fetch([verb, path]) { abort "unexpected #{verb} #{path}" }
  end
  certs = CertsRepo.new(url: "https://github.com/o/certs.git", authorization: "dTp0", http: http)
  certs.start_branch("match/provision-7", base: "main")
  abort "branch not started from main head: #{calls[1]}" unless calls[1] == [:post, "git/refs", { "ref" => "refs/heads/match/provision-7", "sha" => "abc123" }]
  abort "not ahead" unless certs.ahead?("match/provision-7", base: "main")
  url = certs.merge_by_pull_request("match/provision-7", base: "main", title: "t", body: "b")
  abort "pr url #{url}" unless url == "https://github.com/o/certs/pull/9"
  pr = calls.find { |c| c[0] == :post && c[1] == "pulls" }
  abort "pr must target main from the branch: #{pr}" unless pr[2]["base"] == "main" && pr[2]["head"] == "match/provision-7"
  merge = calls.find { |c| c[1] == "pulls/9/merge" }
  abort "merge must rebase (linear history): #{merge}" unless merge[2] == { "merge_method" => "rebase" }
  certs.delete_branch("match/provision-7") # already deleted on merge: tolerated
  abort "never writes the default branch directly" if calls.any? { |c| c[1].include?("heads/main") && c[0] != :get }

  refused = CertsRepo.new(url: "https://github.com/o/certs.git", authorization: "dTp0",
                          http: ->(*) { [403, { "message" => "Resource not accessible by personal access token" }] })
  begin
    refused.merge_by_pull_request("b", base: "main", title: "t", body: "b")
    abort "a refused pull request must raise"
  rescue CertsRepo::Error => e
    abort "error must carry the HTTP status: #{e.message}" unless e.message.include?("HTTP 403")
  end
' fastlane/certs_repo.rb || fail "certs repo provisioning flow"

# The App Store Connect JWT is a valid ES256 signature over its header.payload.
openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$work/key.p8" 2>/dev/null
ruby -e '
  require "base64"; require "json"; require "openssl"
  load ARGV[0]
  pem = File.read(ARGV[1])
  token = SigningPreflight.new({ "SIGNING_PREFLIGHT" => "local" }, "project.yml")
                          .send(:asc_token, "KEY123", "issuer-uuid", Base64.strict_encode64(pem))
  header, payload, sig = token.split(".")
  pad = ->(s) { s + "=" * ((4 - s.length % 4) % 4) }
  h = JSON.parse(Base64.urlsafe_decode64(pad.(header)))
  p = JSON.parse(Base64.urlsafe_decode64(pad.(payload)))
  raw = Base64.urlsafe_decode64(pad.(sig))
  abort "header #{h}" unless h == { "alg" => "ES256", "kid" => "KEY123", "typ" => "JWT" }
  abort "payload #{p}" unless p["iss"] == "issuer-uuid" && p["aud"] == "appstoreconnect-v1" && p["exp"] - p["iat"] <= 1200
  abort "signature length #{raw.bytesize}" unless raw.bytesize == 64
  der = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(OpenSSL::BN.new(raw[0, 32], 2)),
                                 OpenSSL::ASN1::Integer(OpenSSL::BN.new(raw[32, 32], 2))]).to_der
  abort "signature does not verify" unless OpenSSL::PKey::EC.new(pem).verify(OpenSSL::Digest::SHA256.new, der, "#{header}.#{payload}")
' "$scripts/check-signing-material.rb" "$work/key.p8" || fail "App Store Connect JWT is not a valid ES256 token"

echo "Signing preflight tests passed"
