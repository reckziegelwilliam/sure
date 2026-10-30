class CreateTellerItems < ActiveRecord::Migration[8.1]
  def change
    create_table :teller_items, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :owner, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :access_token, null: false
      t.string :enrollment_id, null: false
      t.string :institution_name
      t.string :status, null: false, default: "good"
      t.boolean :scheduled_for_deletion, null: false, default: false
      t.jsonb :raw_payload

      t.timestamps
    end

    add_index :teller_items, [ :family_id, :enrollment_id ], unique: true
  end
end
