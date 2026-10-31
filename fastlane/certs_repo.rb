# The certs repo's default branch is protected: changes land by pull request,
# never by direct push. fastlane match pushes to whatever branch it is given,
# swallows a rejected push (git_storage.rb rescues it and logs an error), and
# turns a branch that does not exist yet into an empty orphan, which would mint
# a new distribution certificate. So a provisioning run (MATCH_READONLY=false)
# starts a real branch from the default branch, lets match write there, then
# lands it by pull request and checks that every profile arrived.
require "json"
require "net/http"
require "uri"

class CertsRepo
  class Error < StandardError; end

  attr_reader :owner, :repo

  def initialize(url:, authorization:, http: nil)
    m = url.to_s.match(%r{github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?\z})
    raise ArgumentError, "MATCH_GIT_URL must be a GitHub repository URL" unless m
    raise ArgumentError, "MATCH_GIT_BASIC_AUTHORIZATION is empty" if authorization.to_s.strip.empty?

    @owner = m[1]
    @repo = m[2]
    @authorization = "Basic #{authorization.strip}"
    @http = http || method(:request)
  end

  # A new branch at the base's head. match checks it out rather than creating
  # an orphan, so it sees and reuses the existing certificate and profiles.
  def start_branch(name, base:)
    sha = call(:get, "git/ref/heads/#{base}").fetch("object").fetch("sha")
    call(:post, "git/refs", "ref" => "refs/heads/#{name}", "sha" => sha)
    sha
  end

  def ahead?(branch, base:)
    call(:get, "compare/#{base}...#{branch}").fetch("ahead_by").to_i.positive?
  end

  # Open a PR and merge it. Rebase keeps the protected branch's linear history.
  def merge_by_pull_request(branch, base:, title:, body:)
    pr = call(:post, "pulls", "title" => title, "head" => branch, "base" => base, "body" => body)
    call(:put, "pulls/#{pr.fetch('number')}/merge", "merge_method" => "rebase")
    pr.fetch("html_url")
  end

  # Tolerates a branch GitHub already deleted on merge.
  def delete_branch(name)
    call(:delete, "git/refs/heads/#{name}", nil, ok: [404, 422])
  end

  def paths(branch)
    call(:get, "git/trees/#{branch}?recursive=1").fetch("tree").map { |e| e["path"] }
  end

  private

  def call(verb, path, payload = nil, ok: [])
    status, body = @http.call(verb, "https://api.github.com/repos/#{@owner}/#{@repo}/#{path}", payload, @authorization)
    return body if (200..299).cover?(status) || ok.include?(status)

    message = body.is_a?(Hash) ? body["message"] : nil
    raise Error, "#{verb.to_s.upcase} #{path} returned HTTP #{status}#{message ? ": #{message}" : ''}"
  end

  def request(verb, url, payload, authorization)
    uri = URI(url)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(verb)
    req = klass.new(uri)
    req["Authorization"] = authorization
    req["Accept"] = "application/vnd.github+json"
    req["User-Agent"] = "cadence-match-provisioning"
    if payload
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(payload)
    end
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |h| h.request(req) }
    body = begin
      res.body.to_s.empty? ? {} : JSON.parse(res.body)
    rescue JSON::ParserError
      {}
    end
    [res.code.to_i, body]
  end
end
