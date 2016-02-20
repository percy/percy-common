require 'logger'
require 'syslog-logger'

module Percy
  def self.logger
    @logger if defined?(@logger)

    if (ENV['PERCY_ENV'] || 'development') == 'development'
      @logger ||= Logger.new(STDOUT)
    else
      @logger ||= Logger::Syslog.new('percy', Syslog::LOG_LOCAL7)
      @logger.level = Logger::INFO
    end
    @logger
  end
end
