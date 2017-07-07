require 'socket'
require 'excon'

module Percy
  class NetworkHelpers
    class ServerDown < RuntimeError; end

    def self.random_open_port
      # Using a port of "0" relies on the system to pick an open port.
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1]
      server.close
      port
    end

    def self.verify_healthcheck(url:, expected_body: 'ok', retry_wait_seconds: 0.5)
      10.times do
        begin
          response = Excon.get(url)
          return true if response.body == expected_body
        rescue Excon::Error::Socket, Excon::Error::Timeout
          sleep retry_wait_seconds
        end
      end
      raise ServerDown, "Healthcheck failed for #{url}"
    end

    def self.verify_http_server_up(hostname, port: nil, path: nil, retry_wait_seconds: 0.25)
      10.times do
        begin
          Excon.get("http://#{hostname}#{port.nil? ? '' : ':' + port.to_s}#{path || ''}")
          return true
        rescue Excon::Error::Socket, Excon::Error::Timeout
          sleep retry_wait_seconds
        end
      end
      raise ServerDown, "Server is down: #{hostname}"
    end

    def self.serve_static_directory(dir, hostname: 'localhost', port: nil)
      port ||= random_open_port

      # Note: using this form of popen to keep stdout and stderr silent and captured.
      process = IO.popen(
        [
          'ruby', '-run', '-e', 'httpd', dir, '-p', port.to_s, err: [:child, :out],
        ].flatten,
      )
      verify_http_server_up(hostname, port: port)
      process.pid
    end
  end
end
