class TellerItemsController < ApplicationController
  before_action :set_teller_item, only: [ :show, :edit, :update, :destroy, :sync ]
  before_action :require_admin!, only: [ :create, :update, :destroy, :sync, :link_existing_account ]

  def index
    @teller_items = Current.family.teller_items.where(scheduled_for_deletion: false)
  end

  def show
  end

  def new
    @accountable_type = params[:accountable_type]
  end

  def create
    teller_item = Current.family.create_teller_item!(
      access_token: teller_params[:access_token],
      enrollment_id: teller_params[:enrollment_id],
      institution_name: teller_params[:institution_name]
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "provider_panel_teller",
          partial: "settings/providers/teller_panel",
          locals: { teller_items: Current.family.teller_items }
        )
      end
      format.html { redirect_to teller_items_path, status: :see_other }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.record)
  end

  def edit
  end

  def update
    if @teller_item.update(name: teller_params[:name])
      TellerConnectionUpdateJob.perform_later(@teller_item)
      redirect_to teller_items_path, status: :see_other
    else
      render_error(@teller_item)
    end
  end

  def destroy
    @teller_item.update!(scheduled_for_deletion: true)
    redirect_to teller_items_path, status: :see_other
  end

  def sync
    TellerConnectionUpdateJob.perform_later(@teller_item)
    redirect_to teller_items_path, status: :see_other
  end

  def select_existing_account
    @account_id = params[:account_id]
  end

  def link_existing_account
    account = Current.family.accounts.find(params[:account_id])
    teller_account = TellerAccount.find(params[:teller_account_id])

    AccountProvider.create!(account: account, provider: teller_account)

    redirect_to teller_items_path, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.record)
  end

  private
    def set_teller_item
      @teller_item = Current.family.teller_items.find(params[:id])
    end

    def teller_params
      params.require(:teller_item).permit(:access_token, :enrollment_id, :institution_name, :name)
    end

    def render_error(record)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "provider_panel_teller",
            partial: "settings/providers/teller_panel",
            locals: { teller_items: Current.family.teller_items, error: record.errors.full_messages.to_sentence }
          ), status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = record.errors.full_messages.to_sentence
          redirect_to teller_items_path
        end
      end
    end
end
