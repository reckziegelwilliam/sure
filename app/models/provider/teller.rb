class Provider::Teller
  include HTTParty
  extend SslConfigurable

  base_uri "https://api.teller.io"
  headers "User-Agent" => "Sure Finance Teller Client"
  default_options.merge!({ timeout: 30 }.merge(httparty_ssl_options))

  MAX_RETRIES = 3
  INITIAL_RETRY_DELAY = 2
  MAX_RETRY_DELAY = 30

  RETRYABLE_ERRORS = [
    SocketError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    EOFError
  ].freeze

  def initialize
  end

  def get_accounts(access_token)
    response = with_retries("GET /accounts") do
      self.class.get("https://api.teller.io/accounts", **request_options(access_token))
    end
    handle_response(response, "fetch accounts")
  end

  def get_transactions(access_token, account_id)
    response = with_retries("GET /accounts/#{account_id}/transactions") do
      self.class.get(
        "https://api.teller.io/accounts/#{account_id}/transactions",
        **request_options(access_token)
      )
    end
    handle_response(response, "fetch transactions")
  end

  def get_balances(access_token, account_id)
    response = with_retries("GET /accounts/#{account_id}/balances") do
      self.class.get(
        "https://api.teller.io/accounts/#{account_id}/balances",
        **request_options(access_token)
      )
    end
    handle_response(response, "fetch balances")
  end

  class TellerError < StandardError
    attr_reader :error_type

    def initialize(message, error_type = :unknown)
      super(message)
      @error_type = error_type
    end
  end

  private
    # Teller requires BOTH the access token as HTTP Basic Auth username
    # (blank password) AND, outside sandbox, a client mTLS certificate
    # issued per-application from the Teller Dashboard. The cert is
    # configured once for the whole instance (see config/initializers/teller.rb),
    # not per-request, since it authenticates the application, not the user.
    def request_options(access_token)
      opts = { basic_auth: { username: access_token, password: "" }, follow_redirects: false }

      cert_path = Rails.configuration.x.teller.cert_path
      key_path = Rails.configuration.x.teller.key_path
      if cert_path.present? && key_path.present?
        # HTTParty's :pem option expects certificate and key concatenated into one PEM blob
        opts[:pem] = File.read(cert_path) + File.read(key_path)
        opts[:pem_password] = nil
      end

      opts
    end

    def handle_response(response, operation_name)
      case response.code
      when 200
        JSON.parse(response.body, symbolize_names: true)
      when 401
        raise TellerError.new("Teller access token is invalid or revoked", :unauthorized)
      when 404
        raise TellerError.new("Teller resource not found", :not_found)
      when 429
        Rails.logger.warn "Teller API: Rate limited - #{response.body}"
        raise TellerError.new("Teller rate limit exceeded. Please try again later.", :rate_limited)
      when 500..599
        Rails.logger.error "Teller API: Server error - Code: #{response.code}, Body: #{response.body}"
        raise TellerError.new("Teller server error (#{response.code}). Please try again later.", :server_error)
      else
        Rails.logger.error "Teller API: Unexpected response - Code: #{response.code}, Body: #{response.body}"
        raise TellerError.new("Failed to #{operation_name}: #{response.code} #{response.message}", :fetch_failed)
      end
    end

    def with_retries(operation_name, max_retries: MAX_RETRIES)
      retries = 0
      begin
        yield
      rescue *RETRYABLE_ERRORS => e
        retries += 1
        if retries <= max_retries
          delay = [ INITIAL_RETRY_DELAY * (2 ** (retries - 1)), MAX_RETRY_DELAY ].min
          Rails.logger.warn "Teller API: #{operation_name} failed (attempt #{retries}/#{max_retries}): #{e.class}. Retrying in #{delay}s..."
          sleep(delay)
          retry
        else
          raise TellerError.new("Network error after #{max_retries} retries: #{e.message}", :network_error)
        end
      rescue TellerError
        raise
      rescue => e
        Rails.logger.error "Teller API: #{operation_name} failed with non-retryable error: #{e.class}: #{e.message}"
        raise TellerError.new("Exception during #{operation_name}: #{e.message}", :request_failed)
      end
    end
end
