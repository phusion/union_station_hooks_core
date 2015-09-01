# Developer quickstart

**Table of contents**

 * [Setting up the development environment](#setting-up-the-development-environment)
 * [Development workflow](#development-workflow)
 * [Testing](#testing)
   - [Running the test suite against a specific Passenger version](#running-the-test-suite-against-a-specific-passenger-version)
   - [Code coverage](#code-coverage)
   - [Writing tests](#writing-tests)

## Setting up the development environment

Before you can start developing `union_station_hooks_core`, you must setup a development environment.

### Step 1: install gem bundle

Go to the `union_station_hooks_core` directory, then install the gem bundle:

    cd /path-to/union_station_hooks_core
    bundle install

### Step 2: install Passenger

During development, the `union_station_hooks_core` unit tests are to be run against a specific Passenger version. If you already have Passenger installed, then you don't have to do anything. But if you do not yet have Passenger, then here is how you can install it:

 1. Clone the Passenger source code:

        git clone git://github.com/phusion/passenger.git

 2. Compile the Passenger UstRouter:

        cd passenger
        rake nginx

 3. Add this Passenger installation's `bin` directory to your `$PATH`:

        export PATH=/path-to-passenger/bin:$PATH

    You also need to add this to your bashrc so that the environment variable persists in new shell sessions.

## Development workflow

The development workflow is as follows:

 1. Write code (`lib` directory).
 2. Write tests (`spec` directory).
 3. Run tests. Repeat from step 1 if necessary.
 4. Commit code, send a pull request.

## Testing

Once you have set up your development environment per the above instructions, run the test suite with:

    bundle exec rake spec

The unit test suite will automatically detect your Passenger installation by scanning `$PATH` for the `passenger-config` command.

### Running the test suite against a specific Passenger version

If you have multiple Passenger versions installed, and you want to run the test suite against a specific Passenger version (e.g. to test compatibility with that version), then you can do that by setting the `PASSENGER_CONFIG` environment variable to that Passenger installation's `passenger-config` command. For example:

    export PASSENGER_CONFIG=$HOME/passenger-5.0.18/bin/passenger-config
    bundle exec rake spec

### Running a specific test

If you want to run a specific test, then pass the test's name through the `E` environment variable. For example:

    bundle exec rake spec E='UnionStationHooks::Transaction#message logs the given message'

### Code coverage

You can run the test suite with code coverage reporting by setting the `COVERAGE=1` environment variable:

    export COVERAGE=1
    bundle exec rake spec

Afterwards, the coverage report will be available in `coverage/index.html`.

### Writing tests

Tests are written in [RSpec](http://rspec.info/). Most tests follow this pattern:

 1. Start the UstRouter in development mode. The development mode will cause the UstRouter to dump any received data to files on the filesystem, instead of sending them to the Union Station service.
 2. Perform some work, which we expect will send a bunch of data to the UstRouter.
 3. Assert that the UstRouter dump files will **eventually** contain the data that we expect. The "eventually" part is important, because the UstRouter is highly asynchronous and may not write to disk immediately.

The test suite contains a bunch of helper methods that aid you in writing tests that follow these pattern. See `spec/spec_helper.rb` and `lib/union_station_hooks_core/spec_helper.rb`.
