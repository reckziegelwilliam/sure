# frozen_string_literal: true

class TellerItem::Syncer
  include SyncStats::Collector

  attr_reader :teller_item

  def initialize(teller_item)
    @teller_item = teller_item
  end

  def perform_sync(sync)
    sync.update!(status_text: "Importing accounts from Teller...") if sync.respond_to?(:status_text)
    mark_import_started(sync)

    TellerItem::Importer.new(teller_item).import

    # Clear any previously-flagged credential error once a sync succeeds.
    teller_item.update!(status: :good) if teller_item.requires_update?

    collect_setup_stats(sync, provider_accounts: teller_item.teller_accounts.to_a)

    linked_accounts = teller_item.teller_accounts.joins(:account_provider).joins(:account).merge(Account.visible)

    sync.update!(status_text: "Processing accounts...") if sync.respond_to?(:status_text)
    teller_item.process_accounts

    if linked_accounts.any?
      sync.update!(status_text: "Calculating balances...") if sync.respond_to?(:status_text)
      teller_item.schedule_account_syncs(
        parent_sync: sync,
        window_start_date: sync.window_start_date,
        window_end_date: sync.window_end_date
      )

      account_ids = linked_accounts.filter_map { |ta| ta.current_account&.id }
      collect_transaction_stats(sync, account_ids: account_ids, source: "teller")
    end

    collect_health_stats(sync, errors: nil)
  rescue Provider::Teller::TellerError => e
    teller_item.update!(status: :requires_update) if e.error_type == :unauthorized

    DebugLogEntry.capture(
      category: "provider_sync_error",
      level: "error",
      message: "Teller sync failed: #{e.message}",
      source: self.class.name,
      provider_key: "teller",
      family: teller_item.family,
      metadata: { teller_item_id: teller_item.id, error_type: e.error_type }
    )

    collect_health_stats(sync, errors: [ { message: e.message, category: "sync_error" } ])
    raise
  rescue => e
    collect_health_stats(sync, errors: [ { message: e.message, category: "sync_error" } ])
    raise
  end

  def perform_post_sync
    # no-op
  end
end
