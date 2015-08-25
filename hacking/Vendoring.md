# Vendoring mechanism

`union_station_hooks_core` and [union_station_hooks_rails](https://github.com/phusion/union_station_hooks_rails) are available as standalone gems, but they are also vendored into (bundled with) [Passenger](https://www.phusionpassenger.com/). The reason why we allow this is because the Union Station Ruby hooks used to be part of Passenger. At some point, we decided to split the code to separate projects to ease contributions and to improve maintenance. When the Union Station Ruby hooks were part of Passenger, the application developer does not need to install any new gems to make use of Union Station. By vendoring `union_station_hooks_core` and `union_station_hooks_rails`, we maintain that tradition.

## Passenger

The vendored version of the `union_station_hooks_*` gems are located in the Passenger source tree under the directory `src/ruby_supportlib/phusion_passenger/vendor`. They exist in the form of Git submodules. The Passenger maintainers should regularly update these submodules to the latest version.

## Version override

As documented in the README, it is possible to override the version bundled with Passenger. This mechanism works as follows.

Before loading a Ruby application, Passenger loads its bundled versions of the `union_station_hooks_*` gems (of course, only when the user has enabled Union Station support). This is done by loading the gems' Ruby files' absolute paths. Passenger also sets the `vendor` property of the gems' modules to true.

When the application developer adds `union_station_hooks_*` to their Gemfile and calls `require 'union_station_hooks_*'`, the versions in the Gemfile are loaded. Upon loading, the code checks whether the module is already defined and whether the `vendor` property has been set to true. If so, then it unloads the previously loaded module (by removing the constant) before redefining the module.

See `lib/union_station_hooks_core.rb` for an example of this mechanism in action.

## No dependencies

Because Passenger itself [must be able to work without Bundler](https://www.phusionpassenger.com/library/indepth/ruby/bundler.html), Passenger may not have any gem dependencies. The `union_station_hooks_*` gems are bundled with Passenger, and therefore they may not have any dependencies either. Please do not introduce any dependencies when contributing.
