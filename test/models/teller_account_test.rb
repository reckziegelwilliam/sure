require "test_helper"

class TellerAccountTest < ActiveSupport::TestCase
  test "belongs_to teller_item" do
    account = teller_accounts(:chase_checking)
    assert_equal teller_items(:chase_connection), account.teller_item
  end

  test "current_account returns linked internal Account" do
    account = teller_accounts(:chase_checking)
    assert_equal accounts(:depository), account.current_account
  end
end
