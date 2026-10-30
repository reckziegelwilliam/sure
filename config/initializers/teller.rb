Rails.application.configure do
  config.x.teller ||= ActiveSupport::OrderedOptions.new
  config.x.teller.application_id = ENV["TELLER_APPLICATION_ID"]
  config.x.teller.environment = ENV["TELLER_ENVIRONMENT"].presence || "sandbox"
  config.x.teller.cert_path = ENV["TELLER_CERT_PATH"]
  config.x.teller.key_path = ENV["TELLER_KEY_PATH"]
end
