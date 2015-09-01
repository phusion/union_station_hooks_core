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
require 'socket'
UnionStationHooks.require_lib 'message_channel'

module UnionStationHooks

describe MessageChannel do
  describe "scenarios with a single channel" do
    before :each do
      @reader_pipe, @writer_pipe = IO.pipe
      @reader = MessageChannel.new(@reader_pipe)
      @writer = MessageChannel.new(@writer_pipe)
    end

    after :each do
      @reader_pipe.close unless @reader_pipe.closed?
      @writer_pipe.close unless @writer_pipe.closed?
    end

    it "can read a single written array message" do
      @writer.write("hello")
      expect(@reader.read).to eq(["hello"])
    end

    it "can handle array messages that contain spaces" do
      @writer.write("hello world", "! ")
      expect(@reader.read).to eq(["hello world", "! "])
    end

    it "can handle array messages that have only a single empty string" do
      @writer.write("")
      expect(@reader.read).to eq([""])
    end

    it "can handle array messages with empty arguments" do
      @writer.write("hello", "", "world")
      expect(@reader.read).to eq(["hello", "", "world"])

      @writer.write("")
      expect(@reader.read).to eq([""])

      @writer.write(nil, "foo")
      expect(@reader.read).to eq(["", "foo"])
    end

    it "properly detects end-of-file when reading an array message" do
      @writer.io.close
      expect(@reader.read).to be_nil
    end
  end

  describe "scenarios with 2 channels and 2 concurrent processes" do
    after :each do
      @parent_socket.close
      Process.waitpid(@pid) rescue nil
    end

    def spawn_process
      @parent_socket, @child_socket = UNIXSocket.pair
      @pid = fork do
        @parent_socket.close
        @channel = MessageChannel.new(@child_socket)
        begin
          yield
        rescue Exception => e
          STDERR.puts("#{e} (#{e.class})\n#{e.backtrace.join("\n")}")
        ensure
          @child_socket.close
          exit!
        end
      end
      @child_socket.close
      @channel = MessageChannel.new(@parent_socket)
    end

    it "both processes can read and write a single array message" do
      spawn_process do
        x = @channel.read
        @channel.write("#{x[0]}!")
      end
      @channel.write("hello")
      expect(@channel.read).to eq(["hello!"])
    end

    it "supports large amounts of data" do
      iterations = 1000
      blob = "123" * 1024
      spawn_process do
        iterations.times do |i|
          @channel.write(blob)
        end
      end
      iterations.times do
        expect(@channel.read).to eq([blob])
      end
    end
  end
end

end # module UnionStationHooks
