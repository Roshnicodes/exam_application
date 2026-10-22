class InvitationsController < ApplicationController
  before_action :set_invitation, only: %i[show report edit update destroy decide language send_email]

  def index
    @invitations = filtered_invitations
    @by_position = params[:group] == "position"
  end

  # Excel of the candidates on screen (same filters / search), with results, warnings, scores, answers and chat.
  def export
    label = [ params[:status], params[:q] ].compact_blank.join("-").parameterize.presence
    send_xlsx CandidateExport.new(filtered_invitations, link: exam_link).to_xlsx, [ "candidates", label, Date.current ].compact.join("-") + ".xlsx"
  end

  # HR switches the test language (the candidate's page follows, even mid-test).
  def language
    @invitation.update!(language: params[:language] == "hi" ? "hi" : "en")
    @invitation.broadcast_language
    note = @invitation.hindi? && !@invitation.quiz.hindi_ready? ? " The paper has Hindi for #{@invitation.quiz.hindi_count}/#{@invitation.quiz.questions.size} questions — the rest stay in English." : ""
    redirect_to @invitation, notice: "Test language set to #{Invitation::LANGUAGES[@invitation.language]}.#{note}"
  end

  # Emails the test link with the candidate guide PDF attached (needs SMTP on the server).
  def send_email
    return redirect_to(@invitation, alert: "Add the candidate's email first (Edit).") if @invitation.candidate_email.blank?
    return redirect_to(@invitation, alert: "Email isn't set up on the server yet — ask IT to add the SMTP settings to .env.") unless CandidateMailer.configured?

    CandidateMailer.invitation(@invitation).deliver_later
    redirect_to @invitation, notice: "Email with the test link and candidate guide PDF sent to #{@invitation.candidate_email}."
  end

  # Excel for one candidate.
  def export_one
    invitation = Current.user.invitations.find(params[:id])
    send_xlsx CandidateExport.new(Current.user.invitations.where(id: invitation.id), link: exam_link).to_xlsx,
              "#{invitation.candidate_name.parameterize}-#{Date.current}.xlsx"
  end

  def new
    plan = Invitation::INTERVIEW_PLANS.key?(params[:plan]) ? params[:plan] : "separate"
    @invitation = Current.user.invitations.new(max_warnings: 5, interview_mode: "Online", quiz_id: params[:quiz_id], vacancy_id: params[:vacancy_id],
                                               interview_plan: plan,
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
    plan_changed = @invitation.interview_plan_changed?
    if @invitation.save
      note = plan_changed && !@invitation.replan_rounds! ? " Rounds already started, so the interview plan wasn't rebuilt — edit rounds directly." : ""
      redirect_to @invitation, notice: "Candidate details updated.#{note}"
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def report
    @questions = @invitation.quiz.questions
    @events = @invitation.proctor_events.timeline
  end

  # Final hiring decision: selected / on hold / rejected (blank clears it).
  def decide
    value = params[:decision].presence
    return redirect_to(@invitation, alert: "Unknown decision.") if value && !Invitation::DECISIONS.key?(value)

    @invitation.decide!(value, params[:decision_note])
    redirect_to @invitation, notice: value ? "Marked as #{@invitation.decision_label}." : "Decision cleared."
  end

  def destroy
    @invitation.destroy
    back = request.referer.to_s
    back = invitations_path if back.blank? || back.include?(invitation_path(@invitation))
    redirect_to back, notice: "#{@invitation.candidate_name} deleted.", status: :see_other
  end

  private
    def exam_link
      ->(invitation) { exam_url(invitation.token) }
    end

    def filtered_invitations
      scope = Current.user.invitations.includes(:quiz, :interview_rounds).recent
      if params[:status] == "submitted"
        scope = scope.completed # finished the test (incl. auto-terminated)
      elsif Invitation::STATUSES.include?(params[:status])
        scope = scope.where(status: params[:status])
      end
      scope = scope.qualified if params[:status] == "qualified"
      scope = scope.disqualified if params[:status] == "disqualified"
      if params[:q].present?
        q = "%#{Invitation.sanitize_sql_like(params[:q])}%"
        scope = scope.where("candidate_name ILIKE :q OR vacancy ILIKE :q OR candidate_email ILIKE :q", q: q)
      end
      scope
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
                                  :link_expires_at, :meeting_link, :interview_plan, :resume, :language, panelist_ids: [] ])
    end
end
