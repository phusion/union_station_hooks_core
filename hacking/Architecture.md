# Architecture

## Communication architecture

From the client point of view, the Union Station architecture looks as follows.

<img src="https://raw.githubusercontent.com/phusion/union_station_hooks_core/master/hacking/ArchitectureCommunication.png">

 1. Central to the architecture is the UstRouter. It is a Passenger process which runs locally and is responsible for aggregating Union Station log data from multiple processes, with the goal of sending the aggregate data over the network to the Union Station service.

 2. When visitors send a request to your server, the request is first received by Passenger, after which it is processed by Passenger's Core process. The Passenger Core then logs relevant information about the request to the UstRouter and forwards the request to the application process.

 3. After the Passenger core has received a request, processing continues inside the application process. Inside the application process, the Union Station hooks code are running. The hooks code consist of the `union_station_*` family of gems. Through these gems, the application process also logs relevant information about the request to the UstRouter.

 4. The UstRouter combines all information about a particular request from all processes. This combined information is a single atomic entity called a "packet". The UstRouter batches multiple packets and sends them to one of the Union Station service through one of the gateway servers.

 5. The Union Station service is represented by a number of gateway servers. A gateway accepts packets and forwards them for further processing. How accepted packets are processed is outside the scope of this document, and so the processing can be considered a black box.

As explained in the [Debugging guide](https://github.com/phusion/union_station_hooks_core/blob/master/hacking/Debugging.md), the UstRouter can also be configured to dump packets into files, instead of sending them to a gateway.

## Gem architecture

The Union Station hooks code is separated into a number of gems, each with its own responsibility.

<img src="https://raw.githubusercontent.com/phusion/union_station_hooks_core/master/hacking/ArchitectureGems.png">

At the very bottom is `union_station_hooks_core`, which provides a foundation on top of which other `union_station_hooks_*` gems are built. `union_station_hooks_core` provides an API for logging data to the UstRouter. It also hooks into Ruby core and stdlib methods in order to automatically log information about those things.

The `union_station_hooks_rails` gem hooks into Rails, and uses the API exposed by `union_station_hooks_core` to log Rails-specific information to the UstRouter.

In the future, we may introduce more gems that hook into other frameworks or libraries. These gems will also be built in top of `union_station_hooks_core`.
