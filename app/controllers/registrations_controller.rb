class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"

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
end
