class Provider::TellerAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  Provider::Factory.register("TellerAccount", self)

  def self.supported_account_types
    %w[Depository CreditCard]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_teller?

    [ {
      key: "teller",
      name: "Teller",
      description: "Connect to your US bank via Teller",
      can_connect: true,
      new_account_path: ->(accountable_type, return_to) {
        Rails.application.routes.url_helpers.new_teller_item_path(
          accountable_type: accountable_type
        )
      },
      existing_account_path: ->(account_id) {
        Rails.application.routes.url_helpers.select_existing_account_teller_items_path(
          account_id: account_id
        )
      }
    } ]
  end

  def provider_name
    "teller"
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_teller_item_path(item)
  end

  def item
    provider_account.teller_item
  end

  def can_delete_holdings?
    false
  end

  def institution_name
    item&.institution_name
  end

  def institution_domain
    nil
  end

  def institution_url
    nil
  end

  def institution_color
    nil
  end
end
