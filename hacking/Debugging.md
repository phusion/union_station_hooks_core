# Debugging guide

**Table of contents**

 * [Enabling debug logs](#enabling-debug-logs)
 * [Running a specific test](#running-a-specific-test)
 * [Investigating logged data](#investigating-logged-data)
   - [Checking whether data is correctly sent to the UstRouter](#checking-whether-data-is-correctly-sent-to-the-ustrouter)
   - [Checking whether the UstRouter correctly accepts the data](#checking-whether-the-ustrouter-correctly-accepts-the-data)
   - [Checking whether the UstRouter correctly sends the data to the Union Station service](#checking-whether-the-ustrouter-correctly-sends-the-data-to-the-union-station-service)
   - [Inspecting dump files](#inspecting-dump-files)

## Enabling debug logs

If you set the `DEBUG=1` environment variable, the test suite will enable debug logs. This will have two effects:

 1. Calls to `UnionStationHooks::Log.debug()`, which is normally silent, will now print to standard error.
 2. The UstRouter process will have its log level set to 6. This will cause it to print many debugging messages to standard error.

Here is an example:

    export DEBUG=1
    bundle exec rake spec

The debug logs can be a bit overwhelming, so if you enabled debug logs then it's a good idea to run a specific test instead of the whole test suite.

## Investigating logged data

As explained in `Architecture.md`, the `union_station_hooks_*` gems make use of a UstRouter process. The gems do not send data to the Union Station service directly, but sends data to the UstRouter process, which in turn is responsible for sending the data to the Union Station service.

Thus, when investigating logged data, there are three aspects that you should investigate:

 1. Whether data is correctly sent to the UstRouter.
 2. Whether the UstRouter correctly accepts the data.
 3. Whether the UstRouter correctly sends the data to the Union Station service.

### Checking whether data is correctly sent to the UstRouter

If you enabled [debug logs](#enabling-debug-logs), and the gem cannot contact the UstRouter, then it will enter null mode and print debug messages that begin with `[Union Station log to null]`.

To learn more about the null mode, see the documentation for the `RequestReporter` class.

If the gem *can* contact the UstRouter, then no data is logged.

### Checking whether the UstRouter correctly accepts the data

The UstRouter performs a few simple sanity checks on any received data, so it may not accept that data. If one of the sanity checks don't pass, then the UstRouter will drop the data and log the error. When running the test suite, you should see such error messages even if you did not enable debug logging.

Note that **such errors do not necessarily cause exceptions in the gems**, so even if the test suite exits with exit code 0, you should check the terminal for whether or not the UstRouter logged any errors.

### Checking whether the UstRouter correctly sends the data to the Union Station service

You can check whether the UstRouter correctly sends data to the Union Station service by running Passenger normally and using the `passenger-status --show=union_station` command.

> **Note**: The test suite runs the UstRouter in development mode, so the test suite never sends any data to the Union Station service. If you want to check, during development of the test suite, what data the UstRouter will send to the Union Station service if it weren't running in development mode, then you should [inspect dump files](#inspecting-dump-files).

Start your app in Passenger:

    passenger start --union-station-key YOUR_KEY_HERE

By default, Passenger sends data to the production Union Station gateway at `gateway.unionstationapp.com`. If you want to send data to a different Union Station gateway (e.g. development or staging), then pass `--union-station-gateway`:

    passenger start --union-station-key YOUR_KEY_HERE --union-station-gateway localhost:1234

Passenger's UstRouter sends data to the Union Station service in batches. This works as follows. All received data is appended to a 240 KB buffer. Whenever the buffer is full or overflown, the entire buffer plus any overflow data is scheduled to be sent to the Union Station service in a single compressed batch -- a "packet". In addition, every 5 seconds the entire buffer is scheduled to be sent to the Union Station service, regardless of whether or not it is full.

The UstRouter also has this concept of "transactions". A transaction is a logical group of data that should function as a single atomic unit. For example, all Union Station data that we log for a single request is part of a single transaction. The transaction's data isn't appended to the buffer until the transaction has finished. Thus, the Union Station service always receives batches of atoms. The Union Station service never receives partial data about a request.

You can query the UstRouter's status with:

    passenger-status --show=union_station

This will print a JSON document representing the status. The following keys are especially interesting.

 * `remote_sender.available_servers`: An array of Union Station gateway host names that the UstRouter will send to. The UstRouter determines this by:
   
    1. Resolving the host name of the gateway,
    2. Pinging the server at each resolved IP address (through a `GET /ping` request),
    3. Adding to the array the IP address of each server that responds successfully to the ping.

   This array might be briefly empty during startup, but should eventually become non-empty. If it stays empty for a while, then it either means that there is a DNS resolution error, or that none of the servers at the resolved IP addresses responded to pings.
 * `remote_sender.packets_sent_to_gateway`: The number of packets successfully sent to the Union Station service so far. This should become non-zero after a while.
 * `remote_sender.packets_dropped`: The number of packets dropped. A packet can be dropped if no servers are available, when I/O errors are encountered or when the UstRouter cannot send packets to the Union Station gateway quickly enough. If this value is non-zero, then there is trouble.
 * `remote_sender.queue_size`: Sending a packet to the Union Station service does not succeed instantly; it takes some time. The UstRouter does not stop accepting data while it is busy sending a packet. Instead, it schedules the packet to be sent, by adding the packet to a queue. After this act, the UstRouter continues to accept data. A background thread sends out packets in the queue as quickly as possible.

   The queue's maximum size is 1024 packets. If packets are appended to this queue faster than the background thread can send out packets, then this queue eventually becomes full. Any packets that cannot be appended to the queue are dropped. If you see a large queue size that is near 1024, then that is a bad sign.
 * `transactions`: A map of transactions that haven't finished yet. The data associated with these transactions aren't scheduled for sending until the transaction has finished.

Any errors that the UstRouter encounters will be logged. You should read that file in order to analyze any issues you encounter. You can find the location of the UstRouter log file with:

    passenger-config api-call -a ust_router_api GET /config.json | grep log_file

### Inspecting dump files

You can also inspect the dump files that the UstRouter writes to. By convention, the tests configure the UstRouter to dump to files in `@tmpdir`.

The easiest way to inspect files in `@tmpdir` is by calling `debug_shell` inside tests. By convention, the tests configure the debug shell to be opened inside `@tmpdir`.

The UstRouter dumps each category to its own file. For example, data in belonging to the `requests` category are dumped to `#{@tmpdir}/requests`.

Example:

    describe Transaction do
      # ...

      describe '#message' do
        it 'logs the given message' do
          start_agent
          # ...

          debug_shell # <--- insert this

          eventually do
            File.exist?(dump_file_path) &&
              read_dump_file.include?('hello')
          end
        end
      end
    end

When running the above test, you will see the debug shell:

    $ rake spec E="UnionStationHooks::Transaction#message logs the given message"
    ...

    UnionStationHooks::Transaction
      #message
    ------ Opening debug shell -----
    You are at /var/folders/98/6tqkjq791_l02r4s2qkq1sfw0000gn/T/d20150830-68695-gntmiy.
    You can find UstRouter dump files in this directory.
    bash d20150830-68695-gntmiy$

You can for example read one of the dump files:

    bash d20150830-68695-gntmiy$ cat requests
    eaqh9-Gx0LI0BvDKL e6rm4szrty 0 ATTACH
    eaqh9-Gx0LI0BvDKL e6rm4szuhe 1 hello
    eaqh9-Gx0LI0BvDKL e6rm4szuji 2 DETACH

Exit the debug shell by typing `exit`:

    bash d20150830-68695-gntmiy$ exit
    exit
    ------ Exiting debug shell -----
        logs the given message

    Finished in 2 minutes 5.8 seconds (files took 0.42966 seconds to load)
    1 example, 0 failures
