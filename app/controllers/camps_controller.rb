class CampsController < ApplicationController
  before_action :authenticate_user!, except: [:show, :index]
  before_action :load_camp!, except: [:index, :new, :create]
  before_action :enforce_delete_permission!, only: [:destroy, :archive]
  before_action :enforce_guide!, only: %i(tag)
  before_action :load_lang_detector, only: %i(show index)

  def index
    filter = params[:filterrific] || { sorted_by: 'updated_at_desc' }
    filter[:active] = true
    filter[:not_hidden] = true

    if (!current_user.nil? && (current_user.admin? || current_user.guide?))
      filter[:hidden] = true
      filter[:not_hidden] = false
    else
      filter[:sorted_by] = 'random'
    end

    @filterrific = initialize_filterrific(
      Camp,
      filter
    ) or return
    @camps = @filterrific.find.page(params[:page])

    respond_to do |format|
      format.html
      format.js
    end
  end

  def new
    @camp = Camp.new
  end

  def edit
    @just_view = params[:just_view]
  end

  def create
    # Create camp without people then add them
    @camp = Camp.new(camp_params)
    @camp.creator = current_user

    if create_camp
      flash[:notice] = t('created_new_dream')
      redirect_to edit_camp_path(id: @camp.id)
    else
      flash.now[:notice] = "#{t:errors_str}: #{@camp.errors.full_messages.uniq.join(', ')}"
      render :new
    end
  end

  # Toggle granting

  def toggle_granting
    @camp.toggle!(:grantingtoggle)
    redirect_to camp_path(@camp)
  end

  # Handle the grant updates in their own controller action
  def update_grants
    # Reduce the number of grants assigned to the current user by the number
    # of grants given away. Increase the number of grants assigned to the
    # camp by the same number of grants.

    # Decrement user grants. Check first if granting more than needed.
    granted = params['grants'].to_i
    if(granted <= 0)
      flash[:alert] = "#{t:cant_send_less_then_one}"
      redirect_to camp_path(@camp) and return
    end

    if @camp.maxbudget.nil?
      flash[:alert] = "#{t:dream_need_to_have_max_budget}"
      redirect_to camp_path(@camp) and return
    end

    if @camp.grants_received + granted > @camp.maxbudget
        granted = @camp.maxbudget - @camp.grants_received
    end

    if current_user.grants < granted
      flash[:alert] = "#{t:security_more_grants, granted: granted, current_user_grants: current_user.grants}"
      redirect_to camp_path(@camp) and return
    end

    ActiveRecord::Base.transaction do
      current_user.grants -= granted

      # Increase camp grants.
      @camp.grants.new({:user_id => current_user.id, :amount => granted})      

      if @camp.grants_received + granted >= @camp.minbudget
        @camp.minfunded = true
      else
        @camp.minfunded = false
      end
      
      if @camp.grants_received + granted >= @camp.maxbudget
        @camp.fullyfunded = true
      else
        @camp.fullyfunded = false
      end
        
      unless current_user.save
        flash[:notice] = "#{t:errors_str}: #{current_user.errors.full_messages.uniq.join(', ')}"
        redirect_to camp_path(@camp) and return
      end
      
      unless @camp.save
        flash[:notice] = "#{t:errors_str}: #{@camp.errors.full_messages.uniq.join(', ')}"
        redirect_to camp_path(@camp) and return
      end
    end

    redirect_to camp_path(@camp)
    flash[:notice] = "#{t:thanks_for_sending, grants: granted}"
  end

  def update
    if (@camp.creator != current_user) and !current_user.admin and !current_user.guide
      flash[:alert] = "#{t:security_cant_edit_dreams_you_dont_own}"
      redirect_to camp_path(@camp) and return
    end

    if @camp.update_attributes camp_params
      if params[:done] == '1'
        redirect_to camp_path(@camp)
      else
        respond_to do |format|
          format.html { redirect_to edit_camp_path(id: @camp.id) }
          format.json { respond_with_bip(@camp) }
        end
      end
    else
      respond_to do |format|
        flash.now[:alert] = "#{t:errors_str}: #{@camp.errors.full_messages.uniq.join(', ')}"
        format.html { render :action => "edit" }
        format.json { respond_with_bip(@camp) }
      end
    end
  end

  def tag
    @camp.update_attributes(tag_list: params.require(:camp).require(:tag_list))

    flash[:notice] = "#{t:tags_saved}"
    redirect_to camp_path(@camp)
  end

  def destroy
    @camp.destroy!

    redirect_to camps_path
  end

  # Display a camp and its users
  def show
    @users = @camp.users.select(:email)

    # Added this to move some code out of the view.
    if current_user
      @user_grant_limit = current_user.grants
    end
  end

  # Allow a user to join a particular camp.
  def join
    @user = current_user

    #
    # Only add a user to the list of associated members if the user isn't
    # in the list. We should add a uniqueness validation to this.
    #

    if !@user
      flash[:notice] = "#{t:join_dream}"
    elsif @camp.users.where(id: @user.id).exists?
      flash[:notice] = "#{t:join_already_sent}"
    else
      flash[:notice] = "#{t:join_dream}"
      @camp.users << @user
    end
    redirect_to @camp
  end

  def archive
    @camp.update!(active: false)
    redirect_to camps_path
  end

  private

  def camp_params
    params.require(:camp).permit!
  end

  def load_camp!
    @camp = Camp.find_by(id: params[:id])
    if @camp.nil?
      flash[:alert] = t('dream_not_found')
      redirect_to camps_path
    end
  end

  def enforce_guide!
    if (!current_user.admin) && (!current_user.guide)
      flash[:alert] = "#{t:security_cant_tag_dreams_you_dont_own}"
      redirect_to camp_path(@camp)
    end
  end

  def enforce_delete_permission!
    if (@camp.creator != current_user) and (!current_user.admin)
      flash[:alert] = "#{t:security_cant_delete_dreams_you_dont_own}"
      redirect_to camp_path(@camp)
    end
  end

  def create_camp
    Camp.transaction do
      @camp.save!
      if Rails.application.config.x.firestarter_settings['google_drive_integration'] and ENV['GOOGLE_APPS_SCRIPT'].present?
        response = NewDreamAppsScript::createNewDreamFolder(@camp.creator.email, @camp.id, @camp.name)
        @camp.google_drive_folder_path = response['id']
        @camp.google_drive_budget_file_path = response['budget']
        @camp.save!
      end
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def load_lang_detector
    @detector = StringDirection::Detector.new(:dominant)
  end
end

