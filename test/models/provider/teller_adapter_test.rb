require "test_helper"

class Provider::TellerAdapterTest < ActiveSupport::TestCase
  test "supported_account_types excludes investments" do
    assert_equal %w[Depository CreditCard], Provider::TellerAdapter.supported_account_types
  end

  test "provider_name is teller" do
    account = teller_accounts(:chase_checking)
    adapter = Provider::TellerAdapter.new(account)
    assert_equal "teller", adapter.provider_name
  end

  test "institution_name reads from teller_item" do
    account = teller_accounts(:chase_checking)
    adapter = Provider::TellerAdapter.new(account)
    assert_equal "Chase", adapter.institution_name
  end

  test "registered in Provider::Factory" do
    account = teller_accounts(:chase_checking)
    assert_equal Provider::TellerAdapter, Provider::Factory.create_adapter(account).class
  end
end
