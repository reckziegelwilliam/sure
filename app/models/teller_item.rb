class TellerItem < ApplicationRecord
  include Syncable, DestroyableLater

  belongs_to :family
  belongs_to :owner, class_name: "User", optional: true
  has_many :teller_accounts, dependent: :destroy

  encrypts :access_token, deterministic: true

  validates :name, :access_token, :enrollment_id, presence: true

  def institution_color
    nil
  end

  def institution_url
    nil
  end

  def sync_later
    TellerConnectionUpdateJob.perform_later(self)
  end
end
