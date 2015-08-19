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
require 'digest/md5'

module UnionStationHooks
  class RequestSpecificReporter
    MUTEX = Mutex.new
    OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS      = ObjectSpace.respond_to?(:live_objects)
    OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS = ObjectSpace.respond_to?(:allocated_objects)
    OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS     = ObjectSpace.respond_to?(:count_objects)
    GC_SUPPORTS_TIME        = GC.respond_to?(:time)
    GC_SUPPORTS_CLEAR_STATS = GC.respond_to?(:clear_stats)

    def initialize(txn_id)
      return if !txn_id
      @txn_id = txn_id
      @transaction = continue_transaction
    end

    def close
      if @txn_id
        @transaction.close
      end
    end

    def null?
      @txn_id.nil? || @transaction.null?
    end

    def measure_and_log_event(name)
      if @txn_id.nil?
        yield
      else
        @transaction.measure(name) do
          yield
        end
      end
    end

    def benchmark(title = "Benchmarking", &block)
      if @txn_id.nil?
        yield
      else
        measure_and_log_event("BENCHMARK: #{title}", &block)
      end
    end

    def log_exception(exception, options = nil)
      transaction = UnionStationHooks.context.new_transaction(
        UnionStationHooks.app_group_name,
        :exceptions,
        UnionStationHooks.key)
      begin
        message = exception.message
        message = exception.to_s if message.empty?
        message = [message].pack('m')
        message.gsub!("\n", "")
        backtrace_string = [exception.backtrace.join("\n")].pack('m')
        backtrace_string.gsub!("\n", "")

        if @txn_id
          transaction.message("Request transaction ID: #{@txn_id}")
        end
        transaction.message("Message: #{message}")
        transaction.message("Class: #{exception.class.name}")
        transaction.message("Backtrace: #{backtrace_string}")

        if options && options[:controller_name]
          if options[:action_name]
            controller_action = "#{options[:controller_name]}##{options[:action_name]}"
          else
            controller_action = controller_name
          end
          transaction.message("Controller action: #{controller_action}")
        end
      ensure
        transaction.close
      end
    end

    def log_controller_action(options)
      if @txn_id.nil?
        yield
      else
        log_controller_action_begin(options)
        has_error = false
        begin
          yield
        rescue Exception
          has_error = true
          raise
        ensure
          log_controller_action_end(has_error)
        end
      end
    end

    # Log the beginning of a controller action.
    # Options:
    #   :controller_name
    #   :action_name
    #   :method - Interpreted HTTP method name (may be different from actual HTTP method)
    def log_controller_action_begin(options)
      return if @txn_id.nil?
      if options[:controller_name]
        if !options[:action_name]
          raise ArgumentError, "The :action_name option must be set"
        end
        @transaction.message("Controller action: #{options[:controller_name]}##{options[:action_name]}")
      end
      if options[:method]
        @transaction.message("Application request method: #{options[:method]}")
      end
      @transaction.begin_measure("framework request processing")
    end

    def log_controller_action_end(uncaught_exception_raised_during_action = false)
      return if @txn_id.nil?
      @transaction.end_measure("framework request processing",
        uncaught_exception_raised_during_action)
    end

    # Log the total view rendering time of a request.
    def log_total_view_rendering_time(runtime)
      return if @txn_id.nil?
      @transaction.message("View rendering time: #{runtime.to_i}")
    end

    # Log a single view rendering.
    def log_view_rendering_event(&block)
      if @txn_id.nil?
        yield
      else
        measure_and_log_event("view rendering", &block)
      end
    end

    # Log a database query.
    def log_database_query(name, begin_time, end_time, sql)
      return if @txn_id.nil?
      digest = Digest::MD5.hexdigest("#{name}\0#{sql}\0#{rand}")
      @transaction.measured_time_points("DB BENCHMARK: #{digest}",
        begin_time,
        end_time,
        "#{name}\n#{sql}")
    end

    def log_request_begin
      return if @txn_id.nil?
      @transaction.begin_measure("app request handler processing")
    end

    def log_request_end(uncaught_exception_raised_during_request = false)
      return if @txn_id.nil?
      @transaction.end_measure("app request handler processing",
        uncaught_exception_raised_during_request)
    end

    def log_gc_stats_on_request_begin
      return if @txn_id.nil?

      # We synchronize GC stats reporting because in multithreaded situations
      # we don't want to interleave GC stats access with calls to
      # GC.clear_stats. Not that GC stats are very helpful in multithreaded
      # situations, but this is better than nothing.
      MUTEX.synchronize do
        if OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS
          @transaction.message("Initial objects on heap: #{ObjectSpace.live_objects}")
        end
        if OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS
          @transaction.message("Initial objects allocated so far: #{ObjectSpace.allocated_objects}")
        elsif OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS
          count = ObjectSpace.count_objects
          @transaction.message("Initial objects allocated so far: #{count[:TOTAL] - count[:FREE]}")
        end
        if GC_SUPPORTS_TIME
          @transaction.message("Initial GC time: #{GC.time}")
        end
      end
    end

    def log_gc_stats_on_request_end
      return if @txn_id.nil?

      # See log_gc_stats_on_request_begin to learn why we use a mutex here.
      MUTEX.synchronize do
        if OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS
          @transaction.message("Final objects on heap: #{ObjectSpace.live_objects}")
        end
        if OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS
          @transaction.message("Final objects allocated so far: #{ObjectSpace.allocated_objects}")
        elsif OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS
          count = ObjectSpace.count_objects
          @transaction.message("Final objects allocated so far: #{count[:TOTAL] - count[:FREE]}")
        end
        if GC_SUPPORTS_TIME
          @transaction.message("Final GC time: #{GC.time}")
        end
        if GC_SUPPORTS_CLEAR_STATS
          # Clear statistics to void integer wraps.
          GC.clear_stats
        end
      end
    end

    def log_cache_hit(name)
      return if @txn_id.nil?
      @transaction.message("Cache hit: #{name}")
    end

    def log_cache_miss(name, generation_time = nil)
      return if @txn_id.nil?
      if generation_time
        @transaction.message("Cache miss (#{generation_time.to_i}): #{name}")
      else
        @transaction.message("Cache miss: #{name}")
      end
    end

  private

    def continue_transaction
      UnionStationHooks.context.continue_transaction(@txn_id,
        UnionStationHooks.app_group_name, :requests, UnionStationHooks.key)
    end
  end
end
