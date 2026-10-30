require "test_helper"

class TellerItemTest < ActiveSupport::TestCase
  test "encrypts access_token when encryption is configured" do
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

  test "linked_teller_accounts and unlinked_teller_accounts partition on account_provider" do
    item = teller_items(:chase_connection)
    unlinked = item.teller_accounts.create!(teller_account_id: "acc_unlinked", name: "Unlinked")
    linked = item.teller_accounts.create!(teller_account_id: "acc_linked", name: "Linked")
    account = Account.create!(
      family: item.family, name: "Linked Account", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "checking")
    )
    AccountProvider.create!(account: account, provider: linked)

    assert_includes item.linked_teller_accounts, linked
    assert_not_includes item.linked_teller_accounts, unlinked
    assert_includes item.unlinked_teller_accounts, unlinked
    assert_not_includes item.unlinked_teller_accounts, linked
  end

  test "linked_accounts_count, unlinked_accounts_count and total_accounts_count" do
    item = teller_items(:chase_connection)
    item.teller_accounts.destroy_all
    unlinked = item.teller_accounts.create!(teller_account_id: "acc_unlinked", name: "Unlinked")
    linked = item.teller_accounts.create!(teller_account_id: "acc_linked", name: "Linked")
    account = Account.create!(
      family: item.family, name: "Linked Account", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "checking")
    )
    AccountProvider.create!(account: account, provider: linked)

    assert_equal 1, item.linked_accounts_count
    assert_equal 1, item.unlinked_accounts_count
    assert_equal 2, item.total_accounts_count
  end

  test "has_completed_initial_setup? reflects whether any account is linked" do
    item = teller_items(:chase_connection)
    item.teller_accounts.destroy_all
    assert_not item.has_completed_initial_setup?

    unlinked = item.teller_accounts.create!(teller_account_id: "acc_unlinked", name: "Unlinked")
    assert_not item.has_completed_initial_setup?

    account = Account.create!(
      family: item.family, name: "Linked Account", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "checking")
    )
    AccountProvider.create!(account: account, provider: unlinked)

    assert item.reload.has_completed_initial_setup?
  end

  test "sync_status_summary reflects no_accounts, synced, and synced_with_setup states" do
    item = teller_items(:chase_connection)
    item.teller_accounts.destroy_all
    assert_equal I18n.t("teller_items.sync_status.no_accounts"), item.sync_status_summary

    unlinked = item.teller_accounts.create!(teller_account_id: "acc_unlinked", name: "Unlinked")
    assert_equal I18n.t("teller_items.sync_status.synced_with_setup", linked: 0, unlinked: 1), item.sync_status_summary

    account = Account.create!(
      family: item.family, name: "Linked Account", currency: "USD", balance: 0,
      accountable_type: "Depository", accountable: Depository.create!(subtype: "checking")
    )
    AccountProvider.create!(account: account, provider: unlinked)

    assert_equal I18n.t("teller_items.sync_status.synced", count: 1), item.reload.sync_status_summary
  end

  test "is ProviderItemOwnable and assigns a default owner" do
    item = TellerItem.create!(
      family: families(:dylan_family), name: "No Owner Conn",
      access_token: "token_no_owner", enrollment_id: "enr_no_owner"
    )

    assert item.owner.present?
    assert_respond_to item, :owned_by?
  end
end
