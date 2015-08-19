#  Union Station - https://www.unionstationapp.com/
#  Copyright (c) 2010-2015 Phusion Holding B.V.
#
#  "Union Station" and "Passenger" are trademarks of Phusion Holding B.V.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#  THE SOFTWARE.

require 'fileutils'

module UnionStationHooks
  module SpecHelper
    extend self # Make methods available as class methods.

    def self.included(klass)
      # When included into another class, make sure that Utils
      # methods are made private.
      public_instance_methods(false).each do |method_name|
        klass.send(:private, method_name)
      end
    end

    def initialize!
      load_passenger
      initialize_debugging
      undo_bundler
    end

    def find_passenger_config
      passenger_config = ENV['PASSENGER_CONFIG']
      if passenger_config.nil? || passenger_config.empty?
        ENV['PATH'].split(':').each do |path|
          if File.exist?("#{path}/passenger-config")
            passenger_config = "#{path}/passenger-config"
            break
          end
        end
      end
      if passenger_config.nil? || passenger_config.empty?
        abort 'ERROR: The unit tests are to be run against a specific ' \
          'Passenger version. However, the \'passenger-config\' command is ' \
          'not found. Please install Passenger, or (if you are sure ' \
          'Passenger is installed) set the PASSENGER_CONFIG environment ' \
          'variable to the \'passenger-config\' command.'
      end
      passenger_config
    end

    def load_passenger
      passenger_config = find_passenger_config
      puts "Using Passenger installation at: #{passenger_config}"
      passenger_ruby_libdir = `#{passenger_config} about ruby-libdir`.strip
      require("#{passenger_ruby_libdir}/phusion_passenger")
      PhusionPassenger.locate_directories
      PhusionPassenger.require_passenger_lib 'constants'
      puts "Loaded Passenger version #{PhusionPassenger::VERSION_STRING}"

      agent = PhusionPassenger.find_support_binary(PhusionPassenger::AGENT_EXE)
      if agent.nil?
        abort "ERROR: The Passenger agent isn't installed. Please ensure " \
          "that it is installed, e.g. using:\n\n" \
          "  #{passenger_config} install-agent\n\n"
      end
    end

    def initialize_debugging
      @@debug = !ENV['DEBUG'].to_s.empty?
      if @@debug
        UnionStationHooks.require_lib('log')
        UnionStationHooks::Log.debugging = true
      end
    end

    # Unit tests must undo the Bundler environment so that the gem's
    # own Gemfile doesn't affect subprocesses that may have their
    # own Gemfile.
    def undo_bundler
      clean_env = nil
      Bundler.with_clean_env do
        clean_env = ENV.to_hash
      end
      ENV.replace(clean_env)
    end

    def debug?
      @@debug
    end

    def write_file(path, content)
      dir = File.dirname(path)
      if !File.exist?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(path, 'wb') do |f|
        f.write(content)
      end
    end

    def base64(data)
      [data].pack('m').gsub("\n", '')
    end

    def eventually(deadline_duration = 3, check_interval = 0.05)
      deadline = Time.now + deadline_duration
      while Time.now < deadline
        if yield
          return
        else
          sleep(check_interval)
        end
      end
      raise 'Time limit exceeded'
    end

    def should_never_happen(deadline_duration = 0.5, check_interval = 0.05)
      deadline = Time.now + deadline_duration
      while Time.now < deadline
        if yield
          raise "That which shouldn't happen happened anyway"
        else
          sleep(check_interval)
        end
      end
    end
  end
end
