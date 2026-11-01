#!/usr/bin/env ruby
# Live signing preflight: proves, in about a minute on Ubuntu, that the signed
# release build can get its signing material, instead of finding out 25
# minutes into a macOS release run. Every check here is a real failure from
# 2026-10-31:
#
# 1. The certs-repo token works: it can read the repo, and write to it when
#    MATCH_READONLY=false (a pasted wrong token failed the clone).
# 2. Every shipped App ID has an App Store profile in the certs repo, or the
#    run may create one (the watch App ID shipped with no profile while match
#    was read-only).
# 3. The App Store Connect key works, and Apple is not blocking the account on
#    an unaccepted agreement (a new Program License Agreement blocked match).
# 4. Every shipped App ID is registered in the developer portal (match cannot
#    register one, even when provisioning).
# 5. The account has an unexpired distribution certificate, and every shipped
#    App ID an active App Store profile, neither expiring within
#    EXPIRY_WARNING_DAYS (a notice). They lapse a year after match creates
#    them, outside the repository; the daily signing-health workflow reports
#    them in time.
#
# Never prints a credential. Env (CI passes the same secrets as store-build):
#   MATCH_GIT_URL, MATCH_GIT_BASIC_AUTHORIZATION, MATCH_GIT_BRANCH (default: the Matchfile git_branch),
#   MATCH_READONLY, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT (base64 .p8)
#   SIGNING_PREFLIGHT=required (default) | optional | local
#     optional: no credentials (fork/Dependabot PRs) is a notice, not a failure
#     local: owner's machine; the certs check falls back to `gh auth token`
#     and the App Store Connect checks are skipped without a key
#   SIGNING_FINDINGS=<path>  write the errors and expiry warnings there as a
#     Markdown list (empty when there are none), for signing-health.yml
#   SIGNING_HTTP_FIXTURES=<json>  tests only: canned responses by request name
require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"
require_relative "signing-targets"

