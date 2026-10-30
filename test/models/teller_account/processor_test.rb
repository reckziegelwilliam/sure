require "test_helper"

class TellerAccount::ProcessorTest < ActiveSupport::TestCase
  setup do
    @item = teller_items(:chase_connection)
  end

  test "does nothing for an unlinked account" do
    teller_account = teller_accounts(:chase_checking)
    assert_nil teller_account.current_account

    assert_nothing_raised do
      TellerAccount::Processor.new(teller_account).process
    end
  end

  test "pushes the depository balance through to the linked account" do
    teller_account = teller_accounts(:chase_checking)
    account = accounts(:depository)
    AccountProvider.create!(account: account, provider: teller_account)
    teller_account.update!(current_balance: BigDecimal("1500.00"), available_balance: BigDecimal("1450.00"))

    TellerAccount::Processor.new(teller_account).process

    assert_equal BigDecimal("1500.00"), account.reload.balance
    assert_equal BigDecimal("1500.00"), account.cash_balance
  end

  test "treats a positive credit card balance from Teller as debt by default" do
    teller_account = teller_accounts(:chase_checking)
    account = accounts(:credit_card)
    AccountProvider.create!(account: account, provider: teller_account)
    teller_account.update!(current_balance: BigDecimal("123.45"), available_balance: BigDecimal("76.55"))

    TellerAccount::Processor.new(teller_account).process

    assert_equal BigDecimal("123.45"), account.reload.balance
  end

  test "balance_sign_override 'credit' flips an ambiguous credit card balance" do
    teller_account = teller_accounts(:chase_checking)
    account = accounts(:credit_card)
    AccountProvider.create!(account: account, provider: teller_account)
    teller_account.update!(current_balance: BigDecimal("50.00"), balance_sign_override: "credit")

    TellerAccount::Processor.new(teller_account).process

    assert_equal BigDecimal("-50.00"), account.reload.balance
  end
end
