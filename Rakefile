require 'shellwords'

TRAVIS_PASSENGER_BRANCH = 'ust_router_rewrite'

desc 'Run tests'
task :spec do
  pattern = ENV['E']
  if pattern
    args = "-e #{Shellwords.escape(pattern)}"
  end
  sh 'rm -rf coverage'
  sh "bundle exec rspec -c -f d spec/*_spec.rb #{args}"
end

task :test => :spec

desc 'Run tests in Travis'
task "spec:travis" do
  if !File.exist?('passenger')
    sh "git clone --recursive --branch #{TRAVIS_PASSENGER_BRANCH} git://github.com/phusion/passenger.git"
  else
    puts 'cd passenger'
    Dir.chdir('passenger') do
      sh 'git fetch'
      sh 'rake clean'
      sh "git reset --hard origin/#{TRAVIS_PASSENGER_BRANCH}"
      sh 'git submodule update --init --recursive'
    end
    puts 'cd ..'
  end

  passenger_config = './passenger/bin/passenger-config'
  envs = {
    'PASSENGER_CONFIG' => passenger_config,
    'CC' => 'ccache cc',
    'CXX' => 'ccache c++',
    'CCACHE_COMPRESS' => '1',
    'CCACHE_COMPRESS_LEVEL' => '3'
  }
  envs.each_pair do |key, val|
    ENV[key] = val
    puts "$ export #{key}=#{val}"
  end
  sh "#{passenger_config} install-agent --auto"

  sh 'cp ruby_versions.yml.travis ruby_versions.yml'
  Rake::Task['spec'].invoke
end

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
