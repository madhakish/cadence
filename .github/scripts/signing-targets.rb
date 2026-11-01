# Shared by check-signing-coverage.rb and check-signing-material.rb: the
# App IDs the store IPA must be signed for, derived from project.yml so a new
# embedded target (widget, watch app, extension) is covered the moment it is
# added. Plain Ruby 2.6+ stdlib: it runs on stock macOS and Ubuntu runners.
require "yaml"

module SigningTargets
  APP_TARGET = "Cadence".freeze

  Target = Struct.new(:name, :type, :bundle_id)

  # Every non-test target that ships inside the app bundle, the app first.
  def self.shippable(project_path = "project.yml")
    targets = YAML.load_file(project_path).fetch("targets")
    seen = []
    queue = [APP_TARGET]
    until queue.empty?
      name = queue.shift
      next if seen.include?(name)
      spec = targets[name] or raise "project.yml: #{name} is embedded but not defined"
      next if spec["type"].to_s.start_with?("bundle.") # test bundles never ship
      seen << name
      (spec["dependencies"] || []).each { |dep| queue << dep["target"] if dep["target"] }
    end
    seen.map do |name|
      spec = targets[name]
      settings = spec["settings"] || {}
      base = settings["base"] || settings
      Target.new(name, spec["type"], base["PRODUCT_BUNDLE_IDENTIFIER"])
    end
  end
end
