class CreateTellerAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :teller_accounts, id: :uuid do |t|
      t.references :teller_item, null: false, foreign_key: true, type: :uuid
      t.references :account, null: true, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :teller_account_id, null: false
      t.string :name
      t.string :account_type
      t.string :account_subtype
      t.string :currency
      t.string :last_four
      t.decimal :current_balance, precision: 19, scale: 4
      t.decimal :available_balance, precision: 19, scale: 4
      t.string :balance_sign_override
      t.jsonb :raw_payload

      t.timestamps
    end

    add_index :teller_accounts, [ :teller_item_id, :teller_account_id ], unique: true, name: "index_teller_accounts_on_item_and_teller_id"
    add_check_constraint :teller_accounts, "balance_sign_override IN ('credit', 'debt')", name: "teller_accounts_balance_sign_override_check"
  end
end
