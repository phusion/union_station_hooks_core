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

describe Transaction do
  before :each do
    @username  = "logging"
    @password  = "1234"
    @tmpdir    = Dir.mktmpdir
    @core      = Core.new(@socket_address, @username, @password, "localhost")
  end

  after :each do
    @core.close
    kill_agent
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    Timecop.return
  end

  def start_agent
    @agent_pid, @socket_filename, @socket_address = spawn_ust_router(
      @tmpdir, @password, DEBUG)
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

  it "becomes null once it is closed" do
    start_agent
    transaction = @core.new_transaction("foobar")
    transaction.close
    transaction.should be_null
  end

  it "does nothing if it's null" do
    start_agent
    logger = Core.new(nil, nil, nil, nil)
    begin
      transaction = logger.new_transaction("foobar")
      transaction.message("hello")
      transaction.close(true)
    ensure
      logger.close
    end

    File.exist?("#{@log_dir}/1").should be_false
  end

  describe "#begin_measure" do
    it "sends a BEGIN message" do
      start_agent
      transaction = @core.new_transaction("foobar")
      begin
        transaction.should_receive(:message).with(/^BEGIN: hello \(.+?,.+?,.+?\) $/)
        transaction.begin_measure("hello")
      ensure
        transaction.close
      end
    end

    it "adds extra information as base64" do
      start_agent
      transaction = @core.new_transaction("foobar")
      begin
        transaction.should_receive(:message).with(/^BEGIN: hello \(.+?,.+?,.+?\) YWJjZA==$/)
        transaction.begin_measure("hello", "abcd")
      ensure
        transaction.close
      end
    end
  end

  describe "#end_measure" do
    it "sends an END message if error_countered=false" do
      start_agent
      transaction = @core.new_transaction("foobar")
      begin
        transaction.should_receive(:message).with(/^END: hello \(.+?,.+?,.+?\)$/)
        transaction.end_measure("hello")
      ensure
        transaction.close
      end
    end

    it "sends a FAIL message if error_countered=true" do
      start_agent
      transaction = @core.new_transaction("foobar")
      begin
        transaction.should_receive(:message).with(/^FAIL: hello \(.+?,.+?,.+?\)$/)
        transaction.end_measure("hello", true)
      ensure
        transaction.close
      end
    end
  end
end

end # module UnionStationHooks
