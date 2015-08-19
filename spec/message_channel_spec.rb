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
      @writer.close
      expect(@reader.read).to be_nil
    end

    specify "#read_hash works" do
      @writer.write("hello", "world")
      expect(@reader.read_hash).to eq("hello" => "world")

      @writer.write("hello", "world", "foo", "bar", "", "...")
      expect(@reader.read_hash).to eq("hello" => "world", "foo" => "bar", "" => "...")
    end

    specify "#read_hash throws an exception if the array message doesn't have an even number of items" do
      @writer.write("foo")
      expect { @reader.read_hash }.to raise_error(MessageChannel::InvalidHashError)

      @writer.write("foo", "bar", "baz")
      expect { @reader.read_hash }.to raise_error(MessageChannel::InvalidHashError)
    end

    it "can read a single written scalar message" do
      @writer.write_scalar("hello world")
      expect(@reader.read_scalar).to eq("hello world")
    end

    it "can handle empty scalar messages" do
      @writer.write_scalar("")
      expect(@reader.read_scalar).to eq("")
    end

    it "properly detects end-of-file when reading a scalar message" do
      @writer.close
      expect(@reader.read_scalar).to be_nil
    end

    it "puts the data into the given buffer" do
      buffer = ''
      @writer.write_scalar("x" * 100)
      result = @reader.read_scalar(buffer)
      expect(result.object_id).to eq(buffer.object_id)
      expect(buffer).to eq("x" * 100)
    end

    it "raises SecurityError when a received scalar message's size is larger than a specified maximum" do
      @writer.write_scalar(" " * 100)
      expect { @reader.read_scalar('', 99) }.to raise_error(SecurityError)
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

    it "can handle scalar messages with arbitrary binary data" do
      garbage_files = ["garbage1.dat", "garbage2.dat", "garbage3.dat"]
      spawn_process do
        garbage_files.each do |name|
          data = File.binread("spec/#{name}")
          @channel.write_scalar(data)
        end
      end

      garbage_files.each do |name|
        data = File.binread("spec/#{name}")
        expect(@channel.read_scalar).to eq(data)
      end
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

    it "has stream properties" do
      garbage = File.binread("spec/garbage1.dat")
      spawn_process do
        @channel.write("hello", "world")
        @channel.write_scalar(garbage)
        @channel.write_scalar(":-)")

        a = @channel.read_scalar
        b = @channel.read
        b << a
        @channel.write(*b)
      end
      expect(@channel.read).to eq(["hello", "world"])
      expect(@channel.read_scalar).to eq(garbage)
      expect(@channel.read_scalar).to eq(":-)")

      @channel.write_scalar("TASTE MY WRATH! ULTIMATE SWORD TECHNIQUE!! DRAGON'S BREATH SL--")
      @channel.write("Uhm, watch your step.", "WAAHH?!", "Calm down, Motoko!!")
      expect(@channel.read).to eq(["Uhm, watch your step.", "WAAHH?!", "Calm down, Motoko!!",
        "TASTE MY WRATH! ULTIMATE SWORD TECHNIQUE!! DRAGON'S BREATH SL--"])
    end
  end
end

end # module UnionStationHooks
