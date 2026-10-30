require "test_helper"

class TellerItemTest < ActiveSupport::TestCase
  test "encrypts access_token" do
    item = TellerItem.create!(
      family: families(:dylan_family),
      name: "Test Teller Connection",
      access_token: "token_plaintext_123",
      enrollment_id: "enr_test",
      institution_name: "Chase"
    )

    raw = ActiveRecord::Base.connection.execute(
      "SELECT access_token FROM teller_items WHERE id = '#{item.id}'"
    ).first["access_token"]

    assert_not_equal "token_plaintext_123", raw
    assert_equal "token_plaintext_123", item.reload.access_token
  end

  test "has_many teller_accounts with dependent destroy" do
    item = teller_items(:chase_connection)
    assert item.teller_accounts.any?

    account_ids = item.teller_accounts.pluck(:id)
    item.destroy

    account_ids.each do |id|
      assert_nil TellerAccount.find_by(id: id)
    end
  end
end
