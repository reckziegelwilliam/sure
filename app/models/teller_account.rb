class TellerAccount < ApplicationRecord
  belongs_to :teller_item
  belongs_to :account, optional: true

  validates :teller_account_id, presence: true

  def current_account
    account
  end
end
