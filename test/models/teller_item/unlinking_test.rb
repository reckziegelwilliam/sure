require "test_helper"

class TellerItem::UnlinkingTest < ActiveSupport::TestCase
  test "unlink_all! destroys AccountProvider links for this item's teller accounts only" do
    item = teller_items(:chase_connection)
    other_item = TellerItem.create!(
      family: item.family,
      name: "Other Teller",
      access_token: "token_other",
      enrollment_id: "enr_other"
    )
    other_teller_account = TellerAccount.create!(teller_item: other_item, teller_account_id: "acc_other")

    link = AccountProvider.create!(account: accounts(:depository), provider: teller_accounts(:chase_checking))
    other_link = AccountProvider.create!(account: accounts(:credit_card), provider: other_teller_account)

    item.unlink_all!(dry_run: false)

    assert_not AccountProvider.exists?(link.id)
    assert AccountProvider.exists?(other_link.id)
  end

  test "unlink_all! with dry_run does not destroy any links" do
    item = teller_items(:chase_connection)
    link = AccountProvider.create!(account: accounts(:depository), provider: teller_accounts(:chase_checking))

    item.unlink_all!(dry_run: true)

    assert AccountProvider.exists?(link.id)
  end
end
