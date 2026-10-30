require "test_helper"

class Family::TellerConnectableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @original_application_id = Rails.configuration.x.teller.application_id
    Rails.configuration.x.teller.application_id = "test_app_id"
  end

  teardown do
    Rails.configuration.x.teller.application_id = @original_application_id
  end

  test "can_connect_teller? is true" do
    assert @family.can_connect_teller?
  end

  test "create_teller_item! persists the access token directly without a claim step" do
    item = @family.create_teller_item!(
      access_token: "token_new_abc",
      enrollment_id: "enr_new_abc",
      institution_name: "Bank of Example"
    )

    assert item.persisted?
    assert_equal "token_new_abc", item.access_token
    assert_equal "Bank of Example", item.institution_name
    assert_equal @family, item.family
  end

  test "create_teller_item! enqueues a sync" do
    assert_enqueued_with(job: TellerConnectionUpdateJob) do
      @family.create_teller_item!(
        access_token: "token_new_abc",
        enrollment_id: "enr_new_abc",
        institution_name: "Bank of Example"
      )
    end
  end
end
