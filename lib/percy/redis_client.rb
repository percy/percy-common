# frozen_string_literal: true

require 'redis'

module Percy
  class RedisClient
    class InvalidConfiguration < ArgumentError
    end
    attr_reader :client
    attr_reader :options

    def initialize(given_options = {})
      @provided_options = given_options
      @options = ssl_options.merge(given_options)
      @client = ::Redis.new(options)
    end

    private def ssl_enabled?
      provided_url.to_s.start_with?('rediss://')
    end

    private def provided_url
      @provided_options&.dig(:url)
    end

    private def ssl_options
      {
        ssl: ssl_enabled?,
        ssl_params: ssl_params,
      }
    end

    private def ssl_params
      return {} unless ssl_enabled?

      {
        ca_file: certificate_authority,
        cert: OpenSSL::X509::Certificate.new(client_certificate),
        key: OpenSSL::PKey::RSA.new(private_key),
      }
    end

    private def client_certificate
      @provided_options&.dig(:ssl_params, :cert) ||
        client_certificate_from_env ||
        client_certificate_from_path
    end

    private def client_certificate_from_env
      ENV['REDIS_SSL_CLIENT_CERTIFICATE']
    end

    private def client_certificate_from_path
      File.read(fetch_key('REDIS_SSL_CLIENT_CERTIFICATE_PATH'))
    end

    private def private_key
      provided_private_key ||
        private_key_from_env ||
        private_key_from_path
    end

    private def provided_private_key
      @provided_options&.dig(:ssl_params, :key)
    end

    private def private_key_from_env
      ENV['REDIS_SSL_PRIVATE_KEY']
    end

    private def private_key_from_path
      File.read(fetch_key('REDIS_SSL_PRIVATE_KEY_PATH'))
    end

    private def certificate_authority
      provided_certificate_authority ||
        certificate_authority_from_env ||
        certificate_authority_from_path
    end

    private def provided_certificate_authority
      @provided_options&.dig(:ssl_params, :ca_file)
    end

    private def certificate_authority_from_env
      ENV['REDIS_SSL_CERTIFICATE_AUTHORITY']
    end

    private def certificate_authority_from_path
      File.read(fetch_key('REDIS_SSL_CERTIFICATE_AUTHORITY_PATH'))
    end

    private def fetch_key(key)
      ENV.fetch(key) { missing_key(key) }
    end

    private def missing_key(key)
      raise InvalidConfiguration, "#{key} is not defined"
    end
  end
end