class SigningPreflight
  ASC_API = "https://api.appstoreconnect.apple.com/v1".freeze
  EXPIRY_WARNING_DAYS = 30

  def initialize(env, project_path)
    @env = env
    @mode = env.fetch("SIGNING_PREFLIGHT", "required")
    @readonly = env["MATCH_READONLY"] != "false"
    @project_path = project_path
    @app_ids = SigningTargets.shippable(project_path).map(&:bundle_id).compact
    @fixtures = env["SIGNING_HTTP_FIXTURES"] && JSON.parse(File.read(env["SIGNING_HTTP_FIXTURES"]))
    @errors = []
    @notices = []
    @warnings = []
    @now = Time.now.utc
  end

  def run
    certs_auth = certs_authorization
    asc = asc_credentials
    if certs_auth.nil? && asc.nil? && @mode == "optional"
      say(:notice, "signing credentials are not available to this run (fork or Dependabot PR); skipped")
      return 0
    end
    certs_auth ? check_certs(certs_auth) : missing("MATCH_GIT_BASIC_AUTHORIZATION (certs repo token)")
    if asc
      check_apple(asc)
    elsif @mode == "local"
      say(:notice, "no App Store Connect key in the environment; Apple account checks skipped")
    else
      missing("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_CONTENT (App Store Connect key)")
    end
    @notices.each { |n| say(:notice, n) }
    @warnings.each { |w| say(:notice, w) }
    @errors.each { |e| say(:error, e) }
    write_findings
    if @errors.empty?
      puts "Signing preflight passed for #{@app_ids.join(', ')}#{@readonly ? '' : ' (provisioning run: MATCH_READONLY=false)'}"
      0
    else
      1
    end
  end

  private

  def missing(what)
    @errors << "missing #{what}"
  end

  def write_findings
    path = @env["SIGNING_FINDINGS"].to_s
    return if path.empty?

    File.write(path, (@errors.map { |e| "- **Error:** #{e}\n" } +
                      @warnings.map { |w| "- **Expiring:** #{w}\n" }).join)
  end

  def say(level, message)
    if @env["GITHUB_ACTIONS"] == "true"
      puts "::#{level}::#{message}"
    else
      puts "#{level}: #{message}"
    end
  end

  # -- certs repo ----------------------------------------------------------

  def certs_authorization
    basic = @env["MATCH_GIT_BASIC_AUTHORIZATION"].to_s.strip
    return "Basic #{basic}" unless basic.empty?
    return nil unless @mode == "local"
    token = `gh auth token 2>/dev/null`.strip rescue ""
    token.empty? ? nil : "Bearer #{token}"
  end

  def certs_repo
    url = @env["MATCH_GIT_URL"].to_s
    url = "https://github.com/madhakish/cadence-certs.git" if url.empty? && @mode == "local"
    m = url.match(%r{github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?\z})
    m && [m[1], m[2]]
  end

  def check_certs(auth)
    owner, repo = certs_repo
    return @errors << "MATCH_GIT_URL must be a GitHub repository URL" unless owner

    status, body = get("certs_repo", "https://api.github.com/repos/#{owner}/#{repo}", { "Authorization" => auth })
    unless status == 200
      return @errors << "the certs repo token cannot read #{owner}/#{repo} (HTTP #{status}). " \
                        "Re-create MATCH_GIT_BASIC_AUTHORIZATION as base64(\"<user>:<fine-grained PAT>\") " \
                        "with Contents access to that repo only (docs/TESTFLIGHT.md)"
    end
    branch = certs_branch
    # A provisioning run pushes a new branch and lands it by pull request
    # (fastlane/certs_repo.rb), because the default branch is protected.
    check_provisioning_access(owner, repo, branch, auth) unless @readonly

    status, tree = get("certs_tree", "https://api.github.com/repos/#{owner}/#{repo}/git/trees/#{branch}?recursive=1",
                       { "Authorization" => auth })
    return @errors << "cannot list branch #{branch} of the certs repo (HTTP #{status})" unless status == 200

    paths = (tree["tree"] || []).map { |e| e["path"] }
    unless paths.any? { |p| p.start_with?("certs/distribution/") && p.end_with?(".cer") }
      need_provisioning("the certs repo has no distribution certificate")
    end
    @app_ids.each do |id|
      next if paths.include?("profiles/appstore/AppStore_#{id}.mobileprovision")
      need_provisioning("the certs repo has no App Store provisioning profile for #{id}")
    end
  end

  # `permissions.push` describes the account's role, not what a fine-grained
  # token was granted, so prove Contents write with a scratch branch that is
  # created and deleted. Pull request write is proven when the run lands its
  # PR (the lane keeps the branch and says what to do if it cannot).
  def check_provisioning_access(owner, repo, branch, auth)
    base = "https://api.github.com/repos/#{owner}/#{repo}"
    headers = { "Authorization" => auth }
    status, ref = api("certs_branch_ref", :get, "#{base}/git/ref/heads/#{branch}", headers)
    return @errors << "cannot read branch #{branch} of the certs repo (HTTP #{status})" unless status == 200

    scratch = "preflight/#{@env['GITHUB_RUN_ID'] || Time.now.to_i}"
    status, = api("certs_scratch_create", :post, "#{base}/git/refs", headers,
                  { "ref" => "refs/heads/#{scratch}", "sha" => ref.dig("object", "sha") })
    if status == 201
      api("certs_scratch_delete", :delete, "#{base}/git/refs/heads/#{scratch}", headers)
    else
      @errors << "MATCH_READONLY=false but the certs repo token cannot push a branch to #{owner}/#{repo} " \
                 "(HTTP #{status}); match could not save new profiles. Give it Contents: Read and write"
    end
    status, = api("certs_pulls", :get, "#{base}/pulls?per_page=1", headers)
    return if status == 200

    @errors << "MATCH_READONLY=false but the certs repo token cannot use pull requests on #{owner}/#{repo} " \
               "(HTTP #{status}); provisioning lands by pull request. Give it Pull requests: Read and write"
  end

  # The branch match reads: MATCH_GIT_BRANCH, else the Matchfile's git_branch.
  def certs_branch
    return @env["MATCH_GIT_BRANCH"] unless @env["MATCH_GIT_BRANCH"].to_s.empty?
    matchfile = File.join(File.dirname(@project_path), "fastlane", "Matchfile")
    branch = File.exist?(matchfile) && File.read(matchfile)[/^git_branch\("([^"]+)"\)/, 1]
    # match falls back to its own default ("master") without one; never rely on it.
    branch || (@errors << "fastlane/Matchfile must set git_branch(\"main\")" && "main")
  end

  # Missing signing material is fatal for a read-only run. A provisioning run
  # (MATCH_READONLY=false with a write token) is how it gets created.
  def need_provisioning(what)
    if @readonly
      @errors << "#{what}. Read-only match cannot create it: set the repository variable MATCH_READONLY=false " \
                 "with a read-and-write certs token for one signed run, then revert both (docs/TESTFLIGHT.md)"
    else
      @notices << "#{what}; this provisioning run will create it"
    end
  end

  # -- App Store Connect ---------------------------------------------------

  def asc_credentials
    key_id, issuer, content = @env.values_at("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_CONTENT").map { |v| v.to_s.strip }
    return nil if key_id.empty? || issuer.empty? || content.empty?
    [key_id, issuer, content]
  end

  def check_apple(creds)
    token = @fixtures ? "fixture" : asc_token(*creds)
    return unless token

    auth = { "Authorization" => "Bearer #{token}" }
    ids = @app_ids.join(",")
    status, body = get("asc_bundle_ids", "#{ASC_API}/bundleIds?filter%5Bidentifier%5D=#{ids}&limit=200", auth)
    unless status == 200
      details = (body["errors"] || []).map { |e| [e["code"], e["detail"]].compact.join(": ") }.join("; ")
      if details =~ /agreement/i
        return @errors << "Apple is blocking the developer account until the Account Holder accepts the latest " \
                          "agreement at developer.apple.com/account (and App Store Connect > Business). Apple says: #{details}"
      end
      return @errors << "the App Store Connect key was refused (HTTP #{status}#{details.empty? ? '' : ": #{details}"}). " \
                        "Check ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT and the key's App Manager role"
    end
    registered = (body["data"] || []).map { |d| d.dig("attributes", "identifier") }
    # match never registers App IDs, even when provisioning: it stops with
    # "Couldn't find bundle identifier" (match/spaceship_ensure.rb).
    (@app_ids - registered).each do |id|
      @errors << "App ID #{id} is not registered in the developer portal, and match cannot register it. " \
                 "Register it under Certificates, IDs & Profiles > Identifiers (docs/TESTFLIGHT.md)"
    end
    check_expiry(auth)
  end

  # Apple's side of the signing material: what the certs repo holds stops
  # signing once Apple's copy expires or is invalidated.
  def check_expiry(auth)
    status, body = get("asc_certificates",
                       "#{ASC_API}/certificates?filter%5BcertificateType%5D=DISTRIBUTION,IOS_DISTRIBUTION" \
                       "&fields%5Bcertificates%5D=displayName,expirationDate&limit=200", auth)
    return @errors << "cannot list distribution certificates in App Store Connect (HTTP #{status})" unless status == 200

    check_dates("distribution certificate", (body["data"] || []).map { |c| expiration(c) })

    status, body = get("asc_profiles",
                       "#{ASC_API}/profiles?filter%5BprofileType%5D=IOS_APP_STORE&filter%5BprofileState%5D=ACTIVE" \
                       "&include=bundleId&fields%5Bprofiles%5D=name,expirationDate,bundleId" \
                       "&fields%5BbundleIds%5D=identifier&limit=200", auth)
    return @errors << "cannot list App Store profiles in App Store Connect (HTTP #{status})" unless status == 200

    bundle_ids = (body["included"] || []).select { |i| i["type"] == "bundleIds" }
                                         .to_h { |i| [i["id"], i.dig("attributes", "identifier")] }
    profiles = (body["data"] || []).group_by { |p| bundle_ids[p.dig("relationships", "bundleId", "data", "id")] }
    @app_ids.each do |id|
      check_dates("active App Store profile for #{id}", (profiles[id] || []).map { |p| expiration(p) })
    end
  end

  # The latest-expiring candidate decides. Missing or expired fails a
  # read-only run, like missing material in the certs repo.
  def check_dates(what, dates)
    latest = dates.compact.max
    if latest.nil?
      need_provisioning("the developer account has no #{what}")
    elsif latest <= @now
      need_provisioning("the #{what} expired on #{latest.strftime('%F')}")
    elsif (days = ((latest - @now) / 86_400).floor) <= EXPIRY_WARNING_DAYS
      @warnings << "the #{what} expires on #{latest.strftime('%F')}, in #{days} days. " \
                   "Renew it before then (docs/TESTFLIGHT.md, Signing health)"
    end
  end

  def expiration(resource)
    Time.parse(resource.dig("attributes", "expirationDate").to_s).utc
  rescue ArgumentError
    nil
  end

  def asc_token(key_id, issuer, content)
    key = OpenSSL::PKey::EC.new(Base64.decode64(content))
    now = Time.now.to_i
    input = [{ alg: "ES256", kid: key_id, typ: "JWT" },
             { iss: issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }]
            .map { |part| b64url(part.to_json) }.join(".")
    # JWS wants raw r||s, not the DER signature OpenSSL returns.
    r, s = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new, input)).value.map { |i| i.value.to_s(2).rjust(32, "\0") }
    "#{input}.#{b64url(r + s)}"
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    @errors << "ASC_KEY_CONTENT is not a base64-encoded .p8 private key"
    nil
  end

  def b64url(data)
    Base64.urlsafe_encode64(data).delete("=")
  end

  # -- HTTP ----------------------------------------------------------------

  def get(name, url, headers)
    api(name, :get, url, headers)
  end

  def api(name, verb, url, headers, payload = nil)
    if @fixtures
      canned = @fixtures.fetch(name) { raise "fixture missing response #{name}" }
      return [canned.fetch("status"), canned.fetch("body", {})]
    end
    uri = URI(url)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(verb)
    request = klass.new(uri)
    headers.merge("Accept" => "application/json", "User-Agent" => "cadence-signing-preflight").each { |k, v| request[k] = v }
    if payload
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
    end
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |h| h.request(request) }
    body = begin
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end
    [response.code.to_i, body.is_a?(Hash) ? body : {}]
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    [0, { "errors" => [{ "detail" => "network error: #{e.class}" }] }]
  end
end

exit SigningPreflight.new(ENV, ARGV[0] || "project.yml").run if $PROGRAM_NAME == __FILE__
