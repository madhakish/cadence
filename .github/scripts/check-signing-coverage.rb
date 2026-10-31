#!/usr/bin/env ruby
# Static signing contract, checked offline in seconds (preflight, `make test`,
# pre-commit). Every target that ships inside the app must be signed by every
# piece of the release lane, and the first-run provisioning switch must work:
#
# - each embedded target has an explicit bundle ID under the app's;
# - Fastfile `match`, Matchfile, `update_code_signing_settings` and the export
#   `provisioningProfiles` all cover exactly that set of App IDs;
# - build_beta reads MATCH_READONLY before `setup_ci` forces it to true, and
#   passes it to `match` (the #350 regression: provisioning silently stayed
#   read-only, so a new App ID could never get its profile).
#
# Usage: ruby check-signing-coverage.rb [project.yml] [Fastfile] [Matchfile]
#        ruby check-signing-coverage.rb --list   # print the App IDs
require_relative "signing-targets"

list_only = ARGV.delete("--list")
project_path, fastfile_path, matchfile_path = ARGV
project_path ||= "project.yml"
fastfile_path ||= "fastlane/Fastfile"
matchfile_path ||= "fastlane/Matchfile"

targets = SigningTargets.shippable(project_path)
if list_only
  targets.each { |t| puts "#{t.name} #{t.bundle_id}" }
  exit 0
end

errors = []
app = targets.first
app_id = app.bundle_id
errors << "project.yml: #{app.name} has no PRODUCT_BUNDLE_IDENTIFIER" if app_id.to_s.empty?
targets.drop(1).each do |t|
  if t.bundle_id.to_s.empty?
    errors << "project.yml: embedded target #{t.name} has no PRODUCT_BUNDLE_IDENTIFIER"
  elsif !t.bundle_id.start_with?("#{app_id}.")
    errors << "project.yml: #{t.name} bundle ID #{t.bundle_id} must sit under #{app_id} (Fastfile derives it from APP_ID)"
  end
end
expected = targets.map(&:bundle_id).compact

fastfile = File.read(fastfile_path)
matchfile = File.read(matchfile_path)

# Resolve the Fastfile's `NAME_ID = ...` constants to concrete App IDs.
default_app = '(?:ENV\["APP_IDENTIFIER"\]\s*\|\|\s*)?"([^"]+)"'
constants = {}
fastfile.scan(/^([A-Z_]+_ID)\s*=\s*(.+)$/) do |name, expr|
  value = expr.strip
  if (m = value.match(/\A"\#\{([A-Z_]+)\}(\.[^"]+)"\z/))
    constants[name] = constants[m[1]] && constants[m[1]] + m[2]
  elsif (m = value.match(/\A#{default_app}\z/))
    constants[name] = m[1]
  end
end
resolve = lambda do |names, where|
  names.map do |n|
    constants[n] || (errors << "Fastfile #{where}: cannot resolve #{n}"; nil)
  end.compact
end
same_set = lambda do |label, actual|
  missing = expected - actual
  extra = actual - expected
  errors << "#{label} does not sign #{missing.join(', ')}" unless missing.empty?
  errors << "#{label} signs #{extra.join(', ')}, which project.yml does not ship" unless extra.empty?
end

lane = fastfile[/^  lane :build_beta do\n(.*?)^  end$/m, 1]
# Comments mention setup_ci and MATCH_READONLY too; judge the code alone.
lane &&= lane.lines.reject { |l| l.strip.start_with?("#") }.join
if lane.nil?
  errors << "Fastfile: build_beta lane not found"
else
  match_call = lane[/match\((.*?)\)\s*$/m, 1].to_s
  ids = match_call[/app_identifier:\s*\[([^\]]*)\]/, 1]
  if ids.nil?
    errors << "Fastfile build_beta: match must list app_identifier: [...]"
  else
    same_set.call("Fastfile match", resolve.call(ids.scan(/[A-Z_]+_ID/), "match"))
  end

  signed_targets = {}
  lane.scan(/update_code_signing_settings\((.*?)\n\s*\)/m) do |(block)|
    name = block[/targets:\s*\["([^"]+)"\]/, 1]
    const = block[/profile_name:\s*ENV\["sigh_\#\{([A-Z_]+)\}_appstore_profile-name"\]/, 1]
    signed_targets[name] = constants[const] if name
  end
  targets.each do |t|
    if !signed_targets.key?(t.name)
      errors << "Fastfile build_beta: no update_code_signing_settings for target #{t.name}"
    elsif signed_targets[t.name] != t.bundle_id
      errors << "Fastfile build_beta: #{t.name} is signed with the #{signed_targets[t.name].inspect} profile, not #{t.bundle_id}"
    end
  end

  profiles = lane[/provisioningProfiles:\s*\{(.*?)\n\s*\}/m, 1]
  if profiles.nil?
    errors << "Fastfile build_beta: build_app export_options must map provisioningProfiles"
  else
    same_set.call("Fastfile export provisioningProfiles",
                  resolve.call(profiles.scan(/([A-Z_]+_ID)\s*=>/).flatten, "provisioningProfiles"))
  end

  read_at = lane.index('ENV["MATCH_READONLY"]')
  setup_at = lane.index("setup_ci")
  if read_at.nil? || setup_at.nil? || read_at > setup_at
    errors << "Fastfile build_beta: read ENV[\"MATCH_READONLY\"] before setup_ci, which forces it to true"
  end
  unless match_call =~ /readonly:\s*match_readonly\b/
    errors << "Fastfile build_beta: pass readonly: match_readonly to match (Matchfile reads the env after setup_ci)"
  end

  # Provisioning must never push to the protected certs branch: match gets a
  # branch started from it (an absent branch becomes an empty orphan and a new
  # certificate), and the result lands by pull request and is verified.
  unless match_call =~ /git_branch:\s*provision_branch\s*\|\|\s*CERTS_BRANCH/
    errors << "Fastfile build_beta: match must get git_branch: provision_branch || CERTS_BRANCH"
  end
  start_at = lane.index("start_branch(")
  match_at = lane.index("match(")
  land_at = lane.index("land_provisioning(")
  unless start_at && match_at && land_at && start_at < match_at && match_at < land_at
    errors << "Fastfile build_beta: provisioning must start_branch before match and land_provisioning after it"
  end
end

certs_branch = fastfile[/^CERTS_BRANCH\s*=\s*"([^"]+)"/, 1]
match_branch = matchfile[/^git_branch\("([^"]+)"\)/, 1]
errors << "Fastfile: CERTS_BRANCH must be \"main\", got #{certs_branch.inspect}" unless certs_branch == "main"
errors << "Matchfile: git_branch(\"main\") is required (match defaults to master), got #{match_branch.inspect}" unless match_branch == "main"

matchfile_ids = matchfile[/app_identifier\(\[(.*?)\]\)/m, 1].to_s
  .gsub(/\#\{ENV\["APP_IDENTIFIER"\]\s*\|\|\s*"([^"]+)"\}/, '\1')
  .scan(/^\s*(?:ENV\["APP_IDENTIFIER"\]\s*\|\|\s*)?"([^"]+)"/).flatten
same_set.call("Matchfile app_identifier", matchfile_ids)

if errors.empty?
  puts "Signing coverage passed: #{expected.join(', ')}"
else
  errors.each { |e| warn e }
  exit 1
end
