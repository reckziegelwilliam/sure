class TellerItemsController < ApplicationController
  before_action :set_teller_item, only: [ :show, :edit, :update, :destroy, :sync, :setup_accounts, :complete_account_setup ]
  before_action :require_admin!, only: [ :new, :create, :select_existing_account, :link_existing_account, :edit, :update, :destroy, :sync, :setup_accounts, :complete_account_setup ]

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

  # Show unlinked Teller accounts for setup. The initial sync already
  # populated teller_accounts from Teller's API, so this does not make a live
  # API call the way Mercury's setup_accounts does.
  def setup_accounts
    @teller_accounts = @teller_item.unlinked_teller_accounts.order(:name)

    supported_types = Provider::TellerAdapter.supported_account_types

    account_type_keys = {
      "depository" => "Depository",
      "credit_card" => "CreditCard"
    }

    all_account_type_options = account_type_keys.filter_map do |key, type|
      next unless supported_types.include?(type)
      [ t(".account_types.#{key}"), type ]
    end

    @account_type_options = [ [ t(".account_types.skip"), "skip" ] ] + all_account_type_options

    translate_subtypes = ->(type_key, subtypes_hash) {
      subtypes_hash.map { |k, v| [ t(".subtypes.#{type_key}.#{k}", default: v[:long] || k.humanize), k ] }
    }

    all_subtype_options = {
      "Depository" => {
        label: t(".subtype_labels.depository"),
        options: translate_subtypes.call("depository", Depository::SUBTYPES)
      },
      "CreditCard" => {
        label: t(".subtype_labels.credit_card"),
        options: [],
        message: t(".subtype_messages.credit_card")
      }
    }

    @subtype_options = all_subtype_options.slice(*supported_types)
  end

  def complete_account_setup
    account_types = params[:account_types] || {}
    account_subtypes = params[:account_subtypes] || {}

    valid_types = Provider::TellerAdapter.supported_account_types

    created_accounts = []
    skipped_count = 0

    begin
      ActiveRecord::Base.transaction do
        account_types.each do |teller_account_id, selected_type|
          if selected_type == "skip" || selected_type.blank?
            skipped_count += 1
            next
          end

          unless valid_types.include?(selected_type)
            Rails.logger.warn("Invalid account type '#{selected_type}' submitted for Teller account #{teller_account_id}")
            next
          end

          teller_account = @teller_item.teller_accounts.find_by(id: teller_account_id)
          unless teller_account
            Rails.logger.warn("Teller account #{teller_account_id} not found for item #{@teller_item.id}")
            next
          end

          if teller_account.account_provider.present?
            Rails.logger.info("Teller account #{teller_account_id} already linked, skipping")
            next
          end

          selected_subtype = account_subtypes[teller_account_id]
          selected_subtype = "credit_card" if selected_type == "CreditCard" && selected_subtype.blank?

          account = Account.create_and_sync(
            {
              family: Current.family,
              name: teller_account.name,
              balance: teller_account.current_balance || 0,
              currency: teller_account.currency.presence || "USD",
              accountable_type: selected_type,
              accountable_attributes: selected_subtype.present? ? { subtype: selected_subtype } : {}
            },
            skip_initial_sync: true
          )

          AccountProvider.create!(
            account: account,
            provider: teller_account
          )

          created_accounts << account
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      Rails.logger.error("Teller account setup failed: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      flash[:alert] = t(".creation_failed", error: e.message)
      redirect_to accounts_path, status: :see_other
      return
    rescue StandardError => e
      Rails.logger.error("Teller account setup failed unexpectedly: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      flash[:alert] = t(".creation_failed", error: "An unexpected error occurred")
      redirect_to accounts_path, status: :see_other
      return
    end

    @teller_item.sync_later if created_accounts.any? && !@teller_item.syncing?

    if created_accounts.any?
      flash[:notice] = t(".success", count: created_accounts.count)
    elsif skipped_count > 0
      flash[:notice] = t(".all_skipped")
    else
      flash[:notice] = t(".no_accounts")
    end

    redirect_to accounts_path, status: :see_other
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
