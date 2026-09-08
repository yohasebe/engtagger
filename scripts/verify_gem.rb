#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_gem.rb — pre-release gate for a built .gem
#
# Opens the built gem and checks that its payload matches what the gemspec
# says it should contain, in both directions, then scans the payload for
# secrets and machine-local paths. Exits non-zero on any finding, and on an
# empty payload (a check that inspects nothing must not pass).
#
# The expected file list is NOT re-derived from git; it is asked from the
# gemspec itself (Gem::Specification.load → spec.files), so the gate and the
# packager always use the same rule.
#
#   ruby verify_gem.rb [path/to/name-1.2.3.gem] [--gemspec name.gemspec]
#
# With no gem path, the newest pkg/*.gem is used. With no --gemspec, the
# single *.gemspec in the current directory is used.
#
# Placement: put this file in a directory the gemspec EXCLUDES (check with
#   ruby -e 'puts Gem::Specification.load("x.gemspec").files.grep(/verify_gem/)'
# — must print nothing). A `git ls-files` gemspec ships whatever is tracked, so
# a gate placed in an unexcluded directory ships itself to users.
#
# Rakefile wiring (bundler/gem_tasks projects):
#
#   Rake::Task["build"].enhance { sh "ruby", "scripts/verify_gem.rb" }
#
# `rake release` depends on `build`, so this runs right before push.
#
# Control tests (run once when adopting, and again whenever this file changes):
#   1. `git add -f .audit-decoy.env && gem build ...` → must FAIL (unexpected file)
#   2. put "ghp_" + 36 alnum chars into a tracked file → must FAIL (secret pattern)
#   3. put an absolute path under your home directory into a tracked file → must FAIL (local path)
#      (do not spell the path out here: this file scans itself, see the self-check below)
#   4. delete a file listed in spec.files after build → must FAIL (missing file)
#   5. run against an empty gem → must FAIL (zero files)
#   6. clean build → must PASS

require "rubygems"
require "rubygems/package"
require "zlib"
require "optparse"

gemspec_path = nil
OptionParser.new do |o|
  o.on("--gemspec PATH") { |v| gemspec_path = v }
end.parse!

gem_path = ARGV[0] || Dir["pkg/*.gem"].max_by { |f| File.mtime(f) }
abort "verify_gem: no .gem found (pass a path or build first)" unless gem_path && File.file?(gem_path)

gemspec_path ||= begin
  cands = Dir["*.gemspec"]
  abort "verify_gem: expected exactly one *.gemspec in #{Dir.pwd}, found #{cands.size}" unless cands.size == 1
  cands.first
end

spec = Gem::Specification.load(gemspec_path)
abort "verify_gem: could not load #{gemspec_path}" unless spec

expected = spec.files.map { |f| f.sub(%r{\A\./}, "") }.reject { |f| File.directory?(f) }.sort.uniq
abort "verify_gem: spec.files is empty — the gemspec would ship nothing; refusing to judge" if expected.empty?

# --- read the payload ---------------------------------------------------------
actual = []
contents = {}
begin
  Gem::Package::TarReader.new(File.open(gem_path, "rb")) do |outer|
    outer.each do |entry|
      next unless entry.full_name == "data.tar.gz"
      Zlib::GzipReader.wrap(entry) do |gz|
        Gem::Package::TarReader.new(gz) do |inner|
          inner.each do |e|
            next unless e.file?
            name = e.full_name.sub(%r{\A\./}, "")
            actual << name
            contents[name] = e.read
          end
        end
      end
    end
  end
end
actual = actual.sort.uniq

failures = []

# --- 0. must inspect something ---------------------------------------------------
failures << "payload is empty (0 files) — nothing was inspected" if actual.empty?

# --- 1. both-direction comparison ------------------------------------------------
unexpected = actual - expected
missing    = expected - actual
failures << "files in gem but not in spec.files (#{unexpected.size}):\n  " + unexpected.join("\n  ") unless unexpected.empty?
failures << "files in spec.files but not in gem (#{missing.size}):\n  " + missing.join("\n  ") unless missing.empty?

