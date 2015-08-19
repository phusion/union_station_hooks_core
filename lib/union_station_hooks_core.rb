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

if defined?(UnionStationHooks::VERSION_STRING) && UnionStationHooks.vendored?
  # Passenger loaded its vendored Union Station hooks code, but the application
  # has also included 'union_station_hooks_*' in its Gemfile. We want the
  # version in the Gemfile to take precedence, so we unload the old version. At
  # this point, the Union Station hooks aren't installed yet, so removing the
  # module is enough to unload the old version.
  config_from_vendored_ush = UnionStationHooks.config
  Object.send(:remove_const, :UnionStationHooks)
end

module UnionStationHooks
  LIBROOT = File.expand_path(File.dirname(__FILE__))
  ROOT = File.dirname(LIBROOT)

  class << self
    @@config = {}
    @@context = nil
    @@initializers = []
    @@initialized = false
    @@app_group_name = nil
    @@key = nil
    @@vendored = false

    def initialize!
      return if !should_initialize?

      finalize_and_validate_config
      create_context
      install_event_pre_hook
      @@initializers.each do |initializer|
        initializer.initialize!
      end
      require_lib('api')
      @@config.freeze
      @@app_group_name = @@config[:app_group_name]
      @@key = @@config[:union_station_key]
      @@initialized = true
    end

    def initialized?
      @@initialized
    end

    def should_initialize?
      if defined?(PhusionPassenger)
        PhusionPassenger::App.options["analytics"]
      else
        true
      end
    end

    def vendored?
      @@vendored
    end

    def vendored=(val)
      @@vendored = val
    end

    def require_lib(name)
      require("#{LIBROOT}/union_station_hooks_core/#{name}")
    end

    def call_event_pre_hook(_event)
      raise 'This method may only be called after ' \
        'UnionStationHooks.initialize! is called'
    end

    def config
      @@config
    end

    def context
      @@context
    end

    def initializers
      @@initializers
    end

    def app_group_name
      @@app_group_name
    end

    def key
      @@key
    end

    def check_initialized
      if should_initialize? && !initialized?
        if defined?(::Rails)
          raise 'The Union Station hooks are not initialized. Please ensure ' \
            'that you have an initializer file ' \
            '`config/initializers/union_station.rb` in which you call ' +
            '`UnionStationHooks.initialize!`'
        else
          raise 'The Union Station hooks are not initialized. Please ensure ' \
            'that `UnionStationHooks.initialize!` is called during ' \
            'application startup'
        end
      end
    end

  private

    def finalize_and_validate_config
      final_config = {}

      if defined?(PhusionPassenger)
        import_into_final_config(final_config, PhusionPassenger::App.options)
      end
      import_into_final_config(final_config, config)

      validate_final_config(final_config)

      @@config = final_config
    end

    def import_into_final_config(dest, source)
      source.each_pair do |key, val|
        dest[key.to_sym] = val
      end
    end

    def validate_final_config(config)
      require_non_empty_config_key(config, :union_station_key)
      require_non_empty_config_key(config, :app_group_name)
      require_non_empty_config_key(config, :ust_router_address)
      require_non_empty_config_key(config, :ust_router_password)
    end

    def require_non_empty_config_key(config, key)
      if config[key].nil? || config[key].empty?
        raise ArgumentError,
          "Union Station hooks configuration option required: #{key}"
      end
    end

    def create_context
      require_lib('context')
      @@context = Context.new(config[:ust_router_address],
        config[:ust_router_username] || 'logging',
        config[:ust_router_password],
        config[:node_name])
    end

    def install_event_pre_hook
      preprocessor = @@config[:event_preprocessor]
      if preprocessor
        define_singleton_method(:call_event_pre_hook, &preprocessor)
      else
        def call_event_pre_hook(_event)
          # Do nothing
        end
      end
    end
  end
end

UnionStationHooks.require_lib('version')

if config_from_vendored_ush
  UnionStationHooks.config.update(config_from_vendored_ush)
end
