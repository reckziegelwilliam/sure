class TellerItemsController < ApplicationController
  before_action :set_teller_item, only: [ :show, :edit, :update, :destroy, :sync ]
  before_action :require_admin!, only: [ :new, :create, :select_existing_account, :link_existing_account, :edit, :update, :destroy, :sync ]

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
          "teller-providers-panel",
          partial: "settings/providers/teller_panel",
          locals: { teller_items: Current.family.teller_items }
        )
      end
      format.html { redirect_to accounts_path, status: :see_other }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.record)
  end

  def edit
  end

  def update
    if @teller_item.update(name: teller_params[:name])
      @teller_item.sync_later
      redirect_to accounts_path, status: :see_other
    else
      render_error(@teller_item)
    end
  end

  def destroy
    begin
      @teller_item.unlink_all!(dry_run: false)
    rescue => e
      Rails.logger.warn("Teller unlink during destroy failed: #{e.class} - #{e.message}")
    end
    @teller_item.destroy_later
    redirect_to accounts_path, status: :see_other
  end

  def sync
    @teller_item.sync_later unless @teller_item.syncing?
    redirect_to accounts_path, status: :see_other
  end

  def select_existing_account
    @account = Current.family.accounts.find(params[:account_id])

    @available_teller_accounts = TellerAccount
      .joins(:teller_item)
      .where(teller_items: { family_id: Current.family.id })
      .left_joins(:account_provider)
      .where(account_providers: { id: nil })
      .order(:name)

    render :select_existing_account, layout: false
  end

  def link_existing_account
    account = Current.family.accounts.find(params[:account_id])
    teller_account = TellerAccount.joins(:teller_item)
      .where(teller_items: { family_id: Current.family.id })
      .find(params[:teller_account_id])

    AccountProvider.create!(account: account, provider: teller_account)

    redirect_to accounts_path, notice: t("teller_items.link_existing_account.success"), status: :see_other
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
            "teller-providers-panel",
            partial: "settings/providers/teller_panel",
            locals: { teller_items: Current.family.teller_items, error: record.errors.full_messages.to_sentence }
          ), status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = record.errors.full_messages.to_sentence
          redirect_to accounts_path
        end
      end
    end
end
