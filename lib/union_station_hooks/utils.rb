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

module UnionStationHooks
  module Utils
    extend self    # Make methods available as class methods.

    def self.included(klass)
      # When included into another class, make sure that Utils
      # methods are made private.
      public_instance_methods(false).each do |method_name|
        klass.send(:private, method_name)
      end
    end

    def get_socket_address_type(address)
      if address =~ %r{^unix:.}
        :unix
      elsif address =~ %r{^tcp://.}
        :tcp
      else
        :unknown
      end
    end

    def connect_to_server(address)
      case get_socket_address_type(address)
      when :unix
        UNIXSocket.new(address.sub(/^unix:/, ''))
      when :tcp
        host, port = address.sub(%r{^tcp://}, '').split(':', 2)
        port = port.to_i
        TCPSocket.new(host, port)
      else
        raise ArgumentError, "Unknown socket address type for '#{address}'."
      end
    end

    def local_socket_address?(address)
      case get_socket_address_type(address)
      when :unix
        return true
      when :tcp
        host, port = address.sub(%r{^tcp://}, '').split(':', 2)
        host == "127.0.0.1" || host == "::1" || host == "localhost"
      else
        raise ArgumentError, "Unknown socket address type for '#{address}'."
      end
    end

    if defined?(PhusionPassenger::NativeSupport)
      def process_times
        PhusionPassenger::NativeSupport.process_times
      end
    else
      class ProcessTimes < Struct.new(:utime, :stime)
      end

      def process_times
        times = Process.times
        ProcessTimes.new((times.utime * 1_000_000).to_i,
          (times.stime * 1_000_000).to_i)
      end
    end
  end
end
