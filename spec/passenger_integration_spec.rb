#  Union Station - https://www.unionstationapp.com/
#  Copyright (c) 2015 Phusion Holding B.V.
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

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'tmpdir'
require 'shellwords'
require 'fileutils'

describe 'Passenger integration' do
  let(:port) { 4928 }
  let(:root_url) { "http://127.0.0.1:#{port}" }

  let(:main_lib_path) do
    "#{UnionStationHooks::LIBROOT}/union_station_hooks_core.rb"
  end

  before :each do
    @tmpdir = Dir.mktmpdir
    @dump_dir = "#{@tmpdir}/dump"
    @app_dir = "#{@tmpdir}/app"
    FileUtils.mkdir(@dump_dir)
    FileUtils.mkdir(@app_dir)
    FileUtils.mkdir("#{@app_dir}/public")
    FileUtils.mkdir("#{@app_dir}/tmp")
    FileUtils.mkdir("#{@app_dir}/log")
  end

  after :each do
    stop_app
    FileUtils.rm_rf(@tmpdir)
  end

  def start_app
    Dir.chdir(@app_dir) do
      command = "#{PhusionPassenger.bin_dir}/passenger start " \
        "--address 127.0.0.1 --port #{port} " \
        "--max-pool-size 1 --daemonize --environment production " \
        "--friendly-error-pages " \
        "--union-station-key whatever " \
        "--ctl ust_router_dev_mode=true " \
        "--ctl ust_router_dump_dir=#{Shellwords.escape @dump_dir}"
      output = `#{command} 2>&1`
      if $?.nil? || $?.exitstatus != 0
        raise "Error starting Passenger. This was the command's output:\n" \
          "------ Begin output ------\n" \
          "#{output}\n" \
          "------ End output ------"
      end
    end
  end

  def stop_app
    return if !app_started?
    Dir.chdir(@app_dir) do
      result = system("#{PhusionPassenger.bin_dir}/passenger",
        'stop', '-p', port.to_s)
      if !result
        if $? && $?.termsig
          RSpec.world.wants_to_quit = true
        end
        raise 'Error stopping Passenger'
      end
    end
  end

  def app_started?
    Dir.chdir(@app_dir) do
      system("#{PhusionPassenger.bin_dir}/passenger status " \
        "-p #{port} >/dev/null 2>/dev/null")
    end
  end

  def prepare_debug_shell
    puts "You are at #{@tmpdir}."
    puts "You can find the application's code in 'app'."
    puts "You can find the UstRouter dump files in 'dump'."
    Dir.chdir(@tmpdir)
    if app_started?
      puts "App is listening at: #{root_url}/"
    end
  end

  specify 'the vendored Union Station hooks bundled with Passenger works' do
    write_file("#{@app_dir}/config.ru", %q{
      if defined?(UnionStationHooks)
        UnionStationHooks.initialize!
      end

      app = lambda do |env|
        options = {
          :controller_name => 'HomeController',
          :action_name => 'index'
        }
        reporter = env['union_station_hooks']
        reporter.log_controller_action_block(options) do
          [200, { 'Content-Type' => 'text/plain' },
            ["vendored: #{UnionStationHooks.vendored?}\n"]]
        end
      end

      run app
    })

    start_app

    expect(get('/')).to eq("vendored: true\n")
    wait_for_dump_file_existance
    eventually do
      expect(read_dump_file).to include(
        "Controller action: HomeController#index\n")
    end
  end

  it 'allows overriding the vendored Union Station hooks bundled with Passenger' do
    write_file("#{@app_dir}/config.ru", %Q{
      load #{main_lib_path.inspect}

      if defined?(UnionStationHooks)
        UnionStationHooks.initialize!
      end

      app = lambda do |env|
        options = {
          :controller_name => 'HomeController',
          :action_name => 'index'
        }
        reporter = env['union_station_hooks']
        reporter.log_controller_action_block(options) do
          [200, { 'Content-Type' => 'text/plain' },
            ["vendored: \#{UnionStationHooks.vendored?}\\n"]]
        end
      end

      run app
    })

    start_app
    expect(get('/')).to eq("vendored: false\n")
    wait_for_dump_file_existance
    eventually do
      expect(read_dump_file).to include(
        "Controller action: HomeController#index\n")
    end
  end

  describe "the legacy 'PhusionPassenger.install_framework_extensions!' call" do
    def create_config_ru(middleware)
      code = %Q{
        load #{main_lib_path.inspect}
        #{middleware}
      }
      code << %q{
        app = lambda do |env|
          options = {
            :controller_name => 'HomeController',
            :action_name => 'index'
          }
          reporter = env['union_station_hooks']
          reporter.log_controller_action_block(options) do
            [200, { 'Content-Type' => 'text/plain' },
              ["initialized: #{UnionStationHooks.initialized?}\n" \
               "foo: #{UnionStationHooks.config[:foo].inspect}\n" \
               "bar: #{UnionStationHooks.config[:bar].inspect}\n"]]
          end
        end

        run app
      }
      write_file("#{@app_dir}/config.ru", code)
    end

    it 'is supported with no arguments' do
      create_config_ru(%Q{
        PhusionPassenger.install_framework_extensions!
      })
      start_app
      expect(get('/')).to eq(
        "initialized: true\n" \
        "foo: nil\n" \
        "bar: nil\n"
      )
      wait_for_dump_file_existance
      eventually do
        expect(read_dump_file).to include(
          "Controller action: HomeController#index\n")
      end
    end

    it "is supported with a 'user_options' argument" do
      create_config_ru(%Q{
        PhusionPassenger.install_framework_extensions!(
          :foo => 1234, 'bar' => 5678)
      })
      start_app
      expect(get('/')).to eq(
        "initialized: true\n" \
        "foo: 1234\n" \
        "bar: 5678\n"
      )
      eventually do
        expect(read_dump_file).to include(
          "Controller action: HomeController#index\n")
      end
    end
  end
end
