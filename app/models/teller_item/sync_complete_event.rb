class TellerItem::SyncCompleteEvent
  attr_reader :teller_item

  def initialize(teller_item)
    @teller_item = teller_item
  end

  def broadcast
    teller_item.accounts.each do |account|
      account.broadcast_sync_complete
    end

    teller_item.family.broadcast_sync_complete
  end
end
