desc 'Run tests'
task :spec do
  sh 'bundle exec rspec -c -f d spec/*_spec.rb'
end

task :test => :spec

desc 'Build gem'
task :gem do
  sh 'gem build union_station_hooks_core.gemspec'
end

task :rubocop do
  sh 'bundle exec rubocop -D lib'
end