class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"
  before_action :ensure_signup_allowed

  # Open sign-up only creates the very first account (or when ALLOW_SIGNUP=true);
  # after that, colleagues are added from the Team page.
  def self.signup_open?
    !User.exists? || ENV["ALLOW_SIGNUP"] == "true"
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[name email_address password password_confirmation]))
    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome aboard, #{@user.first_name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def ensure_signup_allowed
      redirect_to new_session_path, alert: "Sign-up is closed. Ask your HR admin to add you from the Team page." unless self.class.signup_open?
    end
end
