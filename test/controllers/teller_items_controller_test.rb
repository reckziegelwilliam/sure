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
    assert_enqueued_with(job: TellerConnectionUpdateJob) do
      post teller_items_path, params: {
        teller_item: { access_token: "t", enrollment_id: "e", institution_name: "Bank" }
      }
    end
  end

  test "destroy soft-deletes via scheduled_for_deletion" do
    item = teller_items(:chase_connection)

    assert_difference "TellerItem.count", 0 do
      delete teller_item_path(item)
    end

    assert item.reload.scheduled_for_deletion
  end

  test "sync enqueues the connection update job" do
    item = teller_items(:chase_connection)

    assert_enqueued_with(job: TellerConnectionUpdateJob, args: [ item ]) do
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
end
