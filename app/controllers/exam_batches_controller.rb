class ExamBatchesController < ApplicationController
  before_action :set_batch, only: %i[show edit update destroy monitor links]

  def index
    @batches = Current.user.exam_batches.includes(:quiz, :opening, :invitations).order(created_at: :desc)
  end

  def new
    @batch = Current.user.exam_batches.new(max_warnings: 5, interview_mode: "Online", quiz_id: params[:quiz_id], vacancy_id: params[:vacancy_id],
                                           interview_date: 1.day.from_now.change(hour: 11), link_expires_at: 3.days.from_now.end_of_day,
                                           name: "Batch #{Date.current.strftime('%d %b %Y')}")
    @rows = Array.new(3) { {} }
    load_form_options
    redirect_to new_quiz_path, alert: "Create a question paper first." if @quizzes.empty?
  end

  def create
    @batch = Current.user.exam_batches.new(batch_params.except(:quiz_id, :vacancy_id, :panelist_ids))
    @batch.panelist_ids = batch_params[:panelist_ids]
    @batch.quiz = Current.user.quizzes.find_by(id: batch_params[:quiz_id])
    @batch.opening = Current.user.vacancies.find_by(id: batch_params[:vacancy_id])
    @rows, @row_errors = ExamBatch.collect_candidates(params[:candidates]&.map { |r| r.permit(:candidate_name, :candidate_email, :candidate_phone, :experience) },
                                                     params.dig(:exam_batch, :candidates_file))
    @row_errors << "Add at least one candidate (type them in or upload an Excel file)" if @rows.empty? && @row_errors.empty?

    if @row_errors.empty? && @batch.valid?
      invitations, @row_errors = @batch.build_invitations(@rows)
      if @row_errors.empty?
        ExamBatch.transaction { @batch.save! }
        return redirect_to exam_batch_path(@batch), notice: "#{invitations.size} exam links created. Share them with the candidates."
      end
    end

    @rows = @rows.presence || Array.new(3) { {} }
    load_form_options
    render :new, status: :unprocessable_entity
  end

  def edit
    @rows = [ {} ]
    load_form_options
  end

  def update
    @batch.assign_attributes(batch_params.except(:quiz_id, :vacancy_id, :panelist_ids))
    @batch.panelist_ids = batch_params[:panelist_ids] if batch_params.key?(:panelist_ids)
    @batch.opening = Current.user.vacancies.find_by(id: batch_params[:vacancy_id]) if batch_params.key?(:vacancy_id)
    if @batch.invitations.where.not(started_at: nil).none? && batch_params[:quiz_id].present?
      @batch.quiz = Current.user.quizzes.find_by(id: batch_params[:quiz_id]) || @batch.quiz
    end
    @rows, @row_errors = ExamBatch.collect_candidates(params[:candidates]&.map { |r| r.permit(:candidate_name, :candidate_email, :candidate_phone, :experience) },
                                                     params.dig(:exam_batch, :candidates_file))

    if @row_errors.empty? && @batch.valid?
      added, @row_errors = @batch.build_invitations(@rows)
      if @row_errors.empty?
        ExamBatch.transaction do
          @batch.save!
          @batch.invitations.where(started_at: nil).update_all(quiz_id: @batch.quiz_id)
          @batch.sync_pending_invitations!
        end
        note = added.any? ? " #{added.size} new candidate(s) added." : ""
        return redirect_to exam_batch_path(@batch), notice: "Batch updated.#{note}"
      end
    end

    @rows = @rows.presence || [ {} ]
    load_form_options
    render :edit, status: :unprocessable_entity
  end

  def show
    @invitations = @batch.invitations.includes(:quiz)
  end

  def monitor
    @invitations = @batch.invitations.includes(:quiz)
    render "monitor/index"
  end

  def links
    send_xlsx @batch.links_xlsx(->(token) { exam_url(token) }), "#{@batch.name.parameterize}-exam-links.xlsx"
  end

  def template
    send_xlsx Spreadsheet.build("Candidates", ExamBatch::CANDIDATE_HEADERS,
                                [ [ "Rahul Verma", "rahul@example.com", "9876543210", "1-3 years" ], [ "Neha Gupta", "neha@example.com", "9123456780", "Fresher" ] ],
                                widths: [ 26, 30, 16, 14 ], notes: [ "One candidate per row. Name is required.", "Mobile (10 digits) is optional — if given, only that number can request the OTP." ]),
              "batch_candidates_template.xlsx"
  end

  def destroy
    @batch.destroy
    redirect_to exam_batches_path, notice: "Batch deleted.", status: :see_other
  end

  private
    def set_batch
      @batch = Current.user.exam_batches.find(params[:id])
    end

    def load_form_options
      @quizzes = Current.user.quizzes.order(:title)
      @vacancies = Current.user.vacancies.open.includes(:department).order(:title)
      @employees = Current.user.employees.ordered
      @panelist_ids = Array(params.dig(:exam_batch, :panelist_ids)).compact_blank.presence&.map(&:to_i) ||
                      (@batch.panelists.ids if @batch&.persisted?).presence ||
                      (@batch&.opening&.panelists&.ids || [])
    end

    def batch_params
      params.expect(exam_batch: [ :name, :quiz_id, :vacancy_id, :vacancy_title, :department, :interview_date, :interview_mode,
                                 :location, :notes, :max_warnings, :link_expires_at, :meeting_link, panelist_ids: [] ])
    end
end
