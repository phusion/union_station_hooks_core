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

UnionStationHooks.require_lib 'log'

module UnionStationHooks
  class IOLogging
    class << self
      def log_class_method(klass, method_name, args)
        old_level = increase_log_level
        begin
          if old_level == 0
            Log.debug("Logging IO class operation: #{klass}.#{method_name}" \
              "(#{inspect_args(args)})")

            reporter = Thread.current[:union_station_hooks]
            if reporter
              activity_name = activity_name_from_class_method_invocation(
                klass, method_name, args)
              activity_id = reporter.log_io_begin(activity_name)
            end
          end

          yield
        ensure
          begin
            if reporter && activity_id
              reporter.log_io_end(activity_id)
            end
          ensure
            set_log_level(old_level)
          end
        end
      end

      def log_instance_method(instance, method_name, args)
        old_level = increase_log_level
        begin
          if old_level == 0
            Log.debug("Logging IO instance operation: #{method_name}" \
              "(#{inspect_args(args)})")

            reporter = Thread.current[:union_station_hooks]
            if reporter
              activity_name = activity_name_from_instance_method_invocation(
                instance, method_name, args)
              activity_id = reporter.log_io_begin(activity_name)
            end
          end
          yield
        ensure
          begin
            if reporter && activity_id
              reporter.log_io_end(activity_id)
            end
          ensure
            set_log_level(old_level)
          end
        end
      end

      def initialize_for_current_thread
        Thread.current[:ush_io_log_level] = 0
      end

      def shutdown_for_current_thread
        Thread.current[:ush_io_log_level] = nil
      end

      def disable
        old_level = Thread.current[:ush_io_log_level]
        Thread.current[:ush_io_log_level] = nil
        begin
          yield
        ensure
          set_log_level(old_level)
        end
      end

    private

      def increase_log_level
        old_level = Thread.current[:ush_io_log_level]
        if old_level
          Thread.current[:ush_io_log_level] += 1
        end
        old_level
      end

      def set_log_level(level)
        Thread.current[:ush_io_log_level] = level
      end

      def inspect_args(args)
        if args.size <= 3 && args.all? { |a| arg_directly_inspectable?(a) }
          args.inspect
        else
          inspect_args_truncated(args)
        end
      end

      def arg_directly_inspectable?(arg)
        case arg
        when String
          arg.size <= 20
        when Numeric, TrueClass, FalseClass, NilClass, Symbol, Regexp
          true
        else
          false
        end
      end

      def inspect_args_truncated(args)
        result = []
        args[0..2].each do |arg|
          if arg_directly_inspectable?(arg)
            result << arg.inspect
          else
            result << inspect_arg_truncated(arg)
          end
        end
        "[#{result.join(', ')}]"
      end

      def inspect_arg_truncated(arg)
        case arg
        when String
          "#{arg[0..16].inspect}..."
        else
          "#<#{arg.class}:#{arg.object_id.to_s(16)}>"
        end
      end

      def activity_name_from_class_method_invocation(klass, method_name, args)
        if klass == IO && method_name == :select
          ios = args[0..2].flatten
          ios.compact!
          ios.map! { |io| io.class.to_s }
          "Waiting for IO: #{ios.join(',')}"
        else
          "#{klass}.#{method_name}"
        end
      end

      def activity_name_from_instance_method_invocation(instance, method_name,
            args)
        "#{instance.class}##{method_name}"
      end
    end
  end
end
