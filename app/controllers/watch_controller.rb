# Read-only live view for interview panelists: they get a secret link instead of a login.
class WatchController < ApplicationController
  allow_unauthenticated_access
  layout "watch"

  def show
    @invitation = Invitation.includes(:quiz).find_by!(watch_token: params[:watch_token])
    @events = @invitation.proctor_events.timeline.limit(30)
  end

  def batch
    @batch = ExamBatch.find_by!(watch_token: params[:watch_token])
    @invitations = @batch.invitations.includes(:quiz).to_a
                         .sort_by { |i| [ { "in_progress" => 0, "otp_requested" => 1, "verified" => 2 }.fetch(i.status, 3), i.candidate_name ] }
  end

  private
    def record_not_found
      render "exams/invalid", layout: "exam", status: :not_found
    end
end
