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

describe Transaction do
  before :each do
    @username = "logging"
    @password = "1234"
    @tmpdir   = Dir.mktmpdir
    @socket_filename = "#{@tmpdir}/ust_router.socket"
    @socket_address  = "unix:#{@socket_filename}"
    @context = Context.new(@socket_address, @username, @password, "localhost")
  end

  after :each do
    @context.close
    kill_agent
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    Timecop.return
    UnionStationHooks::Log.warn_callback = nil
  end

  def start_agent
    @agent_pid = spawn_ust_router(@tmpdir, @socket_filename, @password)
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

  it "becomes null once it is closed" do
    start_agent
    transaction = @context.new_transaction("foobar")
    expect(transaction).not_to be_null
    transaction.close
    expect(transaction).to be_null
  end

  it "does nothing if it's null" do
    start_agent
    logger = Context.new(nil, nil, nil, nil)
    begin
      transaction = logger.new_transaction('foobar')
      expect(transaction).to be_null
      transaction.message('hello')
      transaction.close(true)
    ensure
      logger.close
    end

    expect(File.exist?(dump_file_path)).to be_falsey
  end

  describe '#log_activity_begin' do
    before :each do
      start_agent
      @transaction = @context.new_transaction('foobar')
      expect(@transaction).not_to be_null
    end

    after :each do
      @transaction.close
    end

    it 'logs a BEGIN message' do
      expect(@transaction).to receive(:message).with(
        /^BEGIN: hello \(.+?\) $/)
      @transaction.log_activity_begin('hello')
    end

    it 'adds extra information as base64' do
      expect(@transaction).to receive(:message).with(
        /^BEGIN: hello \(.+?\) YWJjZA==$/)
      @transaction.log_activity_begin('hello', UnionStationHooks.now, 'abcd')
    end

    it 'accepts a TimePoint as time' do
      expect(@transaction).to receive(:message).with(
        /^BEGIN: hello \([a-z0-9]+,[a-z0-9]+,[a-z0-9]+\) $/)
      @transaction.log_activity_begin('hello', UnionStationHooks.now)
    end

    it 'accepts a Time as time, but outputs less detailed information' do
      expect(@transaction).to receive(:message).with(
        /^BEGIN: hello \([a-z0-9]+\) $/)
      @transaction.log_activity_begin('hello', Time.now)
    end
  end

  describe '#log_activity_end' do
    before :each do
      start_agent
      @transaction = @context.new_transaction('foobar')
      expect(@transaction).not_to be_null
    end

    after :each do
      @transaction.close
    end

    context 'if has_error=false' do
      it 'logs an END message' do
        expect(@transaction).to receive(:message).with(
          /^END: hello \(.+?\)$/)
        @transaction.log_activity_end('hello')
      end

      it 'accepts a TimePoint as time' do
        expect(@transaction).to receive(:message).with(
          /^END: hello \([a-z0-9]+,[a-z0-9]+,[a-z0-9]+\)$/)
        @transaction.log_activity_end('hello', UnionStationHooks.now)
      end

      it 'accepts a Time as time, but outputs less detailed information' do
        expect(@transaction).to receive(:message).with(
          /^END: hello \([a-z0-9]+\)$/)
        @transaction.log_activity_end('hello', Time.now)
      end
    end

    context 'if has_error=true' do
      it 'logs a FAIL message' do
        expect(@transaction).to receive(:message).with(
          /^FAIL: hello \(.+?\)$/)
        @transaction.log_activity_end('hello', UnionStationHooks.now, true)
      end

      it 'accepts a TimePoint as time' do
        expect(@transaction).to receive(:message).with(
          /^FAIL: hello \([a-z0-9]+,[a-z0-9]+,[a-z0-9]+\)$/)
        @transaction.log_activity_end('hello', UnionStationHooks.now, true)
      end

      it 'accepts a Time as time, but outputs less detailed information' do
        expect(@transaction).to receive(:message).with(
          /^FAIL: hello \([a-z0-9]+\)$/)
        @transaction.log_activity_end('hello', Time.now, true)
      end
    end
  end
end

end # module UnionStationHooks
