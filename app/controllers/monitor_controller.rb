# Live grid of every candidate who is currently verifying or taking an exam.
class MonitorController < ApplicationController
  def index
    @invitations = Current.user.invitations.where(status: %w[otp_requested verified in_progress])
                          .or(Current.user.invitations.where(submitted_at: 2.hours.ago..))
                          .includes(:quiz).order(:candidate_name)
  end
end
