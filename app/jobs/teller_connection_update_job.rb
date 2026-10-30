class TellerConnectionUpdateJob < ApplicationJob
  queue_as :default

  def perform(teller_item)
    TellerItem::Importer.new(teller_item).import
  rescue Provider::Teller::TellerError => e
    Rails.logger.error "TellerConnectionUpdateJob failed for item #{teller_item.id}: #{e.message}"
    teller_item.update!(status: "requires_update") if e.error_type == :unauthorized
    raise
  end
end
