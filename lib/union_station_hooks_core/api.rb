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

UnionStationHooks.require_lib 'request_specific_reporter'

module UnionStationHooks
  class << self
    def begin_rack_request(rack_env)
      reporter = RequestSpecificReporter.new(rack_env['PASSENGER_TXN_ID'])
      if reporter
        rack_env['union_station_hooks'] = reporter
        Thread.current[:union_station_hooks] = reporter
        reporter.log_request_begin
        reporter.log_gc_stats_on_request_begin
      end
      reporter
    end

    def end_rack_request(rack_env, uncaught_exception_raised_during_request = false)
      reporter = rack_env.delete('union_station_hooks')
      Thread.current[:union_station_hooks] = nil
      begin
        reporter.log_gc_stats_on_request_end
        reporter.log_request_end(uncaught_exception_raised_during_request)
      ensure
        reporter.close
      end
    end
  end
end
