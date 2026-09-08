# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/test*.rb"]
  t.verbose = true
end

# Gem packaging preserves on-disk file modes; owner-only permissions here
# produce gems whose files are unreadable after a sudo install (issue #20).
task :normalize_permissions do
  `git ls-files -z`.split("\x0").each do |f|
    File.chmod(File.executable?(f) ? 0o755 : 0o644, f)
  end
end

Rake::Task["build"].enhance([:normalize_permissions])

# Pre-release gate: after building, open the .gem and verify its payload
# against spec.files in both directions, then scan names, contents and modes.
# `rake release` depends on `build`, so a FAIL here stops the push.
Rake::Task["build"].enhance { sh "ruby", "scripts/verify_gem.rb" }
