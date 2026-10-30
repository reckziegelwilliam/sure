require "test_helper"

class TellerItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @item = teller_items(:chase_connection)
    @provider = mock("Provider::Teller")
    AccountProvider.create!(account: accounts(:depository), provider: teller_accounts(:chase_checking))
  end

  test "import fetches accounts, balances, and transactions, then processes each transaction" do
    accounts_payload = [
      {
        id: "acc_fixture_checking",
        enrollment_id: @item.enrollment_id,
        institution: { id: "chase", name: "Chase" },
        type: "depository",
        name: "Checking",
        subtype: "checking",
        currency: "USD",
        last_four: "7723",
        status: "open"
      }
    ]
    balances_payload = { ledger: "1500.00", available: "1450.00", account_id: "acc_fixture_checking" }
    transactions_payload = [
      {
        id: "txn_new_1",
        account_id: "acc_fixture_checking",
        amount: "-20.00",
        date: "2026-10-20",
        description: "Test Merchant",
        status: "posted"
      }
    ]

    @provider.expects(:get_accounts).with(@item.access_token).returns(accounts_payload)
    @provider.expects(:get_balances).with(@item.access_token, "acc_fixture_checking").returns(balances_payload)
    @provider.expects(:get_transactions).with(@item.access_token, "acc_fixture_checking").returns(transactions_payload)

    importer = TellerItem::Importer.new(@item, provider: @provider)

    assert_difference "Entry.count", 1 do
      importer.import
    end

    account = @item.teller_accounts.find_by(teller_account_id: "acc_fixture_checking")
    assert_equal 1500.00, account.current_balance
    assert_equal 1450.00, account.available_balance
  end

  test "import skips transaction import for unlinked accounts" do
    unlinked_account_payload = {
      id: "acc_unlinked_new",
      enrollment_id: @item.enrollment_id,
      institution: { id: "chase", name: "Chase" },
      type: "depository",
      name: "New Account",
      subtype: "savings",
      currency: "USD",
      last_four: "5678",
      status: "open"
    }
    balances_payload = { ledger: "2500.00", available: "2400.00", account_id: "acc_unlinked_new" }

    @provider.expects(:get_accounts).with(@item.access_token).returns([unlinked_account_payload])
    @provider.expects(:get_balances).with(@item.access_token, "acc_unlinked_new").returns(balances_payload)
    # Explicitly do NOT set up get_transactions for this unlinked account—calling it would raise an error
    @provider.expects(:get_transactions).never

    importer = TellerItem::Importer.new(@item, provider: @provider)

    # Assert no new entries are created (transactions not imported for unlinked account)
    assert_no_difference "Entry.count" do
      importer.import
    end

    # Assert the TellerAccount was created with balances populated
    unlinked_account = @item.teller_accounts.find_by(teller_account_id: "acc_unlinked_new")
    assert_not_nil unlinked_account
    assert_nil unlinked_account.current_account, "Unlinked account should have no linked Account"
    assert_equal 2500.00, unlinked_account.current_balance
    assert_equal 2400.00, unlinked_account.available_balance
  end
end
