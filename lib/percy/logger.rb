require 'logger'

module Percy
  def self.logger
    @logger if defined?(@logger)
    @logger ||= Logger.new(STDOUT)
    @logger.level = Logger::INFO if ENV['PERCY_ENV'] == 'production'
    @logger.formatter = proc do |severity, _datetime, _progname, msg|
      "[#{severity}] #{msg}\n"
    end
    @logger
  end
end
