# frozen_string_literal: true

# Shared machinery for the per-matrix tooling.
# A "cell" is one row of a gem's test-matrix.json (the single source of truth CI reads)
# Both bin/relock (which materializes the committed lockfiles)
# and bin/test (which runs that cell's specs locally) expand cells the same way so neither can drift from CI.
#
# Each cell runs under a matching Ruby provided by mise (https://mise.jdx.dev);
# the required Rubies are declared in .mise.ci.toml and installed with
# `mise --env ci install`.

require "json"

module Matrix
  ROOT = File.expand_path("../..", __dir__)

  # translate gem versions to env vars picked up by Gemfile
  GEM_ENV_MAPPING = {
    "rack" => "RACK_VERSION",
    "redis" => "REDIS_RB_VERSION",
    "rails" => "RAILS_VERSION",
    "sidekiq" => "SIDEKIQ_VERSION"
  }.freeze

  Cell = Struct.new(:gem, :base, :ruby, :env, :rubyopt, keyword_init: true) do
    def wrapper
      "#{gem}/gemfiles/#{base}.gemfile"
    end

    def lock
      "#{wrapper}.lock"
    end

    def label
      "#{gem} / #{base}"
    end
  end

  module_function

  # Expand one test-matrix.json entry into a cell. The entry's keys (in file
  # order) become the filename segments and the env the Gemfile reads:
  #   {"ruby_version":"3.2","rack_version":"2","redis_rb_version":"4"}
  #   -> ruby-3.2_rack-2_redis-4, {RACK_VERSION=2, REDIS_RB_VERSION=4}
  def cell_from_entry(gem, entry)
    ruby = entry.fetch("ruby_version")
    segments = ["ruby-#{ruby}"]
    env = {}

    entry.each do |key, value|
      next if key == "ruby_version" || key == "options"

      name = key.split("_").first
      var = GEM_ENV_MAPPING[name]
      abort "Unknown matrix key: '#{key}' in #{gem}/test-matrix.json" unless var
      segments << "#{name}-#{value}"
      env[var] = value
    end

    Cell.new(gem: gem,
             base: segments.join("_"),
             ruby: ruby,
             env: env,
             rubyopt: entry.dig("options", "rubyopt"))
  end

  # Parse a wrapper/lock path's base name like "ruby-3.2_rack-3_redis-5" back
  # into a cell (used by relock's --cell, which addresses a cell by path).
  # rubyopt isn't recoverable from the path; callers that need it expand from
  # test-matrix.json via cell_from_entry instead.
  def parse_cell(gem, base)
    segments = base.split("_")
    ruby = segments.shift.sub(/\Aruby-/, "")

    env = {}
    segments.each do |seg|
      name, value = seg.split("-", 2)
      var = GEM_ENV_MAPPING[name]
      abort "Unknown matrix axis '#{name}' in #{gem}/gemfiles/#{base}" unless var
      env[var] = value
    end

    Cell.new(gem: gem, base: base, ruby: ruby, env: env)
  end

  # Split a wrapper/lock path into [gem, base] by position, since a cell is
  # addressed as <gem>/gemfiles/<base>.gemfile. Works for absolute, relative,
  # and .lock-suffixed paths. A gem-relative path (gemfiles/<base>.gemfile, e.g.
  # run from inside a gem dir) has no <gem> segment, so gem falls back to
  # fallback_gem (nil if none). Returns nil when the path has no gemfiles/<base>.
  def cell_path_parts(path, fallback_gem: nil)
    parts = path.sub(/\.lock\z/, "").split("/")
    gi = parts.rindex("gemfiles")
    return nil unless gi && parts[gi + 1]

    gem = gi.positive? ? parts[gi - 1] : fallback_gem
    [gem, File.basename(parts[gi + 1], ".gemfile")]
  end

  def matrix_path(gem)
    File.join(ROOT, gem, "test-matrix.json")
  end

  def discover_cells(gems)
    gems.flat_map do |gem|
      path = matrix_path(gem)
      abort "No test-matrix.json for gem '#{gem}'" unless File.exist?(path)
      JSON.parse(File.read(path)).map { |entry| cell_from_entry(gem, entry) }.uniq(&:wrapper)
    end
  end

  def all_gems
    Dir.glob(File.join(ROOT, "*", "test-matrix.json")).map { |p| File.basename(File.dirname(p)) }.sort
  end

  def mise_bin
    @mise_bin ||= begin
      found = `sh -lc 'command -v mise' 2>/dev/null`.strip
      found = found.lines.last.to_s.strip if found.include?("\n")

      candidates = [
        ENV["MISE_BIN"],
        found,
        "/opt/homebrew/bin/mise",
        File.expand_path("~/.local/bin/mise"),
        "/usr/local/bin/mise"
      ]

      candidates.compact.find { |c| File.executable?(c) } ||
        abort("mise not found. Install it: https://mise.jdx.dev")
    end
  end

  def installed?(ruby)
    system(mise_bin, "where", "ruby@#{ruby}", out: File::NULL, err: File::NULL)
  end

  def ensure_installed(cells)
    missing = cells.map(&:ruby).uniq.reject { |spec| installed?(spec) }
    return if missing.empty?

    warn "Ruby not installed: #{missing.map { |s| "ruby@#{s}" }.join(', ')}."
    abort "Run `mise --env ci install` first."
  end

  def cell_env(cell)
    { "BUNDLE_GEMFILE" => File.join(ROOT, cell.wrapper) }.merge(cell.env)
  end
end
