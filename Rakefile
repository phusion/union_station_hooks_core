require 'shellwords'

desc 'Run tests'
task :spec do
  pattern = ENV['E']
  if pattern
    args = "-e #{Shellwords.escape(pattern)}"
  end
  sh "bundle exec rspec -c -f d spec/*_spec.rb #{args}"
end

task :test => :spec

desc 'Build gem'
task :gem do
  sh 'gem build union_station_hooks_core.gemspec'
end

desc 'Check coding style'
task :rubocop do
  sh 'bundle exec rubocop -D lib'
end

desc 'Generate API documentation'
task :doc do
  sh 'rm -rf doc'
  sh 'bundle exec yard'
end
