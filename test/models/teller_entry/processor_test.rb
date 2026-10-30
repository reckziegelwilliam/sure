require "test_helper"

class TellerEntry::ProcessorTest < ActiveSupport::TestCase
  setup do
    @teller_account = teller_accounts(:chase_checking)
  end

  test "pending? is true when status is pending" do
    txn = { id: "txn_1", status: "pending", amount: "-12.50", date: "2026-10-20", description: "Coffee" }
    assert TellerEntry::Processor.pending?(txn)
  end

  test "pending? is false when status is posted" do
    txn = { id: "txn_1", status: "posted", amount: "-12.50", date: "2026-10-20", description: "Coffee" }
    assert_not TellerEntry::Processor.pending?(txn)
  end

  test "process imports a posted transaction with negated amount" do
    txn = {
      id: "txn_abc",
      account_id: @teller_account.teller_account_id,
      amount: "-45.00",
      date: "2026-10-20",
      description: "WHOLE FOODS MARKET",
      type: "card_payment",
      status: "posted",
      details: { counterparty: { name: "Whole Foods", type: "organization" } }
    }

    processor = TellerEntry::Processor.new(txn, teller_account: @teller_account)

    assert_difference "Entry.count", 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first
    assert_equal 45.00, entry.amount
    assert_equal "WHOLE FOODS MARKET", entry.name
    assert_equal "teller", entry.source
  end

  test "process writes pending flag into extra" do
    txn = {
      id: "txn_pending",
      account_id: @teller_account.teller_account_id,
      amount: "-10.00",
      date: "2026-10-20",
      description: "Pending charge",
      status: "pending"
    }

    TellerEntry::Processor.new(txn, teller_account: @teller_account).process

    entry = Entry.order(created_at: :desc).first
    assert_equal true, entry.entryable.extra.dig("teller", "pending")
  end
end
