require 'datadog/statsd'
require 'time'

module Percy
  class Stats < ::Datadog::Statsd
    DEFAULT_HOST = ENV.fetch(
      'DATADOG_AGENT_HOST',
      ::Datadog::Statsd::Connection::DEFAULT_HOST,
    )

    DEFAULT_PORT = Integer(
      ENV.fetch(
        'DATADOG_AGENT_PORT',
        ::Datadog::Statsd::Connection::DEFAULT_PORT,
      ),
    )

    DEFAULT_TAGS = %W[
      env:#{ENV.fetch('PERCY_ENV', 'development')}
    ].freeze

    def initialize(
      host = DEFAULT_HOST,
      port = DEFAULT_PORT,
      tags: DEFAULT_TAGS,
      **kwargs
    )
      super(host, port, tags: tags, **kwargs)
    end

    # Equivalent to stats.time, but without wrapping in blocks and dealing with
    # var scoping issues.
    #
    # @example Report the time taken to activate an account.
    #   stats.start_timing
    #   account.activate!
    #   stats.stop_timing('account.activate')
    def start_timing
      @_timing_start = now
      true
    end

    def stop_timing(stat, options = {})
      # Programmer mistake, so raise an error.
      raise 'no timing started' unless @_timing_start

      time_since(stat, @_timing_start, options)
      @_timing_start = nil
      true
    end

    def time_since(stat, start, opts = {})
      timing(stat, ((now.to_f - start.to_f) * 1000).round, opts)
    end

    private def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
