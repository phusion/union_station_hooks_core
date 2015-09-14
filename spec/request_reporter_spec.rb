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

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'tmpdir'
require 'fileutils'
require 'base64'
require 'digest/md5'

module UnionStationHooks

shared_examples_for 'a RequestReporter' do
  before :each do |example|
    @example_full_description = example.full_description
    @username = 'logging'
    @password = '1234'
    @tmpdir   = Dir.mktmpdir
    @dump_dir = "#{@tmpdir}/dump"
    @socket_filename = "#{@dump_dir}/ust_router.socket"
    @socket_address  = "unix:#{@socket_filename}"
    FileUtils.mkdir(@dump_dir)
  end

  after :each do
    kill_agent
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    UnionStationHooks::Log.warn_callback = nil
  end

  def start_agent
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
    puts "You can find UstRouter dump files in 'dump'."
  end

  describe '#log_request_begin' do
    it "logs the 'app request handler processing' activity's begin" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_request_begin
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: app request handler processing (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_request_begin
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_request_begin\n")
    end
  end

  describe '#log_request_end' do
    it "logs the 'app request handler processing' acitivty's end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_request_end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.
          include?('END: app request handler processing (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_request_end
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_request_end\n")
    end
  end

  describe '#log_gc_stats_on_request_begin' do
    # The behavior is highly specific to Ruby implementations,
    # so there is not much we can test automatically.

    it 'does not crash' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_gc_stats_on_request_begin
      }
      start_agent
      execute(code)
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_gc_stats_on_request_begin
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_gc_stats_on_request_begin\n")
    end
  end

  describe '#log_gc_stats_on_request_end' do
    # The behavior is highly specific to Ruby implementations,
    # so there is not much we can test automatically.

    it 'does not crash' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_gc_stats_on_request_end
      }
      start_agent
      execute(code)
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_gc_stats_on_request_end
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_gc_stats_on_request_end\n")
    end
  end

  describe '#log_controller_action_block' do
    it "logs the 'framework request processing' activity's begin and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_controller_action_block do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: framework request processing (')
      end
      eventually do
        read_dump_file.include?('END: framework request processing (')
      end
    end

    it 'logs the controller action' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :controller_name => 'PostsController',
          :action_name => 'create'
        }
        reporter.log_controller_action_block(options) do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.
          include?("Controller action: PostsController#create\n")
      end
    end

    it 'logs the application request method' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :method => 'PUT'
        }
        reporter.log_controller_action_block(options) do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Application request method: PUT\n")
      end
    end

    it 'raises an exception if :controller_name is given without :action_name' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :controller_name => 'PostsController'
        }
        begin
          reporter.log_controller_action_block(options) do
            # Do nothing
          end
          false
        rescue ArgumentError => e
          e.message =~ /action_name/
        end
      }
      start_agent
      expect(execute(code)).to be_truthy
    end

    it "yields the block and returns its return value" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :controller_name => 'PostsController',
          :action_name => 'create'
        }
        reporter.log_controller_action_block(options) do
          1234
        end
      }
      start_agent
      expect(execute(code)).to eq(1234)
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_controller_action_block do
            # Do nothing
          end
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_controller_action_block\n")
      end

      it "yields the block and returns its return value" do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          reporter = create_reporter
          reporter.log_controller_action_block do
            1234
          end
        }
        expect(execute(code)).to eq(1234)
      end
    end
  end

  describe '#log_controller_action' do
    it "logs the 'framework request processing' activity's begin and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_controller_action(
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now
        )
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: framework request processing (')
      end
      eventually do
        read_dump_file.include?('END: framework request processing (')
      end
    end

    it 'logs the controller action' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :controller_name => 'PostsController',
          :action_name => 'create'
        }
        reporter.log_controller_action(options) do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Controller action: PostsController#create\n")
      end
    end

    it 'logs the application request method' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :method => 'PUT'
        }
        reporter.log_controller_action(options)
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Application request method: PUT\n")
      end
    end

    it 'raises an exception if :controller_name is given without :action_name' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :controller_name => 'PostsController'
        }
        begin
          reporter.log_controller_action(options)
          false
        rescue ArgumentError => e
          e.message =~ /action_name/
        end
      }
      start_agent
      expect(execute(code)).to be_truthy
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now
        }
        reporter.log_controller_action(options)
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_controller_action\n")
    end
  end

  describe '#log_view_rendering_block' do
    it "logs the 'view rendering' activity's begin and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_view_rendering_block do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: view rendering (')
      end
      eventually do
        read_dump_file.include?('END: view rendering (')
      end
    end

    it "yields the block's and returns its return value" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_view_rendering_block do
          1234
        end
      }
      start_agent
      expect(execute(code)).to eq(1234)
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_view_rendering_block do
            # Do nothing
          end
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_view_rendering_block\n")
      end

      it "yields the block and returns its return value" do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          reporter = create_reporter
          reporter.log_view_rendering_block do
            1234
          end
        }
        expect(execute(code)).to eq(1234)
      end
    end
  end

  describe '#log_view_rendering' do
    it "logs the 'view rendering' activity's begin and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now
        }
        reporter.log_view_rendering(options)
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: view rendering (')
      end
      eventually do
        read_dump_file.include?('END: view rendering (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now
        }
        reporter.log_view_rendering(options)
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_view_rendering\n")
    end
  end

  describe '#log_activity_block' do
    it "logs the specified activity's beginning and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_activity_block('foo') do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: foo (')
      end
      eventually do
        read_dump_file.include?('END: foo (')
      end
    end

    it 'yields the block and returns its return value' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_activity_block('foo') do
          1234
        end
      }
      start_agent
      expect(execute(code)).to eq(1234)
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_activity_block('foo') do
            # Do nothing
          end
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_activity_block\n")
      end

      it "yields the block and returns its return value" do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          reporter = create_reporter
          reporter.log_activity_block('foo') do
            1234
          end
        }
        expect(execute(code)).to eq(1234)
      end
    end
  end

  describe '#log_activity_begin' do
    it "logs the specified activity's begin" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_activity_begin('foo')
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: foo (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_activity_begin('foo')
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_activity_begin\n")
    end
  end

  describe '#log_activity_end' do
    it "logs the specified activity's end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_activity_end('foo')
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('END: foo (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_activity_end('foo')
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_activity_end\n")
    end
  end

  describe '#log_activity' do
    it "logs the specified activity's beginning and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_activity('foo', UnionStationHooks.now,
          UnionStationHooks.now)
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: foo (')
      end
      eventually do
        read_dump_file.include?('END: foo (')
      end
    end

    it 'does nothing when in null mode' do
      code = %Q{
        UnionStationHooks.initialize!
        silence_warnings
        hook_request_reporter_do_nothing_on_null
        reporter = create_reporter
        reporter.log_activity('foo', UnionStationHooks.now,
          UnionStationHooks.now)
      }
      execute(code)
      expect(read_dump_file('debug')).to \
        include("Doing nothing: log_activity\n")
    end
  end

  describe '#log_benchmark_block' do
    it "logs the benchmark activity's beginning and end" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_benchmark_block do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: BENCHMARK: Benchmarking (')
      end
      eventually do
        read_dump_file.include?('END: BENCHMARK: Benchmarking (')
      end
    end

    it 'allows customizing the title' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_benchmark_block('foo') do
          # Do nothing
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?('BEGIN: BENCHMARK: foo (')
      end
      eventually do
        read_dump_file.include?('END: BENCHMARK: foo (')
      end
    end

    it "yields the block and returns its return value" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_benchmark_block do
          1234
        end
      }
      start_agent
      expect(execute(code)).to eq(1234)
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_benchmark_block do
            # Do nothing
          end
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_benchmark_block\n")
      end

      it "yields the block and returns its return value" do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          reporter = create_reporter
          reporter.log_benchmark_block do
            1234
          end
        }
        expect(execute(code)).to eq(1234)
      end
    end
  end

  describe '#log_exception' do
    it 'logs exception information' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        begin
          raise EOFError, 'file has ended'
        rescue => e
          reporter.log_exception(e)
        end
      }
      start_agent
      execute(code)

      wait_for_dump_file_existance('exceptions')
      eventually do
        read_dump_file('exceptions').include?('Message: ')
      end
      read_dump_file('exceptions') =~ /Message: (.+)/
      expect(Base64.decode64($1)).to eq('file has ended')

      eventually do
        read_dump_file('exceptions').
          include?("Class: EOFError\n")
      end
      eventually do
        read_dump_file('exceptions') =~ /Backtrace: .+/
      end
    end

    it 'logs the transaction ID' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        begin
          raise EOFError, 'file has ended'
        rescue => e
          reporter.log_exception(e)
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance('exceptions')
      eventually do
        read_dump_file('exceptions').
          include?("Request transaction ID: txn-1234\n")
      end
    end

    it 'logs the associated controller information ' \
         'if log_controller_action_block was called' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :controller_name => 'PostsController',
          :action_name => 'create'
        }
        reporter.log_controller_action_block(options) do
          begin
            raise EOFError, 'file has ended'
          rescue => e
            reporter.log_exception(e)
          end
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance('exceptions')
      eventually do
        read_dump_file('exceptions').
          include?("Controller action: PostsController#create\n")
      end
    end

    it 'logs the associated controller information ' \
         'if log_controller_action was called' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :controller_name => 'PostsController',
          :action_name => 'create'
        }
        reporter.log_controller_action(options)
        begin
          raise EOFError, 'file has ended'
        rescue => e
          reporter.log_exception(e)
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance('exceptions')
      eventually do
        read_dump_file('exceptions').
          include?("Controller action: PostsController#create\n")
      end
    end

    it 'does not log the associated controller information ' \
         'if log_controller_action* was not called' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        begin
          raise EOFError, 'file has ended'
        rescue => e
          reporter.log_exception(e)
        end
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance('exceptions')
      should_never_happen do
        read_dump_file('exceptions').include?('Controller action: ')
      end
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          reporter = create_reporter
          hook_request_reporter_do_nothing_on_null
          begin
            raise EOFError, 'file has ended'
          rescue => e
            reporter.log_exception(e)
          end
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_exception\n")
      end
    end
  end

  describe '#log_database_query' do
    it 'logs the name and query string' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :name => 'ActiveRecord',
          :query => 'SELECT * FROM foo'
        }
        reporter.log_database_query(options)
      }
      start_agent
      execute(code)

      wait_for_dump_file_existance
      eventually do
        File.exist?(dump_file_path) &&
          read_dump_file.include?('BEGIN: DB BENCHMARK: ')
      end
      read_dump_file =~ /DB BENCHMARK: .+? \(.+?\) (.+)/
      extra_info_base64 = $1

      extra_info = Base64.decode64(extra_info_base64)
      expect(extra_info).to eq("ActiveRecord\nSELECT * FROM foo")
    end

    it "uses 'SQL' as default value for the name" do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now,
          :query => 'SELECT * FROM foo'
        }
        reporter.log_database_query(options)
      }
      start_agent
      execute(code)

      wait_for_dump_file_existance
      eventually do
        File.exist?(dump_file_path) &&
          read_dump_file.include?('BEGIN: DB BENCHMARK: ')
      end
      read_dump_file =~ /DB BENCHMARK: .+? \(.+?\) (.+)/
      extra_info_base64 = $1

      extra_info = Base64.decode64(extra_info_base64)
      expect(extra_info).to eq("SQL\nSELECT * FROM foo")
    end

    it 'raises an error if no query was given' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        options = {
          :begin_time => UnionStationHooks.now,
          :end_time => UnionStationHooks.now
        }
        begin
          reporter.log_database_query(options)
          false
        rescue ArgumentError => e
          e.message =~ /query/
        end
      }
      start_agent
      expect(execute(code)).to be_truthy
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          options = {
            :begin_time => UnionStationHooks.now,
            :end_time => UnionStationHooks.now,
            :query => 'SELECT * FROM foo'
          }
          reporter.log_database_query(options)
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_database_query\n")
      end
    end
  end

  describe '#log_cache_hit' do
    it 'logs the cache hit' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_cache_hit('/users/1')
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Cache hit: /users/1\n")
      end
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_cache_hit('/users/1')
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_cache_hit\n")
      end
    end
  end

  describe '#log_cache_miss' do
    it 'logs the cache miss without miss cost duration information ' \
         'if no miss cost duration is given' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_cache_miss('/users/1')
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Cache miss: /users/1\n")
      end
    end

    it 'logs the cache miss and the miss cost duration' do
      code = %Q{
        UnionStationHooks.initialize!
        reporter = create_reporter
        reporter.log_cache_miss('/users/1', 5000)
      }
      start_agent
      execute(code)
      wait_for_dump_file_existance
      eventually do
        read_dump_file.include?("Cache miss (5000 usec): /users/1\n")
      end
    end

    context 'when in null mode' do
      it 'does nothing' do
        code = %Q{
          UnionStationHooks.initialize!
          silence_warnings
          hook_request_reporter_do_nothing_on_null
          reporter = create_reporter
          reporter.log_cache_miss('/users/1')
        }
        execute(code)
        expect(read_dump_file('debug')).to \
          include("Doing nothing: log_cache_miss\n")
      end
    end
  end
end

RUBY_VERSIONS_TO_TEST.each do |spec|
  describe "RequestReporter on #{spec['name']}" do
    let(:ruby_name) { spec['name'] }
    let(:ruby_command) { spec['command'] }

    it_should_behave_like 'a RequestReporter'
  end
end

end
