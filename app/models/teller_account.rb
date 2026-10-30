class TellerAccount < ApplicationRecord
  belongs_to :teller_item

  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :teller_account_id, presence: true
  validates :balance_sign_override, inclusion: { in: %w[credit debt] }, allow_nil: true

  def current_account
    account
  end
end
