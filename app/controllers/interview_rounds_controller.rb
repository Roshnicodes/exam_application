# HR manages a candidate's interview rounds: schedule, panel, live room and scorecards.
class InterviewRoundsController < ApplicationController
  before_action :set_invitation
  before_action :set_round, except: :create

  def create
    position = @invitation.interview_rounds.maximum(:position).to_i + 1
    round = @invitation.interview_rounds.new(round_params.except(:panelist_ids, :task_files).merge(position: position))
    round.parameters = Array(round_params[:parameters]).compact_blank.presence || [ round.name ].select { |n| n.in?(@invitation.interview_parameters) }
    round.panelist_ids = round_params[:panelist_ids] if round_params.key?(:panelist_ids)
    fill_assessment_defaults(round)
    attach_task_files(round)
    if round.save
      redirect_to invitation_path(@invitation, anchor: "rounds"), notice: "#{round.assessment? ? 'Practical assessment' : 'Round'} “#{round.name}” added."
    else
      redirect_to invitation_path(@invitation, anchor: "rounds"), alert: round.errors.full_messages.to_sentence
    end
  end

  def update
    @round.assign_attributes(round_params.except(:panelist_ids, :parameters, :task_files))
    @round.parameters = Array(round_params[:parameters]).compact_blank if round_params.key?(:parameters)
    @round.panelist_ids = round_params[:panelist_ids] if round_params.key?(:panelist_ids)
    fill_assessment_defaults(@round)
    attach_task_files(@round)
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

  # HR's view of the round: video room + scorecard, or the live practical assessment.
  def room
    @feedback = @round.interview_feedbacks.find_by(user: Current.user) || InterviewFeedback.new(reviewer_name: Current.user.name)
    @events = @invitation.proctor_events.for_round(@round).timeline.limit(40) if @round.assessment?
    render :assessment_room if @round.assessment?
  end

  # Marks for a practical assessment, after checking the uploaded file.
  def grade
    return redirect_to(room_invitation_interview_round_path(@invitation, @round), alert: "Only a practical assessment is marked here.") unless @round.assessment?

    @round.grade!(params[:marks], params[:grade_note])
    @invitation.broadcast_feedback
    redirect_to room_invitation_interview_round_path(@invitation, @round),
                notice: @round.graded? ? "Marks saved: #{@round.marks}/#{@round.total_marks} (#{@round.percentage}%)." : "Marks cleared."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to room_invitation_interview_round_path(@invitation, @round), alert: e.record.errors.full_messages.to_sentence
  end

  # HR's own marks for some questions of the answer sheet (the rest stay as auto-marked).
  def mark_items
    return redirect_to(room_invitation_interview_round_path(@invitation, @round), alert: "This round has no answer key.") unless @round.answer_sheet?

    @round.set_item_marks!(params.fetch(:marks, {}).to_unsafe_h, by: Current.user.name)
    @invitation.broadcast_feedback
    redirect_to room_invitation_interview_round_path(@invitation, @round, anchor: "answer-sheet"),
                notice: "Marks saved: #{@round.marks}/#{@round.total_marks} (#{@round.percentage}%)."
  end

  # Mark again from the (corrected) answer key; HR's own marks are kept.
  def remark
    return redirect_to(room_invitation_interview_round_path(@invitation, @round), alert: "This round has no answer key.") unless @round.answer_sheet?

    @round.auto_mark!
    @invitation.broadcast_feedback
    redirect_to room_invitation_interview_round_path(@invitation, @round, anchor: "answer-sheet"),
                notice: "Marked again from the answer key: #{@round.marks}/#{@round.total_marks}."
  end

  # Another attempt at the practical (earlier uploads stay on record).
  def reopen
    @round.reopen_work!
    redirect_to room_invitation_interview_round_path(@invitation, @round),
                notice: "#{@round.name} is open again — #{@invitation.candidate_name} can start it from their link."
  end

  # Removes one of the task files uploaded for this round.
  def task_file
    @round.task_files.attachments.find { |a| a.id == params[:file_id].to_i }&.purge
    redirect_back_or_to invitation_path(@invitation, anchor: "rounds"), notice: "Task file removed."
  end

  def open
    @round.open!
    redirect_to room_invitation_interview_round_path(@invitation, @round),
                notice: "#{@round.name} is live. #{@invitation.candidate_name} can join from their exam link."
  end

  def complete
    # ending a live practical assessment also submits whatever the candidate has uploaded so far
    if @round.assessment? && @round.working?
      @round.submit_work!(reason: "Ended by HR (#{Current.user.name})")
      return redirect_to room_invitation_interview_round_path(@invitation, @round),
                         notice: "#{@round.name} ended. The candidate's files and notes are saved — give the marks below."
    end

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

    # A practical assessment round takes its time / marks / rules from the saved assessment
    # unless HR typed something for this candidate.
    def fill_assessment_defaults(round)
      return unless round.assessment?

      round.assessment ||= Current.user.assessments.find_by(id: round_params[:assessment_id])
      return unless round.assessment

      round.name = round.assessment.title if round.name.blank?
      # time / marks / warning limit left blank follow the practical test (and its later changes)
    end

    # Task files uploaded for this one candidate (they replace the saved assessment's files).
    def attach_task_files(round)
      list = Array(params.dig(:interview_round, :task_files)).select { |f| f.respond_to?(:original_filename) }
      round.task_files.attach(list) if list.any?
    end

    def round_params
      params.expect(interview_round: [ :name, :scheduled_at, :meeting_link, :notes, :status, :kind, :assessment_id,
                                       :duration_minutes, :max_marks, :max_warnings, :instructions, :allow_app_switch,
                                       parameters: [], panelist_ids: [] ])
    end

    def feedback_params
      params.expect(interview_feedback: [ :recommendation, :comments, scores: {} ])
    end
end
