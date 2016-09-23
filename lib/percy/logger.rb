require 'logger'
require 'syslog-logger'

module Percy
  def self.logger
    @logger if defined?(@logger)
    @logger ||= Logger::Syslog.new('percy', Syslog::LOG_LOCAL7)
    @logger.level = Logger::INFO if ENV['PERCY_ENV'] == 'production'
    @logger
  end
end
