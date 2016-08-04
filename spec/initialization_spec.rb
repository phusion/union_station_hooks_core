#  Union Station - https://www.unionstationapp.com/
#  Copyright (c) 2015-2016 Phusion Holding B.V.
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
require 'fileutils'
require 'digest/md5'

describe UnionStationHooks do
  before :each do |example|
    @example_full_description = example.full_description
    @tmpdir = Dir.mktmpdir
  end

  after :each do
    kill_agent
    FileUtils.rm_rf(@tmpdir)
  end

  def start_agent
    @username = 'logging'
    @password = '1234'
    @dump_dir = "#{@tmpdir}/dump"
    @socket_filename = "#{@dump_dir}/ust_router.socket"
    @socket_address  = "unix:#{@socket_filename}"
    @agent_pid = spawn_ust_router(@socket_filename, @password)
  end

  def kill_agent
    if @agent_pid
      Process.kill('KILL', @agent_pid)
      Process.waitpid(@agent_pid)
      File.unlink(@socket_filename)
      @agent_pid = nil
    end
  end

  def prepare_debug_shell
    Dir.chdir(@tmpdir)
    puts "You are at #{@tmpdir}."
    if @agent_pid
      puts "You can find UstRouter dump files in 'dump'."
    end
  end

  def execute(code)
    code_path = "#{@tmpdir}/code.rb"
    write_file(code_path, code)

    result_path = "#{@tmpdir}/result"
    main_lib_path = "#{UnionStationHooks::LIBROOT}/union_station_hooks_core"
    passenger_simulator_path = "#{UnionStationHooks::ROOT}/spec/passenger_simulator"
    runner_path = "#{@tmpdir}/runner.rb"
    runner = %Q{
      if ENV['COVERAGE']
        require 'simplecov'
        SimpleCov.command_name('Inline code ' +
          #{Digest::MD5.hexdigest(@example_full_description).inspect})
        SimpleCov.start('test')
      end

      require #{main_lib_path.inspect}
      require #{passenger_simulator_path.inspect} if #{@simulate_load_passenger}
      UnionStationHooks.config[:union_station_key] = 'any-key'
      UnionStationHooks.config[:app_group_name] = 'any-app'
      UnionStationHooks.config[:ust_router_address] = 'tcp://not-relevant:1234'
      UnionStationHooks.config[:ust_router_password] = 'not-relevant'
      result = eval(File.read(#{code_path.inspect}), binding, #{code_path.inspect})
      File.open(#{result_path.inspect}, 'w') do |f|
        f.write(Marshal.dump(result))
      end
    }
    write_file(runner_path, runner)

    result = system('ruby', runner_path)
    if !result
      if $? && $?.termsig
        RSpec.world.wants_to_quit = true
      end
      raise "Error evaluating code:\n#{code}"
    end

    File.open(result_path, 'rb') do |f|
      Marshal.load(f.read)
    end
  end

  it 'is not vendored by default' do
    expect(UnionStationHooks.vendored?).to be_falsey
  end

  it 'does not allow initialization when Passenger is not loaded' do
    @simulate_load_passenger = false
    code = %Q{
      UnionStationHooks.should_initialize?
    }
    expect(execute(code)).to be_falsey
  end

  it 'allows initialization when Passenger is loaded and the "analytics" option is enabled' do
    code = %Q{
      UnionStationHooks.should_initialize?
    }
    expect(execute(code)).to be_truthy
  end

  it 'does not allow initialization when Passenger is loaded and the "analytics" option is disabled' do
    code = %Q{
      PhusionPassenger::App.options['analytics'] = false
      UnionStationHooks.should_initialize?
    }
    expect(execute(code)).to be_falsey
  end

  describe '#initialize!' do
    it 'initializes the Union Station hooks' do
      code = %Q{
        result = UnionStationHooks.initialize!
        {
          :result => result,
          :initialized => UnionStationHooks.initialized?,
          :vendored => UnionStationHooks.vendored?,
          :context_available => !UnionStationHooks.context.nil?,
          :app_group_name => UnionStationHooks.app_group_name,
          :key => UnionStationHooks.key
        }
      }
      expect(execute(code)).to eq(
        :result => true,
        :initialized => true,
        :vendored => false,
        :context_available => true,
        :app_group_name => 'any-app',
        :key => 'any-key'
      )
    end

    it 'freezes the configuration hash' do
      code = %Q{
        UnionStationHooks.initialize!
        {
          :config_frozen => UnionStationHooks.config.frozen?
        }
      }
      expect(execute(code)).to eq(
        :config_frozen => true
      )
    end

    it 'freezes the initializers list' do
      code = %Q{
        UnionStationHooks.initialize!
        {
          :initializers_frozen => UnionStationHooks.initializers.frozen?
        }
      }
      expect(execute(code)).to eq(
        :initializers_frozen => true
      )
    end

    it 'symbolizes configuration keys' do
      code = %Q{
        UnionStationHooks.config[:foo] = 1234
        UnionStationHooks.config['bar'] = 5678
        UnionStationHooks.initialize!
        UnionStationHooks.config
      }
      result = execute(code)
      expect(result[:foo]).to eq(1234)
      expect(result[:bar]).to eq(5678)
    end

    it 'does nothing when already initialized' do
      code = %Q{
        result = UnionStationHooks.initialize!
        result2 = UnionStationHooks.initialize!
        {
          :result => result,
          :result2 => result2,
          :initialized => UnionStationHooks.initialized?
        }
      }
      expect(execute(code)).to eq(
        :result => true,
        :result2 => true,
        :initialized => true
      )
    end

    it 'calls #initialize! on any registered initializers' do
      code = %Q{
        class Foo
          def self.initialize!
            $foo_initialized = true
          end
        end

        UnionStationHooks.initializers << Foo
        UnionStationHooks.initialize!
        {
          :foo_initialized => $foo_initialized
        }
      }
      expect(execute(code)).to eq(
        :foo_initialized => true
      )
    end

    specify 'UnionStationHooks.check_initialized does not raise an error' do
      code = %Q{
        UnionStationHooks.initialize!
        begin
          UnionStationHooks.check_initialized
          nil
        rescue RuntimeError => e
          e.message
        end
      }
      expect(execute(code)).to eq(nil)
    end
  end

  context 'when not initialized' do
    before :each do
      @env = { 'PASSENGER_TXN_ID' => '1234' }
    end

    specify 'UnionStationHooks.begin_rack_request returns nil' do
      code = %Q{
        result = UnionStationHooks.begin_rack_request(#{@env.inspect})
        {
          :result => result,
          :reporter_class_defined => !!defined?(UnionStationHooks::RequestReporter)
        }
      }
      expect(execute(code)).to eq(
        :result => nil,
        :reporter_class_defined => false
      )
    end

    specify 'UnionStationHooks.end_rack_request returns nil' do
      code = %Q{
        env = #{@env.inspect}
        result = UnionStationHooks.begin_rack_request(env)
        result2 = UnionStationHooks.end_rack_request(env)
        {
          :result => result,
          :result2 => result2,
          :reporter_class_defined => !!defined?(UnionStationHooks::RequestReporter)
        }
      }
      expect(execute(code)).to eq(
        :result => nil,
        :result2 => nil,
        :reporter_class_defined => false
      )
    end

    specify 'UnionStationHooks.check_initialized logs an error' do
      start_agent
      stderr_file = "#{@tmpdir}/stderr.log"
      code = %Q{
        STDERR.reopen(#{stderr_file.inspect})
        UnionStationHooks.config[:union_station_key] = 'any-key'
        UnionStationHooks.config[:app_group_name] = 'any-app'
        UnionStationHooks.config[:ust_router_address] = #{@socket_address.inspect}
        UnionStationHooks.config[:ust_router_password] = #{@password.inspect}
        UnionStationHooks.check_initialized
        nil
      }
      execute(code)
      expect(File.read(stderr_file)).to match(/The Union Station hooks are not initialized/)
      expect(read_dump_file(:internal_information)).to include('HOOKS_NOT_INITIALIZED')
    end

    specify 'UnionStationHooks.check_initialized initializes anyway' do
      start_agent
      stderr_file = "#{@tmpdir}/stderr.log"
      code = %Q{
        STDERR.reopen(#{stderr_file.inspect})
        UnionStationHooks.config[:union_station_key] = 'any-key'
        UnionStationHooks.config[:app_group_name] = 'any-app'
        UnionStationHooks.config[:ust_router_address] = #{@socket_address.inspect}
        UnionStationHooks.config[:ust_router_password] = #{@password.inspect}
        UnionStationHooks.check_initialized
        UnionStationHooks.initialized?
      }
      expect(execute(code)).to be_truthy
      expect(File.read(stderr_file)).to match(/The Union Station hooks are not initialized/)
    end

    specify 'UnionStationHooks.check_initialized does not log an error ' \
            'if :check_initialized is false' do
      code = %Q{
        module UnionStationHooks
          class << self
            def report_internal_information
              raise 'Expected UnionStationHooks.report_internal_information ' \
                'not to be called'
            end
          end
        end

        UnionStationHooks.config[:check_initialized] = false
        UnionStationHooks.check_initialized
        nil
      }
      execute(code)
    end

    specify 'UnionStationHooks.check_initialized does not initialize ' \
            'if :check_initialized is false' do
      code = %Q{
        UnionStationHooks.config[:check_initialized] = false
        UnionStationHooks.check_initialized
        UnionStationHooks.initialized?
      }
      expect(execute(code)).to eq(false)
    end
  end

  describe 'code upgrading' do
    let(:preamble_code) do
      %Q{
        module UnionStationHooks
          def self.old_method
            true
          end
        end

        UnionStationHooks.vendored = true

        load "\#{UnionStationHooks::LIBROOT}/union_station_hooks_core.rb"
      }
    end

    it 'overrides the existing vendored version of the UnionStationHooks namespace' do
      code = %Q{
        #{preamble_code}

        {
          :has_old_method => UnionStationHooks.respond_to?(:has_old_method),
          :vendored => UnionStationHooks.vendored?
        }
      }
      expect(execute(code)).to eq(
        :has_old_method => false,
        :vendored => false
      )
    end

    it 'restores the old configuration' do
      code = %Q{
        UnionStationHooks.config[:foo] = 1234
        #{preamble_code}
        UnionStationHooks.config[:foo]
      }
      expect(execute(code)).to eq(1234)
    end

    it 'restores the old initializers list' do
      code = %Q{
        UnionStationHooks.initializers << 1234
        #{preamble_code}
        UnionStationHooks.initializers
      }
      expect(execute(code)).to eq([1234])
    end

    it 'raises an error if the old UnionStationHooks was already initialized' do
      code = %Q{
        UnionStationHooks.initialize!
        begin
          load "\#{UnionStationHooks::LIBROOT}/union_station_hooks_core.rb"
          nil
        rescue RuntimeError => e
          e.message
        end
      }
      expect(execute(code)).to include(
        'alternative version was already loaded and initialized')
    end
  end
end
