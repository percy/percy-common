require 'datadog/statsd'
require 'time'

module Percy
  class Stats < ::Datadog::Statsd
    def initialize(host = nil, port = nil, opts = {}, max_buffer_size = 50)
      host ||= ENV.fetch('DATADOG_AGENT_HOST', ::Datadog::Statsd::DEFAULT_HOST)
      port ||= Integer(ENV.fetch('DATADOG_AGENT_PORT', ::Datadog::Statsd::DEFAULT_PORT))
      opts[:tags] ||= []
      opts[:tags] << "env:#{ENV['PERCY_ENV'] || 'development'}"
      retry_delay = opts[:retry_delay] || 1
      retry_count = opts[:retry_count] || 3
      retries = 0

      begin
        super(host, port, opts, max_buffer_size)
      rescue SocketError
        host = 'localhost' if retries >= retry_count
        sleep retry_delay
        retries += 1
        retry
      end
    end

    # Equivalent to stats.time, but without wrapping in blocks and dealing with var scoping issues.
    #
    # @example Report the time taken to activate an account.
    #   stats.start_timing
    #   account.activate!
    #   stats.stop_timing('account.activate')
    def start_timing
      @_timing_start = Time.now
      true
    end

    def stop_timing(stat, options = {})
      raise 'no timing started' unless @_timing_start # Programmer mistake, so raise an error.
      time_since(stat, @_timing_start, options)
      @_timing_start = nil
      true
    end
  end
end