# --- 2. names that should never ship ----------------------------------------------
# Note: a private file that was `git add`ed IS in spec.files (git ls-files gemspecs
# ship whatever is tracked), so the two-direction comparison cannot see it. Only
# these name checks and the content scan below can. Keep them broad.
BAD_NAMES = [
  %r{(\A|/)[^/]*\.env(\.[^/]*)?\z}, %r{(\A|/)\.envrc\z},
  %r{(\A|/)(CLAUDE|AGENTS|GEMINI)\.md\z}, %r{(\A|/)\.claude/},
  %r{(\A|/)(credentials|secrets?)[^/]*\z}i, %r{(\A|/)id_(rsa|ed25519|ecdsa)[^/]*\z},
  %r{(\A|/)\.DS_Store\z}, %r{\.(pem|p12|pfx|key|token|log|bak|orig|swp|pyc)\z}, %r{(\A|/)tags\z},
  %r{(\A|/)(tmp|pkg|node_modules|__pycache__)/}, %r{(\A|/)Gemfile\.lock\z}
].freeze
bad = actual.select { |f| BAD_NAMES.any? { |re| f.match?(re) } }
failures << "suspicious file names (#{bad.size}):\n  " + bad.join("\n  ") unless bad.empty?

# --- 3. content scan (narrow patterns only; wide words like "token" are noise) ------
# Patterns whose source text would itself match are written as adjacent string
# literals (Ruby concatenates them), so that this file never trips its own scan if
# a project ships it inside the gem.
SECRET_PATTERNS = {
  "GitHub token"        => /\bghp_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b/,
  "OpenAI-style key"    => /\bsk-[A-Za-z0-9_-]{20,}\b/,
  "AWS access key"      => /\bAKIA[0-9A-Z]{16}\b/,
  "Google API key"      => /\bAIza[0-9A-Za-z_-]{35}\b/,
  "Slack token"         => /\bxox[baprs]-[0-9A-Za-z-]{10,}\b/,
  "private key block"   => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  "local absolute path" => %r{(?<![A-Za-z0-9_])/(Users|home)/[A-Za-z0-9_.-]+/},
  "Dropbox path"        => Regexp.new("/CloudStorage/" "Dropbox/")
}.freeze

# Self-check: this file is often tracked (and therefore public, sometimes even
# shipped). If its own source matches one of its patterns, the gate would fail on
# itself the moment it is included in a payload. Refuse to run rather than let
# that reappear through an innocent edit to a comment or an example.
self_src = File.binread(__FILE__)
self_hits = SECRET_PATTERNS.select { |_, re| self_src.match?(re) }.keys
abort "verify_gem: own source matches #{self_hits.join(', ')} — write the offending text as adjacent string literals" unless self_hits.empty?
hits = []
contents.each do |name, data|
  next if data.nil? || data.empty?
  text = data.dup.force_encoding("BINARY")
  SECRET_PATTERNS.each do |label, re|
    next unless text.match?(re)
    hits << "#{name}: #{label}"
  end
end
failures << "content scan hits (#{hits.size}):\n  " + hits.join("\n  ") unless hits.empty?

# --- 4. permissions ----------------------------------------------------------------
# A `sudo gem install` keeps the mode from the archive and makes root the owner, so
# anything without the world-read bit (0600, 0640, ...) becomes unreadable to the
# user who then requires the gem. Require o+r on every file.
Gem::Package::TarReader.new(File.open(gem_path, "rb")) do |outer|
  outer.each do |entry|
    next unless entry.full_name == "data.tar.gz"
    Zlib::GzipReader.wrap(entry) do |gz|
      Gem::Package::TarReader.new(gz) do |inner|
        narrow = inner.select { |e| e.file? && (e.header.mode & 0o004).zero? }.map(&:full_name)
        failures << "files not world-readable (#{narrow.size}):\n  " + narrow.join("\n  ") unless narrow.empty?
      end
    end
  end
end

# --- report -----------------------------------------------------------------------
if failures.empty?
  puts "verify_gem: PASS — #{gem_path}: #{actual.size} files match spec.files exactly; no suspicious names, content, or modes"
  exit 0
else
  warn "verify_gem: FAIL — #{gem_path}"
  failures.each { |f| warn "  * #{f}" }
  exit 1
end
