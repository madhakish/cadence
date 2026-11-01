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
# 4. Every shipped App ID is registered in the developer portal, or the run
#    may register it.
#
# Never prints a credential. Env (CI passes the same secrets as store-build):
#   MATCH_GIT_URL, MATCH_GIT_BASIC_AUTHORIZATION, MATCH_GIT_BRANCH (default: the Matchfile git_branch),
#   MATCH_READONLY, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT (base64 .p8)
#   SIGNING_PREFLIGHT=required (default) | optional | local
#     optional: no credentials (fork/Dependabot PRs) is a notice, not a failure
#     local: owner's machine; the certs check falls back to `gh auth token`
#     and the App Store Connect checks are skipped without a key
#   SIGNING_HTTP_FIXTURES=<json>  tests only: canned responses by request name
require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"
require_relative "signing-targets"

class SigningPreflight
  def initialize(env, project_path)
    @env = env
    @mode = env.fetch("SIGNING_PREFLIGHT", "required")
    @readonly = env["MATCH_READONLY"] != "false"
    @project_path = project_path
    @app_ids = SigningTargets.shippable(project_path).map(&:bundle_id).compact
    @fixtures = env["SIGNING_HTTP_FIXTURES"] && JSON.parse(File.read(env["SIGNING_HTTP_FIXTURES"]))
    @errors = []
    @notices = []
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
    @errors.each { |e| say(:error, e) }
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
    # A provisioning run pushes a new branch and lands it by pull request
    # (fastlane/certs_repo.rb), because the default branch is protected.
    unless @readonly
      if body.dig("permissions", "push") != true
        @errors << "MATCH_READONLY=false but the certs repo token cannot write to #{owner}/#{repo}; " \
                   "match could not save new profiles. Use a Contents read-and-write PAT for the provisioning run"
      end
      status, = get("certs_pulls", "https://api.github.com/repos/#{owner}/#{repo}/pulls?per_page=1", { "Authorization" => auth })
      unless status == 200
        @errors << "MATCH_READONLY=false but the certs repo token cannot use pull requests on #{owner}/#{repo} " \
                   "(HTTP #{status}); provisioning lands by pull request. Give it Pull requests: Read and write"
      end
    end

    branch = certs_branch
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

    ids = @app_ids.join(",")
    status, body = get("asc_bundle_ids",
                       "https://api.appstoreconnect.apple.com/v1/bundleIds?filter%5Bidentifier%5D=#{ids}&limit=200",
                       { "Authorization" => "Bearer #{token}" })
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
    (@app_ids - registered).each do |id|
      if @readonly
        @errors << "App ID #{id} is not registered in the developer portal. Register it, or let one provisioning " \
                   "run (MATCH_READONLY=false) register it (docs/TESTFLIGHT.md)"
      else
        @notices << "App ID #{id} is not registered yet; this provisioning run will register it"
      end
    end
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
    if @fixtures
      canned = @fixtures.fetch(name) { raise "fixture missing response #{name}" }
      return [canned.fetch("status"), canned.fetch("body", {})]
    end
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    headers.merge("Accept" => "application/json", "User-Agent" => "cadence-signing-preflight").each { |k, v| request[k] = v }
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
