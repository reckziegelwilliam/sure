require "test_helper"

class TellerItemsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :users, :families

  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
  end

  test "create persists a new teller item from Connect widget params and redirects" do
    assert_difference "TellerItem.count", 1 do
      post teller_items_path, params: {
        teller_item: {
          access_token: "token_from_widget",
          enrollment_id: "enr_from_widget",
          institution_name: "Example Bank"
        }
      }
    end

    assert_response :see_other
    item = TellerItem.order(created_at: :desc).first
    assert_equal "token_from_widget", item.access_token
  end

  test "create enqueues a sync job" do
    assert_enqueued_with(job: SyncJob) do
      post teller_items_path, params: {
        teller_item: { access_token: "t", enrollment_id: "e", institution_name: "Bank" }
      }
    end
  end

  test "destroy flags for deletion and enqueues DestroyJob" do
    item = teller_items(:chase_connection)

    assert_enqueued_with(job: DestroyJob, args: [ item ]) do
      delete teller_item_path(item)
    end

    assert item.reload.scheduled_for_deletion
    assert_response :see_other
  end

  test "sync enqueues a sync job" do
    item = teller_items(:chase_connection)

    assert_enqueued_with(job: SyncJob) do
      post sync_teller_item_path(item)
    end
  end

  test "link_existing_account links a teller account owned by the current family" do
    teller_account = teller_accounts(:chase_checking)
    account = accounts(:depository)

    post link_existing_account_teller_items_path, params: {
      account_id: account.id,
      teller_account_id: teller_account.id
    }

    assert_response :see_other
    assert_equal account, teller_account.reload.current_account
  end

  test "select_existing_account renders unlinked teller accounts for the family" do
    account = accounts(:depository)

    get select_existing_account_teller_items_path(account_id: account.id)

    assert_response :success
    assert_select "input[name='teller_account_id'][value=?]", teller_accounts(:chase_checking).id
  end

  test "link_existing_account rejects a teller account from a different family" do
    other_family = Family.create!(name: "Other Family")
    other_item = TellerItem.create!(
      family: other_family,
      name: "Other Bank",
      access_token: "token_other",
      enrollment_id: "enr_other"
    )
    other_teller_account = TellerAccount.create!(
      teller_item: other_item,
      teller_account_id: "acc_other_family"
    )

    post link_existing_account_teller_items_path, params: {
      account_id: accounts(:depository).id,
      teller_account_id: other_teller_account.id
    }

    assert_response :not_found
  end

  test "setup_accounts renders each unlinked teller account" do
    item = teller_items(:chase_connection)
    unlinked = item.teller_accounts.create!(teller_account_id: "acc_unlinked_setup", name: "Needs Setup")

    get setup_accounts_teller_item_path(item)

    assert_response :success
    assert_select "input[name='account_types[#{unlinked.id}]']", false
    assert_select "select[name='account_types[#{unlinked.id}]']"
  end

  test "setup_accounts does not list already-linked teller accounts" do
    item = teller_items(:chase_connection)
    linked = item.teller_accounts.create!(teller_account_id: "acc_linked_setup", name: "Already Set Up")
    account = Account.create!(
      family: @family, name: "Linked Account", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "checking")
    )
    AccountProvider.create!(account: account, provider: linked)

    get setup_accounts_teller_item_path(item)

    assert_response :success
    assert_select "select[name='account_types[#{linked.id}]']", false
  end

  test "complete_account_setup creates accounts only for truly unlinked teller accounts" do
    item = teller_items(:chase_connection)

    linked = item.teller_accounts.create!(teller_account_id: "acc_l_1", name: "Linked", current_balance: 5, currency: "USD")
    linked_account = Account.create!(
      family: @family, name: "Already Linked", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "savings")
    )
    AccountProvider.create!(account: linked_account, provider: linked)

    unlinked = item.teller_accounts.create!(teller_account_id: "acc_cc_1", name: "New CC", current_balance: -20, currency: "USD")
    skipped = item.teller_accounts.create!(teller_account_id: "acc_skip_1", name: "Skip Me", current_balance: 1, currency: "USD")

    assert_enqueued_with(job: SyncJob) do
      assert_difference "Account.count", 1 do
        post complete_account_setup_teller_item_path(item), params: {
          account_types: { unlinked.id => "CreditCard", skipped.id => "skip" },
          account_subtypes: { unlinked.id => "credit_card" }
        }
      end
    end

    assert_response :see_other
    assert_redirected_to accounts_path

    assert_not_nil unlinked.reload.account_provider
    assert_nil skipped.reload.account_provider
    assert_equal linked_account.id, linked.reload.account&.id
  end
end
