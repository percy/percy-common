# frozen_string_literal: true

require 'redis'

module Percy
  class Redis
    attr_reader :options
    attr_reader :client

    def initialize(options = {})
      @options = options
      @client = ::Redis.new(
        options.merge(
          ssl: ssl_enabled?,
          ssl_params: ssl_params,
        ),
      )
    end

    private def ssl_enabled?
      options[:url]&.start_with?('rediss://')
    end

    private def ssl_params
      return {} unless ssl_enabled?

      {
        ca_file: certificate_authority_file,
        cert: OpenSSL::X509::Certificate.new(client_certificate),
        key: OpenSSL::PKey::RSA.new(private_key),
      }
    end

    private def client_certificate
      ENV.fetch(
        'REDIS_SSL_CLIENT_CERTIFICATE',
        File.read(client_certificate_path),
      )
    end

    private def client_certificate_path
      ENV.fetch(
        'REDIS_SSL_CLIENT_CERTIFICATE_PATH',
        File.join(cert_path, 'user.crt'),
      )
    end

    private def private_key
      ENV.fetch(
        'REDIS_SSL_PRIVATE_KEY',
        File.read(private_key_path),
      )
    end

    private def private_key_path
      ENV.fetch(
        'REDIS_SSL_PRIVATE_KEY_PATH',
        File.join(cert_path, 'user_private.key'),
      )
    end

    private def certificate_authority_file
      ENV.fetch(
        'REDIS_SSL_CERTIFICATE_AUTHORITY_PATH',
        File.join(cert_path, 'server_ca.pem'),
      )
    end

    private def cert_path
      ENV.fetch(
        'REDIS_SSL_CERTIFICATE_PATH',
        File.expand_path('../../redis', __dir__),
      )
    end
  end
end
