require 'bundler'
Bundler::GemHelper.install_tasks

desc "Tag #{Bundler::GemHelper.new.send(:version_tag)}, build and push to gemfury"
task :release_internal do |t|
  require 'gemfury'

  class ReleaseInternalGem < Bundler::GemHelper
    def release_gem
      guard_clean
      built_gem_path = build_gem
      if Bundler::VERSION =~ /1\.3\.\d/
        tag_version { git_push } unless already_tagged?
      else
        guard_already_tagged
        tag_version { git_push }
      end
      `fury push #{built_gem_path}`
      Bundler.ui.confirm "Pushed #{name} #{version} to gemfury"
    end
  end

  ReleaseInternalGem.new.release_gem
end
