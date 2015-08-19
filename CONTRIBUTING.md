# Contributors Guide

## Setting up your development environment

Before you can start developing `union_station_hooks_core`, you must setup a development environment. Passenger is required.

 1. Clone the Passenger source code:

        git clone git://github.com/phusion/passenger.git

 2. Compile the Passenger UstRouter:

        cd passenger
        rake nginx

 4. Go to the `union_station_hooks_core` directory, then install the gem bundle:

        cd /path-to/union_station_hooks_core
        bundle install

## Running unit tests

The unit tests are to be run against a specific Passenger version. Once you have set up your development environment, run the unit tests with:

    export PASSENGER_DIR=/path-to-passenger-source
    rake spec

This mechanism allows you to test this gem against multiple Passenger versions.

## Debugging

If you set the `DEBUG=1` environment variable, the unit test suite will enable debug logs.

    export DEBUG=1
    rake spec
