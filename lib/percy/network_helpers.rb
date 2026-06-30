require 'socket'
require 'excon'

module Percy
  class NetworkHelpers
    MIN_PORT = 1_024 # 0-1023 are not available without privilege
    MAX_PORT = 65_535 # (2^16) -1
    MAX_PORT_ATTEMPTS = 50

    class ServerDown < RuntimeError; end
    class OpenPortNotFound < RuntimeError; end
    class InvalidServeDirectory < ArgumentError; end

    # Returns a port number that was bound and immediately released by the OS.
    # Uses kernel-assigned ephemeral ports so the returned value is known-free
    # at the moment of the call. The min_port/max_port arguments are honoured
    # by retrying assignments that fall outside the requested range.
    #
    # Note: there is an inherent TOCTOU race between this method returning and
    # any caller binding the returned port. For race-free use, prefer
    # serve_static_directory with port: nil (which uses OS-assigned ports
    # directly in the child process) or bind via TCPServer.new(host, 0) and
    # keep the socket open.
    def self.random_open_port(min_port: MIN_PORT, max_port: MAX_PORT)
      MAX_PORT_ATTEMPTS.times do
        server = TCPServer.new('127.0.0.1', 0)
        port = server.addr[1]
        server.close
        return port if port.between?(min_port, max_port)
      end

      raise OpenPortNotFound
    end

    def self.port_open?(port)
      begin
        TCPServer.new(port).close
        true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EADDRINUSE
        false
      end
    end

    def self.verify_healthcheck(url:, expected_body: 'ok', retry_wait_seconds: 0.5, proxy: nil,
      headers: {})
      10.times do
        begin
          response = Excon.get(url, proxy: proxy, headers: headers)
          return true if response.body == expected_body
        rescue Excon::Error::Socket, Excon::Error::Timeout
          sleep retry_wait_seconds
        end
      end
      raise ServerDown, "Healthcheck failed for #{url}"
    end

    def self.verify_http_server_up(hostname, port: nil,
      path: nil, retry_wait_seconds: 0.25, proxy: nil, headers: {})
      10.times do
        begin
          url = "http://#{hostname}#{port.nil? ? '' : ':' + port.to_s}#{path || ''}"
          Excon.get(url, proxy: proxy, headers: headers)
          return true
        rescue Excon::Error::Socket, Excon::Error::Timeout
          sleep retry_wait_seconds
        end
      end
      raise ServerDown, "Server is down: #{hostname}"
    end

    # Starts a simple HTTP server that serves `dir`. The directory is resolved
    # to an absolute path with File.realpath; if `allowed_base` is given, the
    # resolved directory must live under it or InvalidServeDirectory is raised.
    #
    # When `port` is nil, the child process is started with -p 0 and the
    # OS-assigned port is read back from its output, eliminating the
    # probe-and-release TOCTOU race between port selection and bind.
    def self.serve_static_directory(dir, hostname: 'localhost', port: nil, allowed_base: nil)
      resolved_dir = validate_serve_directory!(dir, allowed_base: allowed_base)

      child_port = port.nil? ? 0 : port.to_i
      # '--' guards against a `resolved_dir` that begins with '-' being
      # interpreted as a flag by un.rb#httpd's OptionParser.
      process = IO.popen(
        [
          'ruby', '-run', '-e', 'httpd', '--', resolved_dir, '-p', child_port.to_s,
          err: [:child, :out],
        ].flatten,
      )

      bound_port = port.nil? ? read_bound_port(process) : port
      # Drain the child's stdout in the background. WEBrick logs every
      # request to stderr (redirected here onto stdout). Without a reader,
      # the OS pipe buffer (~64KB) fills and WEBrick blocks inside Logger,
      # stalling request handling.
      drain_io_in_background(process)
      verify_http_server_up(hostname, port: bound_port)
      process.pid
    end

    private_class_method def self.validate_serve_directory!(dir, allowed_base:)
      raise InvalidServeDirectory, 'dir must be provided' if dir.nil? || dir.to_s.empty?

      begin
        resolved = File.realpath(dir.to_s)
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise InvalidServeDirectory, "dir does not resolve to an existing directory: #{dir}"
      end

      unless File.directory?(resolved)
        raise InvalidServeDirectory, "dir is not a directory: #{dir}"
      end

      if allowed_base
        base = File.realpath(allowed_base.to_s)
        unless resolved == base || resolved.start_with?(base + File::SEPARATOR)
          raise InvalidServeDirectory,
            "dir #{resolved} is outside allowed_base #{base}"
        end
      end

      resolved
    end

    # Matches the WEBrick startup banner, e.g.:
    #   [2026-06-30 09:30:05] INFO  WEBrick::HTTPServer#start: pid=70189 port=58046
    # Anchoring to `pid=N port=N` avoids latching onto a literal `port=N`
    # substring that could appear elsewhere in the child's output (for
    # example, in an echoed DocumentRoot path).
    BOUND_PORT_PATTERN = /pid=\d+\s+port=(\d+)/.freeze

    private_class_method def self.read_bound_port(process, timeout_seconds: 10)
      deadline = Time.now + timeout_seconds
      buffer = +''
      loop do
        remaining = deadline - Time.now
        break if remaining <= 0

        ready = IO.select([process], nil, nil, remaining)
        break unless ready

        begin
          chunk = process.read_nonblock(4096)
        rescue IO::WaitReadable
          next
        rescue EOFError
          break
        end

        buffer << chunk
        if (match = buffer.match(BOUND_PORT_PATTERN))
          return match[1].to_i
        end
      end

      raise ServerDown, "Could not determine bound port from child process output: #{buffer}"
    end

    private_class_method def self.drain_io_in_background(io)
      Thread.new do
        begin
          io.read until io.closed?
        rescue IOError, Errno::EBADF
          # Stream closed -- nothing more to drain.
        end
      end
    end
  end
end
