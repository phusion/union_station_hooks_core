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
  # A RequestReporter object is used for logging request-specific information
  # to Union Station. "Information" may include (and are not limited to):
  #
  #  * Web framework controller and action name.
  #  * Exceptions raised during the request.
  #  * Cache hits and misses.
  #  * Database actions.
  #
  # A unique RequestReporter is created by Passenger at the beginning of every
  # request (by calling {UnionStationHooks.begin_rack_request}). This object is
  # closed at the end of the same request (after the Rack body object is
  # closed).
  #
  # As an application developer, the RequestReporter is the main class
  # that you will be interfacing with. See the {UnionStationHooks} module
  # description for an example of how you can use RequestReporter.
  #
  # ## Obtaining a RequestReporter
  #
  # You are not supposed to create a RequestReporter object directly.
  # You are supposed to obtain the RequestReporter object that Passenger creates
  # for you. This is done through the `union_station_hooks` key in the Rack
  # environment hash, as well as through the `:union_station_hooks` key in
  # the current thread's object:
  #
  #     env['union_station_hooks']
  #     # => RequestReporter object or nil
  #
  #     Thread.current[:union_station_hooks]
  #     # => RequestReporter object or nil
  #
  # Note that Passenger may not have created such an object because of an
  # error. At present, there are two error conditions that would cause a
  # RequestReporter object not to be created. However, your code should take
  # into account that in the future more error conditions may trigger this.
  #
  #  1. There is no transaction ID associated with the current request.
  #     When Union Station support is enabled in Passenger, Passenger always
  #     assigns a transaction ID. However, administrators can also
  #     {https://www.phusionpassenger.com/library/admin/nginx/request_individual_processes.html
  #     access Ruby processes directly} through process-private HTTP sockets,
  #     bypassing Passenger's load balancing mechanism. In that case, no
  #     transaction ID will be assigned.
  #  2. An error occurred recently while sending data to the UstRouter, either
  #     because the UstRouter crashed or because of some other kind of
  #     communication error occurred. This error condition isn't cleared until
  #     certain a timeout has passed.
  #
  #     The UstRouter is a Passenger process which runs locally and is
  #     responsible for aggregating Union Station log data from multiple
  #     processes, with the goal of sending the aggergate data over the network
  #     to the Union Station service.
  #
  #     This kind of error is automatically recovered from after a certain
  #     period of time.
  #
  # ## Null mode
  #
  # The error condition 2 described above may also cause an existing
  # RequestReporter object to enter the "null mode". When this mode is entered,
  # any further actions on the RequestReporter object will become no-ops.
  # You can check whether the null mode is active by calling {#null?}.
  #
  # Closing a RequestReporter also causes it to enter the null mode.
  class RequestReporter
    # A mutex for synchronizing GC stats reporting. We do this because in
    # multithreaded situations we don't want to interleave GC stats access with
    # calls to `GC.clear_stats`. Not that GC stats are very helpful in
    # multithreaded situations, but this is better than nothing.
    #
    # @private
    MUTEX = Mutex.new

    # @private
    OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS      = ObjectSpace.respond_to?(:live_objects)

    # @private
    OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS = ObjectSpace.respond_to?(:allocated_objects)

    # @private
    OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS     = ObjectSpace.respond_to?(:count_objects)

    # @private
    GC_SUPPORTS_TIME        = GC.respond_to?(:time)

    # @private
    GC_SUPPORTS_CLEAR_STATS = GC.respond_to?(:clear_stats)


    ###### Basic methods ######

    # Returns a new RequestReporter object. You should not call
    # `RequestReporter.new` directly. See "Obtaining a RequestReporter"
    # in the {RequestReporter class description}.
    def initialize(context, txn_id)
      raise ArgumentError, 'Transaction ID must be given' if txn_id.nil?
      @context = context
      @txn_id = txn_id
      @transaction = continue_transaction
    end

    # Indicates that no further information will be logged for this
    # request.
    def close
      if @txn_id
        @transaction.close
      end
    end

    # Returns whether is this RequestReporter object is in null mode.
    # See the {RequestReporter class description} for more information.
    def null?
      @txn_id.nil? || @transaction.null?
    end


    ###### Logging basic request information ######

    # @private
    def log_request_begin
      return if @txn_id.nil?
      @transaction.begin_measure('app request handler processing')
    end

    # @private
    def log_request_end(uncaught_exception_raised_during_request = false)
      return if @txn_id.nil?
      @transaction.end_measure('app request handler processing',
        uncaught_exception_raised_during_request)
    end

    # @private
    def log_gc_stats_on_request_begin
      return if @txn_id.nil?

      # See the docs for MUTEX on why we synchronize this.
      MUTEX.synchronize do
        if OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS
          @transaction.message("Initial objects on heap: " \
            "#{ObjectSpace.live_objects}")
        end
        if OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS
          @transaction.message("Initial objects allocated so far: " \
            "#{ObjectSpace.allocated_objects}")
        elsif OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS
          count = ObjectSpace.count_objects
          @transaction.message("Initial objects allocated so far: " \
            "#{count[:TOTAL] - count[:FREE]}")
        end
        if GC_SUPPORTS_TIME
          @transaction.message("Initial GC time: #{GC.time}")
        end
      end
    end

    # @private
    def log_gc_stats_on_request_end
      return if @txn_id.nil?

      # See the docs for MUTEX on why we synchronize this.
      MUTEX.synchronize do
        if OBJECT_SPACE_SUPPORTS_LIVE_OBJECTS
          @transaction.message("Final objects on heap: " \
            "#{ObjectSpace.live_objects}")
        end
        if OBJECT_SPACE_SUPPORTS_ALLOCATED_OBJECTS
          @transaction.message("Final objects allocated so far: " \
            "#{ObjectSpace.allocated_objects}")
        elsif OBJECT_SPACE_SUPPORTS_COUNT_OBJECTS
          count = ObjectSpace.count_objects
          @transaction.message("Final objects allocated so far: " \
            "#{count[:TOTAL] - count[:FREE]}")
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


    ###### Logging controller-related information ######

    # Logs the beginning of a web framework controller action (using
    # {#log_controller_action_begin}), then yields the given block (which is
    # supposed to perform the main request handling), then logs the end of the
    # web framework controller action (using {#log_controller_action_end}).
    #
    # This is a convenience method for calling {#log_controller_action_begin}
    # and {#log_controller_action_end}. For more information, see the
    # documentation on those methods.
    #
    # The `union_station_hooks_rails` gem automatically calls this for you
    # if your application is a Rails app.
    #
    # @yield The given block is supposed to perform main request handling.
    # @param [Hash] options See {#log_controller_action_begin} for available
    #   options.
    # @return The return value of the block.
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

    # Logs the beginning of a web framework controller action. Of course,
    # you should only call this if your web framework has the concept of
    # controller actions. For example Rails does, but Sinatra and Grape
    # don't.
    #
    # If you call this method, then you *must* also call
    # {#log_controller_action_end} before the RequestReporter object is
    # closed. {#log_controller_action} is a convenience method that takes
    # a block for ensuring that this happens.
    #
    # The `union_station_hooks_rails` gem automatically calls this for you
    # if your application is a Rails app.
    #
    # @param [Hash] options Information about the controller action.
    # @option options [String] :controller_name (optional)
    #   The controller's name, e.g. `PostsController`.
    # @option options [String] :action_name (optional)
    #   The controller action's name, e.g. `create`.
    # @option options [String] :method (optional)
    #   The HTTP method that the web framework thinks this request should have,
    #   e.g. `GET` and `PUT`. The main use case for this option is to support
    #   Rails's HTTP verb emulation. Rails uses a parameter named
    #   [`_method`](http://guides.rubyonrails.org/form_helpers.html#how-do-forms-with-patch-put-or-delete-methods-work-questionmark)
    #   to emulate HTTP verbs besides GET and POST. Other web frameworks may
    #   have a similar mechanism.
    # @example Rails example
    #   # This example shows what to put inside a Rails controller action
    #   # method. Note that all of this is automatically done for you if you
    #   # use the union_station_hooks_rails gem.
    #   options = {
    #     :controller_name => self.class.name,
    #     :action_name => action_name,
    #     :method => request.request_method
    #   }
    #   reporter.log_controller_action(options) do
    #     do_some_request_processing_here
    #   end
    def log_controller_action_begin(options)
      return if @txn_id.nil?
      if options[:controller_name]
        if !options[:action_name]
          raise ArgumentError, 'The :action_name option must be set'
        end
        @transaction.message("Controller action: " \
          "#{options[:controller_name]}##{options[:action_name]}")
      end
      if options[:method]
        @transaction.message("Application request method: #{options[:method]}")
      end
      @transaction.begin_measure('framework request processing')
    end

    # Logs the end of a web framework controller action. You must call this
    # method if and only if you called {#log_controller_action_begin} before
    # in the same request.
    #
    # The `union_station_hooks_rails` gem automatically calls this for you
    # if your application is a Rails app.
    def log_controller_action_end(uncaught_exception_raised_during_action = false)
      return if @txn_id.nil?
      @transaction.end_measure('framework request processing',
        uncaught_exception_raised_during_action)
    end


    ###### Logging view rendering-related information ######

    # Logs the total time it has taken to render all the views (also known as
    # templates in some web frameworks) for this request, including time taken
    # for all partials.
    #
    # The `union_station_hooks_rails` gem automatically calls this for you
    # if your application is a Rails app.
    #
    # @param [Integer] runtime The view rendering time in milliseconds.
    def log_total_view_rendering_time(runtime)
      return if @txn_id.nil?
      @transaction.message("View rendering time: #{runtime.to_i}")
    end

    # Logs the rendering of a single view, template or partial.
    #
    # The `union_station_hooks_rails` gem automatically calls this for you
    # if your application is a Rails app. It will call this on every view
    # or partial rendering.
    #
    # @yield The given block is supposed to perform the actual view rendering.
    # @return The return value of the block.
    def log_view_rendering_event(&block)
      if @txn_id.nil?
        yield
      else
        measure_and_log_event("view rendering", &block)
      end
    end


    ###### Logging miscellaneous other information ######

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
      transaction = @context.new_transaction(
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

    # Log a database query.
    def log_database_query(name, begin_time, end_time, sql)
      return if @txn_id.nil?
      digest = Digest::MD5.hexdigest("#{name}\0#{sql}\0#{rand}")
      @transaction.measured_time_points("DB BENCHMARK: #{digest}",
        begin_time,
        end_time,
        "#{name}\n#{sql}")
    end

    # Logs the fact that you successfully retrieved something from a cache.
    # This can be any cache, be it an in-memory Hash, Redis, Memcached, a
    # flat file or whatever.
    #
    # There is just one exception. You should not use this method to log cache
    # hits in the ActiveRecord SQL cache or similar mechanisms.
    # Database-related timing should be logged with {#log_database_query}.
    #
    # If your app is a Rails app, then the `union_station_hooks_rails` gem
    # automatically calls this for you every time an `ActiveSupport::Cache`
    # `#fetch` or `#read` call success. This includes calls to
    # `Rails.cache.fetch` or `Rails.cache.read`, because `Rails.cache` is
    # an instance of `ActiveSupport::Cache`.
    def log_cache_hit(name)
      return if @txn_id.nil?
      @transaction.message("Cache hit: #{name}")
    end

    # Logs the fact that you failed to retrieve something from a cache.
    # This can be any cache, be it an in-memory Hash, Redis, Memcached, a
    # flat file or whatever.
    #
    # There is just one exception. You should not use this method to log cache
    # misses in the ActiveRecord SQL cache or similar mechanisms.
    # Database-related timing should be logged with {#log_database_query}.
    #
    # If your app is a Rails app, then the `union_station_hooks_rails` gem
    # automatically calls this for you every time an `ActiveSupport::Cache`
    # `#fetch` or `#read` call success. This includes calls to
    # `Rails.cache.fetch` or `Rails.cache.read`, because `Rails.cache` is
    # an instance of `ActiveSupport::Cache`.
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
      @context.continue_transaction(@txn_id,
        UnionStationHooks.app_group_name, :requests, UnionStationHooks.key)
    end
  end
end
