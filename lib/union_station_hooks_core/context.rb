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

require 'thread'
require 'socket'
UnionStationHooks.require_lib 'connection'
UnionStationHooks.require_lib 'transaction'
UnionStationHooks.require_lib 'log'
UnionStationHooks.require_lib 'lock'
UnionStationHooks.require_lib 'utils'

module UnionStationHooks
  # A Context object is the "heart" of all `union_station_hooks_*` gems. It
  # contains a connection to the UstRouter (through a Connection object)
  # and allows you to create Transaction objects.
  #
  # Context is a singleton. During initialization
  # (`UnionStationHooks.initialize!`), an instance is created and stored in
  # `UnionStationHooks.context`. All the public API methods make use of this
  # singleton context.
  #
  # See hacking/Architecture.md for an overview.
  #
  # @private
  class Context
    RETRY_SLEEP = 0.2
    NETWORK_ERRORS = [
      Errno::EPIPE, Errno::ECONNREFUSED, Errno::ECONNRESET,
      Errno::EHOSTUNREACH, Errno::ENETDOWN, Errno::ENETUNREACH,
      Errno::ETIMEDOUT
    ]

    include Utils

    attr_accessor :max_connect_tries
    attr_accessor :reconnect_timeout

    def initialize(ust_router_address, username, password, node_name)
      UnionStationHooks::IOLogging.disable do
        @server_address = ust_router_address
        @username = username
        @password = password
        if node_name && !node_name.empty?
          @node_name = node_name
        else
          @node_name = `hostname`.strip
        end
        @random_dev = File.open('/dev/urandom')

        # This mutex protects the following instance variables, but
        # not the contents of @connection.
        @mutex = Mutex.new

        @connection = Connection.new(nil)
        if @server_address && local_socket_address?(@server_address)
          @max_connect_tries = 10
        else
          @max_connect_tries = 1
        end
        @reconnect_timeout = 1
        @next_reconnect_time = Time.utc(1980, 1, 1)
      end
    end

    def connection
      @mutex.synchronize do
        @connection
      end
    end

    def clear_connection
      @mutex.synchronize do
        @connection.synchronize do
          UnionStationHooks::IOLogging.disable do
            @random_dev = File.open('/dev/urandom') if @random_dev.closed?
            @connection.unref
            @connection = Connection.new(nil)
          end
        end
      end
    end

    def close
      @mutex.synchronize do
        @connection.synchronize do
          UnionStationHooks::IOLogging.disable do
            @random_dev.close
            @connection.unref
            @connection = nil
          end
        end
      end
    end

    def new_transaction(group_name, category, key)
      if !@server_address
        return Transaction.new(nil, nil)
      elsif !group_name || group_name.empty?
        raise ArgumentError, 'Group name may not be empty'
      end

      UnionStationHooks::IOLogging.disable do
        txn_id = create_txn_id

        Lock.new(@mutex).synchronize do |_lock|
          if Time.now < @next_reconnect_time
            return Transaction.new(nil, nil)
          end

          Lock.new(@connection.mutex).synchronize do |connection_lock|
            if !@connection.connected?
              begin
                connect
                connection_lock.reset(@connection.mutex)
              rescue SystemCallError, IOError
                @connection.disconnect
                UnionStationHooks::Log.warn(
                  "Cannot connect to the UstRouter at #{@server_address}; " \
                  "retrying in #{@reconnect_timeout} second(s).")
                @next_reconnect_time = Time.now + @reconnect_timeout
                return Transaction.new(nil, nil)
              rescue Exception => e
                @connection.disconnect
                raise e
              end
            end

            begin
              @connection.channel.write('openTransaction',
                txn_id, group_name, '', category,
                Utils.encoded_timestamp,
                key,
                true,
                true)
              result = @connection.channel.read
              if result[0] != 'status'
                raise "Expected UstRouter to respond with 'status', " \
                  "but got #{result.inspect} instead"
              elsif result[1] == 'ok'
                # Do nothing
              elsif result[1] == 'error'
                if result[2]
                  raise "Unable to close transaction: #{result[2]}"
                else
                  raise 'Unable to close transaction (no server message given)'
                end
              else
                raise "Expected UstRouter to respond with 'ok' or 'error', " \
                  "but got #{result.inspect} instead"
              end

              return Transaction.new(@connection, txn_id)
            rescue SystemCallError, IOError
              @connection.disconnect
              UnionStationHooks::Log.warn(
                "The UstRouter at #{@server_address}" \
                ' closed the connection; will reconnect in ' \
                "#{@reconnect_timeout} second(s).")
              @next_reconnect_time = Time.now + @reconnect_timeout
              return Transaction.new(nil, nil)
            rescue Exception => e
              @connection.disconnect
              raise e
            end
          end
        end
      end
    end

    def continue_transaction(txn_id, group_name, category, key)
      if !@server_address
        return Transaction.new(nil, nil)
      elsif !txn_id || txn_id.empty?
        raise ArgumentError, 'Transaction ID may not be empty'
      end

      UnionStationHooks::IOLogging.disable do
        Lock.new(@mutex).synchronize do |_lock|
          if Time.now < @next_reconnect_time
            return Transaction.new(nil, nil)
          end

          Lock.new(@connection.mutex).synchronize do |connection_lock|
            if !@connection.connected?
              begin
                connect
                connection_lock.reset(@connection.mutex)
              rescue SystemCallError, IOError
                @connection.disconnect
                UnionStationHooks::Log.warn(
                  "Cannot connect to the UstRouter at #{@server_address}; " \
                  "retrying in #{@reconnect_timeout} second(s).")
                @next_reconnect_time = Time.now + @reconnect_timeout
                return Transaction.new(nil, nil)
              rescue Exception => e
                @connection.disconnect
                raise e
              end
            end

            begin
              @connection.channel.write('openTransaction',
                txn_id, group_name, '', category,
                Utils.encoded_timestamp,
                key,
                true)
              return Transaction.new(@connection, txn_id)
            rescue SystemCallError, IOError
              @connection.disconnect
              UnionStationHooks::Log.warn(
                "The UstRouter at #{@server_address}" \
                ' closed the connection; will reconnect in ' \
                "#{@reconnect_timeout} second(s).")
              @next_reconnect_time = Time.now + @reconnect_timeout
              return Transaction.new(nil, nil)
            rescue Exception => e
              @connection.disconnect
              raise e
            end
          end
        end
      end
    end

  private

    RANDOM_CHARS = %w(
      a b c d e f g h i j k l m n o p q r s t u v w x y z
      A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
      0 1 2 3 4 5 6 7 8 9
    )

    def connect
      socket  = connect_to_server(@server_address)
      channel = MessageChannel.new(socket)

      handshake_version(channel)
      handshake_authentication(channel)
      handshake_initialization(channel)

      @connection.unref
      @connection = Connection.new(socket)
    rescue Exception => e
      socket.close if socket && !socket.closed?
      raise e
    end

    def handshake_version(channel)
      result = channel.read
      if result.nil?
        raise EOFError
      elsif result.size != 2 || result[0] != 'version'
        raise IOError, "The UstRouter didn't sent a valid version identifier"
      elsif result[1] != '1'
        raise IOError, "Unsupported UstRouter protocol version #{result[1]}"
      end
    end

    def handshake_authentication(channel)
      channel.write_scalar(@username)
      channel.write_scalar(@password)
      process_ust_router_reply(channel,
        'UstRouter client authentication error',
        SecurityError)
    end

    def handshake_initialization(channel)
      channel.write('init', @node_name)
      process_ust_router_reply(channel,
        'UstRouter client initialization error')
    end

    def random_token(length)
      token = ''
      @random_dev.read(length).each_byte do |c|
        token << RANDOM_CHARS[c % RANDOM_CHARS.size]
      end
      token
    end

    def create_txn_id
      result = (Time.now.to_i / 60).to_s(36)
      result << "-#{random_token(11)}"
      result
    end
  end
end
