require "digest/md5"

class TellerEntry::Processor
  SOURCE = "teller"

  def initialize(teller_transaction, teller_account:, import_adapter: nil)
    @teller_transaction = teller_transaction
    @teller_account = teller_account
    @shared_import_adapter = import_adapter
  end

  def self.pending?(teller_transaction)
    data = teller_transaction.with_indifferent_access
    data[:status].to_s == "pending"
  end

  def process
    import_adapter.import_transaction(
      external_id: external_id,
      amount: amount,
      currency: currency,
      date: date,
      name: name,
      source: SOURCE,
      merchant: merchant,
      extra: extra_metadata,
      replace_extra_namespaces: [ "teller" ]
    )
  end

  private
    attr_reader :teller_account

    def data = @data ||= teller_transaction.with_indifferent_access
    def teller_transaction = @teller_transaction

    def pending? = self.class.pending?(data)

    def import_adapter
      @import_adapter ||= @shared_import_adapter || Account::ProviderImportAdapter.new(account)
    end

    def account = teller_account.current_account

    def external_id
      id = data[:id].presence
      raise ArgumentError, "Teller transaction missing id: #{data.inspect}" unless id
      "teller_#{id}"
    end

    def name
      data[:description].presence || I18n.t("transactions.unknown_name")
    end

    # Teller reports debits (purchases) as negative amount strings in its API,
    # following banking convention similar to SimpleFIN — negated here to match
    # Sure's internal convention (negative = inflow, positive = outflow).
    # Assumption pending real sandbox verification. If sandbox data shows
    # the opposite sign, remove the unary minus below.
    def amount
      parsed = BigDecimal(data[:amount].to_s)
      -parsed
    rescue ArgumentError => e
      Rails.logger.error "Failed to parse Teller transaction amount: #{data[:amount].inspect} - #{e.message}"
      raise
    end

    def currency = teller_account.currency.presence || "USD"

    def date
      raw = data[:date]
      raise ArgumentError, "Teller transaction missing date: #{data.inspect}" if raw.blank?
      Date.parse(raw.to_s)
    end

    def counterparty_name
      data.dig(:details, :counterparty, :name)
    end

    def merchant
      payee = counterparty_name&.strip
      return nil if payee.blank?

      @merchant ||= import_adapter.find_or_create_merchant(
        provider_merchant_id: "teller_#{Digest::MD5.hexdigest(payee.downcase)}",
        name: payee,
        source: SOURCE
      )
    end

    def extra_metadata
      teller = {
        "pending" => pending?,
        "type" => data[:type],
        "processing_status" => data.dig(:details, :processing_status),
        "category" => data.dig(:details, :category),
        "running_balance" => data[:running_balance]
      }.compact

      { "teller" => teller }
    end
end
