# frozen_string_literal: true

# require "bundler/gem_tasks"

version_file = "lib/strop/version.rb"
load version_file

namespace :gem do
  desc "Bump version (m=major, n=minor, p=patch, or full version m.n.p)"
  task :bump, [:vers] do |t, args|
    current_version = Strop::VERSION
    m,n,p = current_version.split(".").map(&:to_i)

    new_version = case args[:vers]
                  when "m", "major"      then "#{m + 1}.0.0"
                  when "n", "minor", nil then "#{m}.#{n + 1}.0"
                  when "p", "patch"      then "#{m}.#{n}.#{p + 1}"
                  else args[:vers] # assume full version string
                  end

    File.write version_file, File.read(version_file).sub(/\bVERSION\s*=\s*\K(["']).+\1/, %["#{new_version}"])
    sh "git add #{version_file}"
    sh "git commit -m 'Bump version to #{new_version}'"
    puts "Bumped version: #{current_version} -> #{new_version}"
  end

  desc "Build gem"
  task :build do
    sh "gem build strop.gemspec"
  end

  desc "Tag current version"
  task :tag do
    sh "git tag v#{Strop::VERSION}"
    sh "git push origin v#{Strop::VERSION}"
  end

  desc "Push gem to rubygems"
  task :push do
    load version_file
    sh "gem push strop-#{Strop::VERSION}.gem"
    Rake::Task["gem:tag"].invoke
  end

  desc "Clean built gems"
  task :clean do
    FileUtils.rm_f Dir.glob "strop-*.gem"
  end

  desc "Release gem (bump minor, build, push, tag)"
  task :release, [:vers] do |t, args|
    Rake::Task["gem:bump"].invoke(args[:vers])
    load version_file
    Rake::Task["gem:build"].invoke
    Rake::Task["gem:push"].invoke
    Rake::Task["gem:clean"].invoke
  end
end
