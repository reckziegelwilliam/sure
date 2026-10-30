require "test_helper"

class TellerItem::SyncerTest < ActiveSupport::TestCase
  setup do
    @item = teller_items(:chase_connection)
  end

  test "a rejected token fails the sync and flags the connection" do
    Provider::Teller.any_instance.stubs(:get_accounts)
      .raises(Provider::Teller::TellerError.new("Teller access token is invalid or revoked", :unauthorized))
    sync = Sync.create!(syncable: @item)

    sync.perform

    assert sync.reload.failed?, "expected the sync to fail, was #{sync.status}"
    assert_equal "Teller access token is invalid or revoked", sync.error
    assert @item.reload.requires_update?
  end

  test "a successful sync clears a previously-flagged connection and creates a Sync row" do
    @item.update!(status: :requires_update)
    account = accounts(:depository)
    AccountProvider.create!(account: account, provider: teller_accounts(:chase_checking))

    accounts_payload = [ {
      id: "acc_fixture_checking",
      type: "depository",
      name: "Checking",
      subtype: "checking",
      currency: "USD",
      last_four: "7723"
    } ]
    balances_payload = { ledger: "1600.00", available: "1550.00" }

    Provider::Teller.any_instance.stubs(:get_accounts).returns(accounts_payload)
    Provider::Teller.any_instance.stubs(:get_balances).returns(balances_payload)
    Provider::Teller.any_instance.stubs(:get_transactions).returns([])

    sync = Sync.create!(syncable: @item)

    # Deliberately does not drain the job queue: schedule_account_syncs enqueues a
    # nested Account::Syncer job, and letting that run here would recompute the
    # balance from entries. This test only verifies TellerItem::Syncer's own work.
    sync.perform

    # The sync stays "syncing" until its nested Account::Syncer child
    # (enqueued by schedule_account_syncs) finishes; TellerItem::Syncer's own
    # work -- importing, clearing the flagged status, pushing the balance --
    # already happened synchronously by this point.
    assert_nil sync.reload.error
    assert_equal "good", @item.reload.status
    assert_equal BigDecimal("1600.00"), account.reload.balance
  end
end
