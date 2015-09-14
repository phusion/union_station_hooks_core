#  Union Station - https://www.unionstationapp.com/
#  Copyright (c) 2015 Phusion Holding B.V.
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

require 'socket'
UnionStationHooks.require_lib 'utils'

IO.class_eval do
  ###### Hook IO class methods ######

  class << self
    class_methods_to_hook = [:binread, :binwrite, :copy_stream,
      :foreach, :read, :readlines, :select, :write]

    class_methods_to_hook.each do |method_name|
      if IO.respond_to?(method_name)
        file, line = [__FILE__, __LINE__]
        eval(%Q{
          def #{method_name}_with_union_station(*args, &block)
            UnionStationHooks::IOLogging.log_class_method(self,
                :#{method_name}, args) do
              #{method_name}_without_union_station(*args, &block)
            end
          end
        }, binding, file, line + 1)

        alias_method(:"#{method_name}_without_union_station", method_name)
        alias_method(method_name, :"#{method_name}_with_union_station")
      end
    end
  end


  ###### Hook IO instance methods ######

  instance_methods_to_hook= [:bytes, :chars, :codepoints, :each_byte,
    :each_char, :each_codepoint, :each_line, :each, :eof, :eof?, :fdatasync,
    :flush, :getbyte, :getc, :gets, :<<, :lines, :print, :putc, :puts, :read,
    :readbyte, :readchar, :readline, :readlines, :readpartial, :sync, :sysread,
    :syswrite, :write]

  instance_methods_to_hook.each do |method_name|
    if method_defined?(method_name)
      normalized_method_name =
        UnionStationHooks::Utils.normalize_method_name(method_name)

      file, line = [__FILE__, __LINE__]
      eval(%Q{
        def #{normalized_method_name}_with_union_station(*args, &block)
          UnionStationHooks::IOLogging.log_instance_method(self,
              :#{method_name}, args) do
            #{normalized_method_name}_without_union_station(*args, &block)
          end
        end
      }, binding, file, line + 1)

      alias_method(:"#{normalized_method_name}_without_union_station", method_name)
      alias_method(method_name, :"#{normalized_method_name}_with_union_station")
    end
  end
end

TCPSocket.class_eval do
  class << self
    class_methods_to_hook = [:new, :open]

    class_methods_to_hook.each do |method_name|
      if IO.respond_to?(method_name)
        file, line = [__FILE__, __LINE__]
        eval(%Q{
          def #{method_name}_with_union_station(*args, &block)
            UnionStationHooks::IOLogging.log_class_method(self,
                :#{method_name}, args) do
              #{method_name}_without_union_station(*args, &block)
            end
          end
        }, binding, file, line + 1)

        alias_method(:"#{method_name}_without_union_station", method_name)
        alias_method(method_name, :"#{method_name}_with_union_station")
      end
    end
  end
end
