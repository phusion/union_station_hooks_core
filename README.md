# Union Station Ruby hooks core code

This gem allows you to hook your application into Union Station. By calling this gem in key places in your codebase, information will be sent to Union Station for analysis.

## Installation

## API




    UnionStationHooks::Logger.new(nil, nil, nil, nil)

    USH.measure_and_log_event(rack_env, name)
    USH.benchmark(rack_env, title, name)
    USH.log_exception(rack_env, exception)

## Contributing

Looking to contribute to this gem? Please read CONTRIBUTING.md.
