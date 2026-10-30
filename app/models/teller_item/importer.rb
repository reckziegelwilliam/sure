class TellerItem::Importer
  def initialize(teller_item, provider: nil)
    @teller_item = teller_item
    @provider = provider || Provider::Teller.new
  end

  def import
    accounts_payload = provider.get_accounts(teller_item.access_token)

    accounts_payload.each do |account_payload|
      teller_account = find_or_create_account(account_payload)
      import_balances(teller_account)
      import_transactions(teller_account) if teller_account.current_account.present?
    end

    teller_item.update!(raw_payload: { accounts: accounts_payload.map { |a| a[:id] } })
  end

  private
    attr_reader :teller_item, :provider

    def find_or_create_account(payload)
      teller_item.teller_accounts.find_or_initialize_by(teller_account_id: payload[:id]).tap do |record|
        record.name = payload[:name]
        record.account_type = payload[:type]
        record.account_subtype = payload[:subtype]
        record.currency = payload[:currency]
        record.last_four = payload[:last_four]
        record.raw_payload = payload
        record.save!
      end
    end

    def import_balances(teller_account)
      balances = provider.get_balances(teller_item.access_token, teller_account.teller_account_id)
      teller_account.update!(
        current_balance: parse_balance(balances[:ledger]),
        available_balance: parse_balance(balances[:available])
      )
    end

    def parse_balance(value)
      return nil if value.blank?
      BigDecimal(value.to_s)
    end

    # Newly-discovered TellerAccount records have no linked internal Account until
    # the user links one via the account-linking UI, so there's nothing to import
    # transactions into yet. The TellerAccount row and its balances are still useful
    # on their own and are created/updated above regardless.
    def import_transactions(teller_account)
      transactions = provider.get_transactions(teller_item.access_token, teller_account.teller_account_id)
      shared_adapter = Account::ProviderImportAdapter.new(teller_account.current_account)

      transactions.each do |txn|
        TellerEntry::Processor.new(txn, teller_account: teller_account, import_adapter: shared_adapter).process
      end
    end
end
