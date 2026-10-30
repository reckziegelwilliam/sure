module Family::TellerConnectable
  extend ActiveSupport::Concern

  included do
    has_many :teller_items, dependent: :destroy
  end

  def can_connect_teller?
    Rails.configuration.x.teller.application_id.present?
  end

  # Teller Connect is a client-side-only widget: by the time this is called,
  # the browser already holds a valid access_token from Teller directly.
  # There is no server-side "claim" step here, unlike
  # Family::SimplefinConnectable#create_simplefin_item! or
  # Family::PlaidConnectable#create_plaid_item!.
  def create_teller_item!(access_token:, enrollment_id:, institution_name: nil, item_name: nil)
    teller_item = teller_items.create!(
      name: item_name || institution_name || "Teller Connection",
      access_token: access_token,
      enrollment_id: enrollment_id,
      institution_name: institution_name,
      owner: Current.user
    )
    teller_item.sync_later
    teller_item
  end
end
