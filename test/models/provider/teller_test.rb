require "test_helper"

class Provider::TellerTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Teller.new
    @access_token = "token_test123"
  end

  test "get_accounts returns parsed JSON on success" do
    accounts_json = [
      {
        id: "acc_oiin624iajrg2mp2ea000",
        enrollment_id: "enr_test123",
        institution: { id: "chase", name: "Chase" },
        type: "depository",
        name: "Checking",
        subtype: "checking",
        currency: "USD",
        last_four: "7723",
        status: "open",
        links: { self: "https://api.teller.io/accounts/acc_oiin624iajrg2mp2ea000" }
      }
    ].to_json

    response = OpenStruct.new(code: 200, body: accounts_json)
    Provider::Teller.expects(:get).with(
      "https://api.teller.io/accounts",
      has_entries(basic_auth: { username: @access_token, password: "" })
    ).returns(response)

    result = @provider.get_accounts(@access_token)

    assert_equal 1, result.size
    assert_equal "acc_oiin624iajrg2mp2ea000", result.first[:id]
    assert_equal "Chase", result.first[:institution][:name]
  end

  test "get_accounts raises TellerError on 401" do
    response = OpenStruct.new(code: 401, body: '{"error":"invalid access token"}')
    Provider::Teller.stubs(:get).returns(response)

    error = assert_raises(Provider::Teller::TellerError) do
      @provider.get_accounts(@access_token)
    end
    assert_equal :unauthorized, error.error_type
  end
end
