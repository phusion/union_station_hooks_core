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
UnionStationHooks.require_lib 'core'

module UnionStationHooks

describe Core do
  YESTERDAY = Time.utc(2010, 4, 11, 11, 56, 02)
  TODAY     = Time.utc(2010, 4, 11, 12, 56, 02)
  TOMORROW  = Time.utc(2010, 4, 11, 13, 56, 02)

  before :each do
    @username = "logging"
    @password = "1234"
    @tmpdir   = Dir.mktmpdir
    @socket_filename = "#{@tmpdir}/ust_router.socket"
    @socket_address  = "unix:#{@socket_filename}"
    @core  = Core.new(@socket_address, @username, @password, "localhost")
    @core2 = Core.new(@socket_address, @username, @password, "localhost")
  end

  after :each do
    @core.close
    @core2.close
    kill_agent
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    Timecop.return
    UnionStationHooks::Log.warn_callback = nil
  end

  def start_agent
    @agent_pid = spawn_ust_router(@tmpdir, @socket_filename, @password, DEBUG)
  end

  def kill_agent
    if @agent_pid
      Process.kill('KILL', @agent_pid)
      Process.waitpid(@agent_pid)
      File.unlink(@socket_filename)
      @agent_pid = nil
    end
  end

  def dump_file_path(category = "requests")
    "#{@tmpdir}/#{category}"
  end

  def read_dump_file(category = "requests")
    File.read(dump_file_path(category))
  end

  def silence_warnings
    UnionStationHooks::Log.warn_callback = lambda { |message| }
  end

  describe "#new_transaction" do
    it "returns a Transaction that allows logging" do
      start_agent
      Timecop.freeze(TODAY)

      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      begin
        transaction.message("hello")
      ensure
        transaction.close(true)
      end

      expect(read_dump_file).to match(/hello/)

      transaction = @core.new_transaction("foobar", :processes)
      expect(transaction).not_to be_null
      begin
        transaction.message("world")
      ensure
        transaction.close(true)
      end

      expect(read_dump_file("processes")).to match(/world/)
    end

    it "reestablishes the connection with the UstRouter when disconnected" do
      start_agent
      Timecop.freeze(TODAY)

      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      transaction.close(true)

      connection = @core.instance_variable_get(:"@connection")
      connection.synchronize do
        connection.channel.close
        connection.channel = nil
      end

      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      begin
        transaction.message("hello")
      ensure
        transaction.close(true)
      end

      expect(read_dump_file).to match(/hello/)
    end

    it "does not reconnect to the UstRouter for a short period of time if connecting failed" do
      @core.reconnect_timeout = 60
      @core.max_connect_tries = 1

      Timecop.freeze(TODAY)
      silence_warnings
      expect(@core.new_transaction("foobar")).to be_null

      Timecop.freeze(TODAY + 30)
      start_agent
      expect(@core.new_transaction("foobar")).to be_null

      Timecop.freeze(TODAY + 61)
      expect(@core.new_transaction("foobar")).not_to be_null
    end
  end

  describe "#continue_transaction" do
    it "returns a Transaction that allows logging" do
      start_agent
      Timecop.freeze(TODAY)

      transaction = @core.new_transaction("foobar", :processes)
      begin
        transaction.message("hello")
        transaction2 = @core2.continue_transaction(transaction.txn_id, "foobar", :processes)
        expect(transaction2).not_to be_null
        expect(transaction2.txn_id).to eq(transaction.txn_id)
        begin
          transaction2.message("world")
        ensure
          transaction2.close(true)
        end
      ensure
        transaction.close(true)
      end

      expect(read_dump_file("processes")).to match(/#{Regexp.escape transaction.txn_id} .* hello$/)
      expect(read_dump_file("processes")).to match(/#{Regexp.escape transaction.txn_id} .* world$/)
    end

    it "reestablishes the connection with the UstRouter when disconnected" do
      start_agent
      Timecop.freeze(TODAY)

      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      transaction.close(true)
      transaction2 = @core2.continue_transaction(transaction.txn_id, "foobar")
      expect(transaction2).not_to be_null
      transaction2.close(true)

      connection = @core2.instance_variable_get(:"@connection")
      connection.synchronize do
        connection.channel.close
        connection.channel = nil
      end

      transaction2 = @core2.continue_transaction(transaction.txn_id, "foobar")
      expect(transaction2).not_to be_null
      begin
        transaction2.message("hello")
      ensure
        transaction2.close(true)
      end

      expect(read_dump_file).to match(/hello/)
    end

    it "does not reconnect to the UstRouter for a short period of time if connecting failed" do
      start_agent
      @core.reconnect_timeout = 60
      @core.max_connect_tries = 1
      @core2.reconnect_timeout = 60
      @core2.max_connect_tries = 1

      Timecop.freeze(TODAY)
      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      expect(@core2.continue_transaction(transaction.txn_id, "foobar")).not_to be_null
      kill_agent
      silence_warnings
      expect(@core2.continue_transaction(transaction.txn_id, "foobar")).to be_null

      Timecop.freeze(TODAY + 30)
      start_agent
      expect(@core2.continue_transaction(transaction.txn_id, "foobar")).to be_null

      Timecop.freeze(TODAY + 61)
      expect(@core2.continue_transaction(transaction.txn_id, "foobar")).not_to be_null
    end
  end

  specify "#new_transaction and #continue_transaction eventually reestablish the connection to the UstRouter if the UstRouter crashed and was restarted" do
    start_agent
    Timecop.freeze(TODAY)

    transaction = @core.new_transaction("foobar")
    expect(transaction).not_to be_null
    @core2.continue_transaction(transaction.txn_id, "foobar").close
    kill_agent
    start_agent

    transaction = @core.new_transaction("foobar")
    expect(transaction).to be_null
    transaction2 = @core2.continue_transaction("1234-abcd", "foobar")
    expect(transaction2).to be_null

    Timecop.freeze(TODAY + 60)
    transaction = @core.new_transaction("foobar")
    expect(transaction).not_to be_null
    transaction.message("hello")
    transaction2 = @core2.continue_transaction(transaction.txn_id, "foobar")
    expect(transaction2).not_to be_null
    begin
      transaction2.message("world")
    ensure
      transaction2.close(true)
    end
    transaction.close(true)

    expect(read_dump_file).to match(/hello/)
    expect(read_dump_file).to match(/world/)
  end

  it "only creates null Transaction objects if no server address is given" do
    core = Core.new(nil, nil, nil, nil)
    begin
      expect(core.new_transaction("foobar")).to be_null
    ensure
      core.close
    end
  end

  describe "#clear_connection" do
    it "closes the connection" do
      start_agent

      transaction = @core.new_transaction("foobar")
      expect(transaction).not_to be_null
      transaction.close

      @core.clear_connection
      connection = @core.instance_variable_get(:"@connection")
      connection.synchronize do
        expect(connection.channel).to be_nil
      end
    end
  end
end

end # module UnionStationHooks
