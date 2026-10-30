class RemoveAccountFromTellerAccounts < ActiveRecord::Migration[8.1]
  def change
    remove_reference :teller_accounts, :account, foreign_key: { on_delete: :nullify }, type: :uuid, index: true
  end
end
