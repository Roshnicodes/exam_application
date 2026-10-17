# HR manages a candidate's interview rounds: schedule, panel, live room and scorecards.
class InterviewRoundsController < ApplicationController
  before_action :set_invitation
  before_action :set_round, except: :create

  def create
    position = @invitation.interview_rounds.maximum(:position).to_i + 1
    round = @invitation.interview_rounds.new(round_params.except(:panelist_ids).merge(position: position))
    round.parameters = Array(round_params[:parameters]).compact_blank.presence || [ round.name ].select { |n| n.in?(@invitation.interview_parameters) }
    round.panelist_ids = round_params[:panelist_ids] if round_params.key?(:panelist_ids)
    if round.save
      redirect_to invitation_path(@invitation, anchor: "rounds"), notice: "Round \\"# {round.name}\\" added."
    else
      redirect_to invitation_path(@invitation, anchor: "rounds"), alert: round.errors.full_messages.to_sentence
    end
  end

  def update
    @round.assign_attributes(round_params.except(:panelist_ids, :parameters))
    @round.parameters = Array(round_params[:parameters]).compact_blank if round_params.key?(:parameters)
    @round.panelist_ids = round_params[:panelist_ids] if round_params.key?(:panelist_ids)
    if @round.save
      redirect_to invitation_path(@invitation, anchor: "rounds"), notice: "#{@round.name} updated."
    else
      redirect_to invitation_path(@invitation, anchor: "rounds"), alert: @round.errors.full_messages.to_sentence
    end
  end

  def destroy
    @round.destroy
    redirect_to invitation_path(@invitation, anchor: "rounds"), notice: "Round removed.", status: :see_other
  end

  # HR's view of the round: video room + scorecard.
  def room
    @feedback = @round.interview_feedbacks.find_by(user: Current.user) || InterviewFeedback.new(reviewer_name: Current.user.name)
  end

  def open
    @round.open!
    redirect_to room_invitation_interview_round_path(@invitation, @round),
                notice: "#{@round.name} is live. #{@invitation.candidate_name} can join from their exam link."
  end

  def complete
    @round.complete!
    redirect_to invitation_path(@invitation, anchor: "rounds"), notice: "#{@round.name} marked as completed."
  end

  def feedback
    feedback = @round.interview_feedbacks.find_or_initialize_by(user: Current.user)
    feedback.assign_attributes(feedback_params.merge(invitation: @invitation, reviewer_name: Current.user.name))
    saved = feedback.save
    respond_to do |format|
      # replace just the scorecard, so an ongoing video call isn't interrupted
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("feedback_form_#{@round.id}", partial: "interview_feedbacks/form",
                 locals: { round: @round, feedback: feedback, url: feedback_invitation_interview_round_path(@invitation, @round), saved: saved })
      end
      format.html { redirect_back_or_to invitation_path(@invitation), saved ? { notice: "Feedback saved." } : { alert: feedback.errors.full_messages.to_sentence } }
    end
  end

  private
    def set_invitation
      @invitation = Current.user.invitations.find(params[:invitation_id])
    end

    def set_round
      @round = @invitation.interview_rounds.find(params[:id])
    end

    def round_params
      params.expect(interview_round: [ :name, :scheduled_at, :meeting_link, :notes, :status, parameters: [], panelist_ids: [] ])
    end

    def feedback_params
      params.expect(interview_feedback: [ :recommendation, :comments, scores: {} ])
    end
end
