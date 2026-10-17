class InvitationsController < ApplicationController
  before_action :set_invitation, only: %i[show report edit update destroy interview open_interview close_interview feedback]

  def index
    @invitations = Current.user.invitations.includes(:quiz).recent
    @invitations = @invitations.where(status: params[:status]) if Invitation::STATUSES.include?(params[:status])
    if params[:q].present?
      q = "%#{Invitation.sanitize_sql_like(params[:q])}%"
      @invitations = @invitations.where("candidate_name ILIKE :q OR vacancy ILIKE :q OR candidate_email ILIKE :q", q: q)
    end
  end

  def new
    @invitation = Current.user.invitations.new(max_warnings: 5, interview_mode: "Online", quiz_id: params[:quiz_id], vacancy_id: params[:vacancy_id],
                                               interview_date: 1.day.from_now.change(hour: 11),
                                               link_expires_at: 3.days.from_now.end_of_day)
    load_form_options
    redirect_to new_quiz_path, alert: "Create a question paper first, then invite candidates." if @quizzes.empty?
  end

  def create
    @invitation = Current.user.invitations.new(invitation_params.except(:panelist_ids))
    @invitation.panelist_ids = invitation_params[:panelist_ids]
    @invitation.quiz = Current.user.quizzes.find_by(id: invitation_params[:quiz_id])
    @invitation.opening = Current.user.vacancies.find_by(id: invitation_params[:vacancy_id])
    if @invitation.save
      redirect_to @invitation, notice: "Invitation created. Share the exam link with #{@invitation.candidate_name}."
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @events = @invitation.proctor_events.timeline.with_attached_snapshot
    @snapshots = @invitation.proctor_events.with_snapshots.with_attached_snapshot.order(created_at: :desc).limit(24)
  end

  def edit
    load_form_options
  end

  def update
    attrs = invitation_params.except(:quiz_id, :vacancy_id, :panelist_ids)
    @invitation.assign_attributes(attrs)
    @invitation.panelist_ids = invitation_params[:panelist_ids] if invitation_params.key?(:panelist_ids)
    @invitation.opening = Current.user.vacancies.find_by(id: invitation_params[:vacancy_id]) if invitation_params.key?(:vacancy_id)
    if @invitation.started_at.nil? && invitation_params[:quiz_id].present?
      @invitation.quiz = Current.user.quizzes.find_by(id: invitation_params[:quiz_id]) || @invitation.quiz
    end
    if @invitation.save
      redirect_to @invitation, notice: "Candidate details updated."
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def report
    @questions = @invitation.quiz.questions
    @events = @invitation.proctor_events.timeline
  end

  # Two-way video interview room (HR view).
  def interview
    @feedback = @invitation.interview_feedbacks.find_by(user: Current.user) || InterviewFeedback.new(reviewer_name: Current.user.name)
  end

  def open_interview
    @invitation.open_interview!
    redirect_to interview_invitation_path(@invitation), notice: "Interview room is open. #{@invitation.candidate_name} can join from their exam link."
  end

  def close_interview
    @invitation.close_interview!
    redirect_to invitation_path(@invitation), notice: "Interview ended."
  end

  def feedback
    @feedback = @invitation.interview_feedbacks.find_or_initialize_by(user: Current.user)
    @feedback.assign_attributes(feedback_params.merge(reviewer_name: Current.user.name))
    saved = @feedback.save
    respond_to do |format|
      # replace just the scorecard, so an ongoing video call isn't interrupted
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("feedback_form_#{@invitation.id}", partial: "interview_feedbacks/form",
                 locals: { invitation: @invitation, feedback: @feedback, url: feedback_invitation_path(@invitation), saved: saved })
      end
      format.html { redirect_back_or_to invitation_path(@invitation), saved ? { notice: "Your feedback is saved." } : { alert: @feedback.errors.full_messages.to_sentence } }
    end
  end

  def destroy
    @invitation.destroy
    back = request.referer.to_s
    back = invitations_path if back.blank? || back.include?(invitation_path(@invitation))
    redirect_to back, notice: "#{@invitation.candidate_name} deleted.", status: :see_other
  end

  private
    def feedback_params
      params.expect(interview_feedback: [ :recommendation, :comments, scores: {} ])
    end

    def load_form_options
      @quizzes = Current.user.quizzes.order(:title)
      @vacancies = Current.user.vacancies.open.includes(:department).order(:title)
      @employees = Current.user.employees.ordered
      @panelist_ids = Array(params.dig(:invitation, :panelist_ids)).compact_blank.presence&.map(&:to_i) ||
                      (@invitation.assigned_panelists.ids if @invitation&.persisted?).presence ||
                      (@invitation&.opening&.panelists&.ids || [])
    end

    def set_invitation
      @invitation = Current.user.invitations.find(params[:id])
    end

    def invitation_params
      params.expect(invitation: [ :candidate_name, :candidate_email, :candidate_phone, :vacancy, :department, :experience,
                                  :interview_date, :interview_mode, :location, :notes, :quiz_id, :vacancy_id, :max_warnings,
                                  :link_expires_at, :meeting_link, panelist_ids: [] ])
    end
end
