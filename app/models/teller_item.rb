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

  # Accepts the same keywords as Syncable#sync_later (Family::Syncer calls
  # every syncable this way via reflection) even though Teller's polling
  # importer always does a full fetch and ignores them.
  def sync_later(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    TellerConnectionUpdateJob.perform_later(self)
  end
end
