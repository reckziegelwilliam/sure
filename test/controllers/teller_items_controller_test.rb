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
end
