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
    Setting.stubs(:syncs_include_pending).returns(true)

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
    assert_equal true, entry.transaction.extra.dig("teller", "pending")
  end

  test "skips pending transactions when pending inclusion is disabled" do
    Setting.stubs(:syncs_include_pending).returns(false)

    txn = {
      id: "txn_pending_disabled",
      account_id: @teller_account.teller_account_id,
      amount: "-20.00",
      date: "2026-10-20",
      description: "Pending auth hold",
      status: "pending"
    }

    # Clear the env var so this only exercises the Setting fallback branch of pending_enabled?
    with_env_overrides TELLER_INCLUDE_PENDING: nil do
      assert_no_difference "Entry.count" do
        TellerEntry::Processor.new(txn, teller_account: @teller_account).process
      end
    end
  end

  test "still imports posted transactions when pending inclusion is disabled" do
    Setting.stubs(:syncs_include_pending).returns(false)

    txn = {
      id: "txn_posted_disabled",
      account_id: @teller_account.teller_account_id,
      amount: "-20.00",
      date: "2026-10-20",
      description: "Posted charge",
      status: "posted"
    }

    with_env_overrides TELLER_INCLUDE_PENDING: nil do
      assert_difference "Entry.count", 1 do
        TellerEntry::Processor.new(txn, teller_account: @teller_account).process
      end
    end
  end

  test "TELLER_INCLUDE_PENDING env var takes precedence over Setting" do
    # Setting says "skip pending", but the env var says "include pending" - env var must win
    Setting.stubs(:syncs_include_pending).returns(false)

    txn = {
      id: "txn_pending_env_override",
      account_id: @teller_account.teller_account_id,
      amount: "-20.00",
      date: "2026-10-20",
      description: "Pending auth hold",
      status: "pending"
    }

    with_env_overrides TELLER_INCLUDE_PENDING: "true" do
      assert_difference "Entry.count", 1 do
        TellerEntry::Processor.new(txn, teller_account: @teller_account).process
      end
    end
  end

  test "TELLER_INCLUDE_PENDING env var disabling pending takes precedence over a permissive Setting" do
    # A self-hoster sets TELLER_INCLUDE_PENDING=false while the Setting (UI toggle)
    # still says "include pending". The env var must win and skip the row.
    Setting.stubs(:syncs_include_pending).returns(true)

    txn = {
      id: "txn_pending_env_disable",
      account_id: @teller_account.teller_account_id,
      amount: "-20.00",
      date: "2026-10-20",
      description: "Pending auth hold",
      status: "pending"
    }

    with_env_overrides TELLER_INCLUDE_PENDING: "false" do
      assert_no_difference "Entry.count" do
        TellerEntry::Processor.new(txn, teller_account: @teller_account).process
      end
    end
  end
end
