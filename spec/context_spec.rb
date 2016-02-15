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
require 'stringio'
require 'tmpdir'
require 'fileutils'
UnionStationHooks.require_lib 'context'

module UnionStationHooks

describe Context do
  YESTERDAY = Time.utc(2010, 4, 11, 11, 56, 02)
  TODAY     = Time.utc(2010, 4, 11, 12, 56, 02)
  TOMORROW  = Time.utc(2010, 4, 11, 13, 56, 02)

  before :each do
    @username = 'logging'
    @password = '1234'
    @tmpdir   = Dir.mktmpdir
    @dump_dir = "#{@tmpdir}/dump"
    @socket_filename = "#{@dump_dir}/ust_router.socket"
    @socket_address  = "unix:#{@socket_filename}"
    @context  = Context.new(@socket_address, @username, @password, 'localhost')
    @context2 = Context.new(@socket_address, @username, @password, 'localhost')
    FileUtils.mkdir(@dump_dir)
  end

  after :each do
    @context.close
    @context2.close
    kill_agent
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    Timecop.return
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

  def new_transaction
    transaction = @context.new_transaction('foobar', :requests, 'any-key')
  end

  describe '#new_transaction' do
    it 'returns a Transaction that allows logging' do
      start_agent
      Timecop.freeze(TODAY)

      transaction = new_transaction
      expect(transaction).not_to be_null
      begin
        transaction.message("hello")
      ensure
        transaction.close
      end

      wait_for_dump_file_existance
      expect(read_dump_file).to match(/hello/)

      transaction = @context.new_transaction('foobar', :processes, 'any-key')
      expect(transaction).not_to be_null
      begin
        transaction.message('world')
      ensure
        transaction.close
      end

      eventually_expect_dump_file_to_match(/world/, 'processes')
    end

    it 'reestablishes the connection with the UstRouter when disconnected' do
      start_agent
      Timecop.freeze(TODAY)

      transaction = new_transaction
      expect(transaction).not_to be_null
      transaction.close

      connection = @context.instance_variable_get(:'@connection')
      connection.synchronize do
        connection.channel.io.close
        connection.channel = nil
      end

      transaction = new_transaction
      expect(transaction).not_to be_null
      begin
        transaction.message('hello')
      ensure
        transaction.close
      end

      eventually_expect_dump_file_to_match(/hello/)
    end

    it 'does not reconnect to the UstRouter for a short ' \
         'period of time if connecting failed' do
      @context.reconnect_timeout = 60
      @context.max_connect_tries = 1

      Timecop.freeze(TODAY)
      silence_warnings
      expect(new_transaction).to be_null

      Timecop.freeze(TODAY + 30)
      start_agent
      expect(new_transaction).to be_null

      Timecop.freeze(TODAY + 61)
      expect(new_transaction).not_to be_null
    end
  end

  describe '#continue_transaction' do
    it 'returns a Transaction that allows logging' do
      start_agent
      Timecop.freeze(TODAY)

      transaction = @context.new_transaction('foobar', :processes, 'any-key')
      begin
        transaction.message('hello')
        transaction2 = @context2.continue_transaction(transaction.txn_id,
          'foobar', :processes, 'any-key')
        expect(transaction2).not_to be_null
        expect(transaction2.txn_id).to eq(transaction.txn_id)
        begin
          transaction2.message('world')
        ensure
          transaction2.close
        end
      ensure
        transaction.close
      end

      eventually_expect_dump_file_to_match(
        /#{Regexp.escape transaction.txn_id} .* hello$/,
        'processes')
      eventually_expect_dump_file_to_match(
        /#{Regexp.escape transaction.txn_id} .* world$/,
        'processes')
    end

    it 'reestablishes the connection with the UstRouter when disconnected' do
      start_agent
      Timecop.freeze(TODAY)

      transaction = new_transaction
      expect(transaction).not_to be_null
      transaction.close
      transaction2 = @context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')
      expect(transaction2).not_to be_null
      transaction2.close

      connection = @context2.instance_variable_get(:'@connection')
      connection.synchronize do
        connection.channel.io.close
        connection.channel = nil
      end

      transaction2 = @context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')
      expect(transaction2).not_to be_null
      begin
        transaction2.message('hello')
      ensure
        transaction2.close
      end

      eventually_expect_dump_file_to_match(/hello/)
    end

    it 'does not reconnect to the UstRouter for a short period of time ' \
         'if connecting failed' do
      start_agent
      @context.reconnect_timeout = 60
      @context.max_connect_tries = 1
      @context2.reconnect_timeout = 60
      @context2.max_connect_tries = 1

      Timecop.freeze(TODAY)
      transaction = new_transaction
      expect(transaction).not_to be_null
      expect(@context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')).not_to be_null
      kill_agent
      silence_warnings
      expect(@context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')).to be_null

      Timecop.freeze(TODAY + 30)
      start_agent
      expect(@context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')).to be_null

      Timecop.freeze(TODAY + 61)
      expect(@context2.continue_transaction(transaction.txn_id,
        'foobar', :requests, 'any-key')).not_to be_null
    end
  end

  specify '#new_transaction and #continue_transaction eventually ' \
            'reestablish the connection to the UstRouter if the ' \
            'UstRouter crashed and was restarted' do
    start_agent
    Timecop.freeze(TODAY)

    transaction = new_transaction
    expect(transaction).not_to be_null
    @context2.continue_transaction(transaction.txn_id,
      'foobar', :requests, 'any-key').close
    kill_agent
    silence_warnings
    start_agent

    transaction = new_transaction
    expect(transaction).to be_null
    transaction2 = @context2.continue_transaction('1234-abcd',
      'foobar', :requests, 'any-key')
    expect(transaction2).to be_null

    Timecop.freeze(TODAY + 60)
    transaction = new_transaction
    expect(transaction).not_to be_null
    transaction.message('hello')
    transaction2 = @context2.continue_transaction(transaction.txn_id,
      'foobar', :requests, 'any-key')
    expect(transaction2).not_to be_null
    begin
      transaction2.message('world')
    ensure
      transaction2.close
    end
    transaction.close

    eventually_expect_dump_file_to_match(/hello/)
    eventually_expect_dump_file_to_match(/world/)
  end

  it 'only creates null Transaction objects if no server address is given' do
    core = Context.new(nil, nil, nil, nil)
    begin
      expect(core.new_transaction('foobar', :requests, 'any-key')).to be_null
    ensure
      core.close
    end
  end

  describe '#clear_connection' do
    it "closes the connection" do
      start_agent

      transaction = new_transaction
      expect(transaction).not_to be_null
      transaction.close

      @context.clear_connection
      connection = @context.instance_variable_get(:"@connection")
      connection.synchronize do
        expect(connection.channel).to be_nil
      end
    end
  end
end

end # module UnionStationHooks
