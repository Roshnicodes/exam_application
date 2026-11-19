# Read-only live view for interview panelists: they get a secret link instead of a login.
class WatchController < ApplicationController
  allow_unauthenticated_access
  layout "watch"

  def show
    @invitation = Invitation.includes(:quiz).find_by!(watch_token: params[:watch_token])
    @events = @invitation.proctor_events.timeline.limit(30)
  end

  # Panelist's view of one round: video room + their scorecard, or the practical assessment.
  def round
    @invitation = Invitation.includes(:quiz).find_by!(watch_token: params[:watch_token])
    @round = @invitation.interview_rounds.find(params[:round_id])
    @panelists = @round.panelists.to_a
    return unless @round.assessment?

    @events = @invitation.proctor_events.for_round(@round).timeline.limit(40)
    render :assessment_round
  end

  # Panelists say who they are (they share one link), then save their scorecard for the round.
  def feedback
    @invitation = Invitation.find_by!(watch_token: params[:watch_token])
    round = @invitation.interview_rounds.find(params[:round_id])
    panelists = round.panelists.to_a
    panelist = panelists.find { |p| p.id == params[:employee_id].to_i }
    typed = params[:reviewer_name].to_s.squish.first(60)
    feedback = if panelist
      round.interview_feedbacks.find_or_initialize_by(employee: panelist)
    elsif typed.present? # guest panelist, or no panel set for the round: one scorecard per name
      round.interview_feedbacks.find_or_initialize_by(employee_id: nil, user_id: nil, reviewer_name: typed)
    else
      round.interview_feedbacks.new
    end
    feedback.assign_attributes(params.expect(interview_feedback: [ :recommendation, :comments, scores: {} ])
                                     .merge(invitation: @invitation, reviewer_name: panelist&.name || typed))
    who = panelist || typed.present?
    saved = who && feedback.save
    feedback.errors.add(:base, "Choose your name from the panel list or type it") unless who

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("feedback_form_#{round.id}", partial: "interview_feedbacks/form",
                 locals: { round: round, feedback: feedback, url: watch_feedback_path(params[:watch_token], round), panelists: panelists, saved: saved })
      end
      format.html { redirect_back_or_to watch_path(params[:watch_token]), saved ? { notice: "Your feedback is saved." } : { alert: feedback.errors.full_messages.to_sentence } }
    end
  end

  # A panelist (department / thematic head) gives their own marks on the answer sheet; the
  # application's marks stay visible next to theirs.
  def marks
    @invitation = Invitation.find_by!(watch_token: params[:watch_token])
    round = @invitation.interview_rounds.find(params[:round_id])
    back = watch_round_path(params[:watch_token], round, anchor: "answer-sheet")
    return redirect_to(back, alert: "This round has no answer key.") unless round.answer_sheet? && round.submitted?

    panelist = round.panelists.to_a.find { |p| p.id == params[:employee_id].to_i }
    name = panelist&.name || params[:reviewer_name].to_s.squish.first(60)
    return redirect_to(back, alert: "Choose your name (or type it) before saving marks.") if name.blank?

    round.set_item_marks!(params.fetch(:marks, {}).to_unsafe_h, by: name)
    @invitation.broadcast_feedback
    redirect_to back, notice: "Marks saved by #{name}: #{round.marks}/#{round.total_marks}."
  end

  def batch
    @batch = ExamBatch.find_by!(watch_token: params[:watch_token])
    Invitation.submit_overdue!
    @invitations = @batch.invitations.includes(:quiz).to_a
                         .sort_by { |i| [ { "in_progress" => 0, "otp_requested" => 1, "verified" => 2 }.fetch(i.status, 3), i.candidate_name ] }
  end

  private
    def record_not_found
      render "exams/invalid", layout: "exam", status: :not_found
    end
end
