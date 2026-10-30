class TellerItem < ApplicationRecord
  include Syncable, Encryptable, Unlinking, DestroyableLater

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  belongs_to :family
  belongs_to :owner, class_name: "User", optional: true
  has_many :teller_accounts, dependent: :destroy
  has_many :accounts, through: :teller_accounts

  if encryption_ready?
    encrypts :access_token, deterministic: true
  end

  validates :name, :access_token, :enrollment_id, presence: true

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def institution_color
    nil
  end

  def institution_url
    nil
  end

  def process_accounts
    return [] if teller_accounts.empty?

    teller_accounts.joins(:account).merge(Account.visible).map do |teller_account|
      result = TellerAccount::Processor.new(teller_account).process
      { teller_account_id: teller_account.id, success: true, result: result }
    rescue => e
      Rails.logger.error "TellerItem #{id} - Failed to process account #{teller_account.id}: #{e.class} - #{e.message}"
      { teller_account_id: teller_account.id, success: false, error: e.message }
    end
  end

  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    return [] if accounts.empty?

    accounts.visible.map do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
      { account_id: account.id, success: true }
    rescue => e
      Rails.logger.error "TellerItem #{id} - Failed to schedule sync for account #{account.id}: #{e.class} - #{e.message}"
      { account_id: account.id, success: false, error: e.message }
    end
  end
end
