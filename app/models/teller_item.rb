class TellerItem < ApplicationRecord
  include Syncable, Unlinking, DestroyableLater, ProviderItemOwnable

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  belongs_to :family
  has_many :teller_accounts, dependent: :destroy
  has_many :accounts, through: :teller_accounts

  # Deliberately NOT gated behind Encryptable#encryption_ready? (as most
  # provider items are): that check is `explicitly_configured?`, which misses
  # the self-hosted default where encryption keys are auto-derived from
  # SECRET_KEY_BASE (config/initializers/active_record_encryption.rb) rather
  # than set via env/credentials. Gating on it would silently store this
  # access_token -- a live bank credential -- in plaintext on the standard
  # self-hosted deployment. Encrypting unconditionally fails loudly instead
  # if encryption is genuinely unavailable, which is the right failure mode
  # for a credential this sensitive.
  encrypts :access_token, deterministic: true

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

  def has_completed_initial_setup?
    accounts.any?
  end

  # Linked accounts (have AccountProvider association)
  def linked_teller_accounts
    teller_accounts.joins(:account_provider)
  end

  # Unlinked accounts (no AccountProvider association)
  def unlinked_teller_accounts
    teller_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
  end

  def linked_accounts_count
    teller_accounts.joins(:account_provider).count
  end

  def unlinked_accounts_count
    teller_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).count
  end

  def total_accounts_count
    teller_accounts.count
  end

  def sync_status_summary
    total = total_accounts_count
    linked = linked_accounts_count
    unlinked = unlinked_accounts_count

    if total == 0
      I18n.t("teller_items.sync_status.no_accounts")
    elsif unlinked == 0
      I18n.t("teller_items.sync_status.synced", count: linked)
    else
      I18n.t("teller_items.sync_status.synced_with_setup", linked: linked, unlinked: unlinked)
    end
  end
end
