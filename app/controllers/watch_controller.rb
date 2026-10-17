# Read-only live view for interview panelists: they get a secret link instead of a login.
class WatchController < ApplicationController
  allow_unauthenticated_access
  layout "watch"

  def show
    @invitation = Invitation.includes(:quiz).find_by!(watch_token: params[:watch_token])
    @events = @invitation.proctor_events.timeline.limit(30)
  end

  def interview
    @invitation = Invitation.includes(:quiz).find_by!(watch_token: params[:watch_token])
    @panelists = @invitation.panelists.to_a
  end

  # Panelists say who they are (they share one link), then save their scorecard.
  def feedback
    @invitation = Invitation.find_by!(watch_token: params[:watch_token])
    panelists = @invitation.panelists.to_a
    panelist = panelists.find { |p| p.id == params[:employee_id].to_i }
    feedback = panelist ? @invitation.interview_feedbacks.find_or_initialize_by(employee: panelist) : InterviewFeedback.new(invitation: @invitation)
    feedback.assign_attributes(params.expect(interview_feedback: [ :recommendation, :comments, scores: {} ]).merge(reviewer_name: panelist&.name.to_s))
    feedback.errors.add(:base, "Choose your name from the panel list") unless panelist
    saved = panelist && feedback.save

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("feedback_form_#{@invitation.id}", partial: "interview_feedbacks/form",
                 locals: { invitation: @invitation, feedback: feedback, url: watch_feedback_path(params[:watch_token]), panelists: panelists, saved: saved })
      end
      format.html { redirect_back_or_to watch_path(params[:watch_token]), saved ? { notice: "Your feedback is saved." } : { alert: feedback.errors.full_messages.to_sentence } }
    end
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
