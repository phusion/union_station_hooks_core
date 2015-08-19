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

module UnionStationHooks
  module SpecHelper
    extend self    # Make methods available as class methods.

    def self.included(klass)
      # When included into another class, make sure that Utils
      # methods are made private.
      public_instance_methods(false).each do |method_name|
        klass.send(:private, method_name)
      end
    end

    def spawn_process(*args)
      args.map! do |arg|
        arg.to_s
      end
      if Process.respond_to?(:spawn)
        Process.spawn(*args)
      else
        fork do
          exec(*args)
        end
      end
    end

    def spawn_ust_router(tmpdir, socket_filename, password, debug)
      password_filename = "#{tmpdir}/password"
      File.open(password_filename, "w") do |f|
        f.write(password)
      end
      pid = spawn_process("#{PhusionPassenger.support_binaries_dir}/#{PhusionPassenger::AGENT_EXE}",
        "ust-router",
        "--passenger-root", PhusionPassenger.install_spec,
        "--log-level", debug ? "6" : "2",
        "--dev-mode",
        "--dump-dir", tmpdir,
        "--listen", "unix:#{socket_filename}",
        "--password-file", password_filename)
      eventually do
        File.exist?(socket_filename)
      end
      pid
    rescue Exception => e
      if pid
        Process.kill('KILL', pid)
        Process.waitpid(pid)
      end
      raise e
    end

    def flush_ust_router(password, socket_address)
      client = MessageClient.new("logging", password, socket_address)
      begin
        client.write("flush")
        client.read
      ensure
        client.close
      end
    end

    def eventually(deadline_duration = 2, check_interval = 0.05)
      deadline = Time.now + deadline_duration
      while Time.now < deadline
        if yield
          return
        else
          sleep(check_interval)
        end
      end
      raise "Time limit exceeded"
    end

    def should_never_happen(deadline_duration = 1, check_interval = 0.05)
      deadline = Time.now + deadline_duration
      while Time.now < deadline
        if yield
          raise "That which shouldn't happen happened anyway"
        else
          sleep(check_interval)
        end
      end
    end
  end
end
