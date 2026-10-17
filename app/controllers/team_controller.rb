# HR colleagues who can log in. Each account sees its own candidates, papers and masters.
class TeamController < ApplicationController
  def index
    @users = User.order(:name)
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[name email_address password]))
    if @user.save
      redirect_to team_path, notice: "#{@user.name} can now sign in with #{@user.email_address}."
    else
      @users = User.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    user = User.find(params[:id])
    return redirect_to(team_path, alert: "You can't remove your own account.") if user == Current.user

    user.destroy
    redirect_to team_path, notice: "#{user.name} removed.", status: :see_other
  end
end
