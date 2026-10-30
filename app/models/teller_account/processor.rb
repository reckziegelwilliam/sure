class TellerAccount::Processor
  attr_reader :teller_account

  def initialize(teller_account)
    @teller_account = teller_account
  end

  def process
    return unless teller_account.current_account.present?

    process_balance!
  end

  private
    def process_balance!
      account = teller_account.current_account

      observed = teller_account.current_balance.nil? ? teller_account.available_balance : teller_account.current_balance
      return if observed.nil?

      is_liability = account.accountable_type == "CreditCard"

      balance =
        if is_liability
          normalize_liability_balance(observed)
        else
          observed
        end

      Account::ProviderImportAdapter.new(account).update_balance(
        balance: balance,
        cash_balance: balance,
        source: "teller"
      )
    end

    # Teller reports credit card balances as the outstanding debt (a positive
    # number). Sure's internal convention for a CreditCard account's `balance`
    # is debt-as-positive too (mirrors SimpleFIN's "debt" classification), so
    # the normal case is a no-op abs. `balance_sign_override` lets a user flip
    # a specific connection that reports the opposite sign (observed matching
    # SimpleFIN's own `balance_sign_override` column/semantics on
    # SimplefinAccount, see simplefin_account/processor.rb).
    def normalize_liability_balance(observed)
      case teller_account.balance_sign_override
      when "credit"
        -observed.abs
      when "debt"
        observed.abs
      else
        observed.abs
      end
    end
end
