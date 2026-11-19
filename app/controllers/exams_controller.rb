# Public, token-addressed flow for candidates: phone + OTP verification, proctored exam, submission.
class ExamsController < ApplicationController
  allow_unauthenticated_access
  layout "exam"

  rate_limit to: 6, within: 5.minutes, only: :request_otp,
             with: -> { redirect_to exam_path(params[:token]), alert: "Too many OTP requests. Please wait a few minutes." }
  rate_limit to: 15, within: 5.minutes, only: :verify_otp,
             with: -> { redirect_to exam_path(params[:token]), alert: "Too many attempts. Please wait a few minutes." }

  # the practical assessment runs on its own pages (it can come before, after or instead of the test)
  ASSESSMENT_ACTIONS = %i[assessment assessment_start assessment_notes assessment_files assessment_remove_file assessment_submit assessment_task_preview assessment_sheet assessment_sheet_save assessment_answers].freeze

  before_action :set_invitation
  before_action :redirect_if_finished, except: %i[finished events recordings interview] + ASSESSMENT_ACTIONS
  before_action :require_verified, only: %i[instructions start take answer rough language submit interview] + ASSESSMENT_ACTIONS
  before_action :auto_submit_if_time_up, only: %i[take answer submit]
  before_action :set_assessment_round, only: ASSESSMENT_ACTIONS

  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render :invalid, status: :not_found }
      format.any { head :not_found }
    end
  end

  def show
    return redirect_to exam_interview_path(@invitation.token) if @invitation.interview_open? && candidate_verified?
    return redirect_to exam_take_path(@invitation.token) if @invitation.in_progress? && candidate_verified?
    return unless candidate_verified?
    return redirect_to exam_assessment_path(@invitation.token) if @invitation.live_assessment || @invitation.practical_only?

    redirect_to exam_instructions_path(@invitation.token) if @invitation.verified?
  end

  def request_otp
    return redirect_to exam_path(@invitation.token), alert: "This exam link has expired. Please contact HR." if @invitation.link_expired?

    @invitation.request_otp!(params[:phone])
    redirect_to exam_path(@invitation.token, step: "otp"), notice: "OTP has been sent to HR. Please ask your HR for the 6 digit code."
  rescue ArgumentError => e
    redirect_to exam_path(@invitation.token), alert: e.message
  end

  def verify_otp
    @invitation.verify_otp!(params[:otp])
    session[session_key] = @invitation.entered_phone
    return redirect_to exam_interview_path(@invitation.token), notice: "Verified — joining the interview." if @invitation.interview_open?
    if @invitation.live_assessment || @invitation.practical_only?
      return redirect_to exam_assessment_path(@invitation.token), notice: "Verified successfully!"
    end

    redirect_to exam_instructions_path(@invitation.token), notice: "Verified successfully!"
  rescue ArgumentError => e
    redirect_to exam_path(@invitation.token, step: "otp"), alert: e.message
  end

  def instructions
    return redirect_to exam_assessment_path(@invitation.token) unless @invitation.test_required?

    redirect_to exam_take_path(@invitation.token) if @invitation.in_progress?
  end

  def start
    return redirect_to exam_assessment_path(@invitation.token) unless @invitation.test_required?

    @invitation.start!
    redirect_to exam_take_path(@invitation.token)
  end

  def take
    return redirect_to exam_assessment_path(@invitation.token) unless @invitation.test_required?
    return redirect_to exam_instructions_path(@invitation.token) unless @invitation.in_progress?

    @questions = @invitation.quiz.questions
  end

  def answer
    @invitation.save_answer!(params[:question_id], params[:option])
    render json: { ok: true, answered: @invitation.answered_count, seconds_left: @invitation.seconds_left }
  end

  # Digital rough sheet: typed notes and the hand-written page (PNG), saved while the test runs.
  # The candidate picks English or Hindi for the paper (before or during the test)
  def language
    lang = params[:language].to_s
    return head :unprocessable_entity unless Invitation::LANGUAGES.key?(lang)

    @invitation.update!(language: lang) unless @invitation.language == lang
    head :no_content
  end

  def rough
    return head :unprocessable_entity unless @invitation.in_progress?

    @invitation.update!(rough_notes: params[:notes].to_s.first(20_000)) if params.key?(:notes)
    sheet = params[:sheet]
    if sheet.respond_to?(:read) && sheet.size.between?(1, 5.megabytes)
      @invitation.rough_sheet.attach(io: sheet, filename: "rough-sheet.png", content_type: "image/png")
    end
    head :no_content
  end

  def events
    return head :forbidden unless candidate_verified?

    kind = params[:kind].to_s
    return head :unprocessable_entity unless ProctorEvent::KINDS.key?(kind)

    # a practical assessment / interview round the candidate is in right now: logged against
    # that round (the test itself is already over, or there is no test at all)
    round = @invitation.interview_rounds.find_by(id: params[:round_id]) if params[:round_id].present?
    round ||= @invitation.live_assessment || @invitation.current_round unless @invitation.in_progress?
    return render json: record_round_event(round, kind) if round && !@invitation.in_progress?

    if @invitation.finished?
      return render json: { status: @invitation.status, terminated: true }
    end

    @invitation.record_event!(kind, message: params[:message].to_s.first(250).presence, snapshot: params[:snapshot])
    @invitation.reload
    render json: {
      status: @invitation.status,
      warnings: @invitation.warnings_count,
      max_warnings: @invitation.max_warnings,
      terminated: @invitation.finished?,
      redirect: (exam_finished_path(@invitation.token) if @invitation.finished?)
    }
  end

  def recordings
    return head :forbidden unless candidate_verified?
    return head :unprocessable_entity unless params[:segment].respond_to?(:content_type)

    round = @invitation.interview_rounds.find_by(id: params[:round_id]) if params[:round_id].present?
    round ||= @invitation.current_round if @invitation.finished?
    prefix = round ? "#{round.name.parameterize}-" : ""
    prefix += "screen-" if params[:kind] == "screen"
    @invitation.recordings.attach(io: params[:segment].tempfile, content_type: params[:segment].content_type,
                                  filename: "#{prefix}segment-#{params[:index].to_i.to_s.rjust(3, "0")}-#{Time.current.to_i}#{File.extname(params[:segment].original_filename.to_s).presence || ".webm"}")
    head :created
  end

  def submit
    @invitation.submit!(answer_params)
    redirect_to exam_finished_path(@invitation.token)
  end

  def finished
    redirect_to exam_path(@invitation.token) unless @invitation.finished?
  end

  # Two-way video interview with the panel: joins whichever round HR has made live.
  def interview
    @round = @invitation.current_round
    redirect_to exam_finished_path(@invitation.token), alert: "No interview round is live right now." unless @round
  end

  # ---- Practical assessment (Excel / Tally / Word / data entry / coding …) -----
  # The candidate works on HR's uploaded task under the same proctoring as the test:
  # camera, screen share, full screen, warnings, recording — with its own clock.

  def assessment
    return render :assessment_waiting unless @round
    return render :assessment_done if @round.submitted?
    return render :assessment_waiting unless @round.open?
    return render :assessment_intro if @round.work_started_at.nil?

    if @round.time_up?
      @round.submit_work!(reason: "time_up")
      return render :assessment_done
    end
    render :assessment
  end

  # Candidate finished the camera / screen check and opened the task: the clock starts now.
  def assessment_start
    return redirect_to exam_assessment_path(@invitation.token), alert: "This assessment is not open right now." unless @round&.open? && !@round.submitted?

    # tests saved before questions were read from the paper: read it now, so each question shows its text
    @round.assessment.read_paper! if @round.answer_sheet? && @round.answer_items.none? { |i| i.key?("question") }
    @round.start_work!
    redirect_to exam_assessment_path(@invitation.token)
  end

  # Autosave of the typed answer / working notes.
  def assessment_notes
    return head :unprocessable_entity unless @round&.working?

    @round.update!(candidate_notes: params[:notes].to_s.first(50_000))
    render json: { ok: true, seconds_left: @round.seconds_left }
  end

  # The solved file(s), uploaded as the candidate works (so nothing is lost if the page closes).
  def assessment_files
    return render(json: { ok: false, error: "This assessment is closed." }, status: :unprocessable_entity) unless @round&.working?

    errors = attach_submissions(params[:files])
    @round.reload
    render json: { ok: errors.empty?, error: errors.to_sentence.presence, files: submission_json, count: @round.submissions.size }
  end

  def assessment_remove_file
    return head :unprocessable_entity unless @round&.working?

    file = @round.submissions.attachments.find { |a| a.id == params[:file_id].to_i }
    if file
      name = file.filename.to_s
      file.purge
      log_round_event("file_removed", "#{name} removed by the candidate")
    end
    @round.reload
    render json: { ok: true, files: submission_json, count: @round.submissions.size }
  end

  # A spreadsheet task file shown as a table inside the assessment page, so opening it
  # is not a new tab (no tab-switch warning). PDFs / images / text open inline in the page.
  def assessment_task_preview
    return head :not_found unless @round&.working?

    file = @round.task_attachments.find { |a| a.id == params[:file_id].to_i }
    return head :not_found unless file

    if file.filename.extension.to_s.downcase == "docx" # a Word question paper, shown as text + tables
      lines = file.blob.open do |tmp|
        QuestionPaperParser.new(ActionDispatch::Http::UploadedFile.new(tempfile: tmp, filename: file.filename.to_s)).lines
      end
      return render partial: "exams/task_doc", locals: { lines: lines }
    end

    sheets = file.blob.open { |tmp| Spreadsheet.preview(tmp.path, file.filename.extension_with_delimiter) }
    render partial: "exams/task_sheet", locals: { sheets: sheets }
  rescue Spreadsheet::Error, QuestionPaperParser::Error => e
    render plain: e.message, status: :unprocessable_entity
  end

  # Autosave of the answer sheet (answers to the questions of the practical's answer key).
  def assessment_answers
    return head :unprocessable_entity unless @round&.working? && @round.answer_sheet?

    @round.record_answers(params.fetch(:answers, {}).to_unsafe_h)
    render json: { ok: true, answered: @round.answered_count, total: @round.answer_items.size, seconds_left: @round.seconds_left }
  end

  # The built-in spreadsheet: the candidate's saved workbook, else the task as HR uploaded it.
  def assessment_sheet
    return head :not_found unless @round&.working? && @round.online_sheet?

    render json: { sheets: @round.working_sheets, saved_at: @round.sheet_saved_at, seconds_left: @round.seconds_left }
  rescue Spreadsheet::Error, QuestionPaperParser::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Autosave of the built-in spreadsheet (cells as typed + the values the candidate saw).
  def assessment_sheet_save
    return head :unprocessable_entity unless @round&.working? && @round.online_sheet?
    return head :payload_too_large if request.content_length.to_i > 4.megabytes

    sheets = Array(params.to_unsafe_h["sheets"]).first(20).filter_map do |sheet|
      next unless sheet.is_a?(Hash)

      grid = ->(rows) { Array(rows).first(Spreadsheet::MAX_SHEET_ROWS).map { |row| Array(row).first(Spreadsheet::MAX_SHEET_COLS).map { |v| v.to_s.first(4000) } } }
      { "name" => sheet["name"].to_s.first(60), "cells" => grid.(sheet["cells"]), "values" => grid.(sheet["values"]),
        "styles" => Spreadsheet.clean_styles(sheet["styles"]), "widths" => Spreadsheet.clean_widths(sheet["widths"]) }
    end
    return head :unprocessable_entity if sheets.empty?

    @round.update!(sheet_data: { "sheets" => sheets }, sheet_saved_at: Time.current)
    render json: { ok: true, saved_at: @round.sheet_saved_at, seconds_left: @round.seconds_left }
  end

  def assessment_submit
    return redirect_to exam_assessment_path(@invitation.token) unless @round
    return redirect_to exam_assessment_path(@invitation.token) if @round.submitted?

    @round.update!(candidate_notes: params[:notes].to_s.first(50_000)) if params.key?(:notes)
    errors = attach_submissions(params[:files])
    @round.reload
    if errors.any?
      return redirect_to exam_assessment_path(@invitation.token), alert: errors.to_sentence
    end
    @round.record_answers(params[:answers].to_unsafe_h) if params[:answers].respond_to?(:to_unsafe_h) && @round.answer_sheet?
    if @round.require_upload? && !@round.online_sheet? && !@round.answer_sheet? && !@round.submissions.attached? && @round.candidate_notes.blank?
      return redirect_to exam_assessment_path(@invitation.token), alert: "Please upload your solved file (or type your answer) before submitting."
    end

    @round.submit_work!
    redirect_to exam_assessment_path(@invitation.token)
  end

  private
    # the submitted answers: only this paper's question ids ({ "12" => "2", … })
    def answer_params
      params.fetch(:answers, {}).permit(*@invitation.quiz.questions.pluck(:id).map(&:to_s)).to_h
    end

    def set_assessment_round
      rounds = @invitation.interview_rounds.to_a.select(&:assessment?)
      @rounds = rounds
      @round = rounds.find(&:working?) || rounds.find { |r| r.open? && !r.submitted? } ||
               rounds.reject(&:cancelled?).max_by { |r| [ r.submitted_at.to_i, r.position ] }
    end

    # Saves the uploaded files on the round. Returns the list of problems (type / size / count).
    def attach_submissions(uploads)
      files = Array(uploads).select { |f| f.respond_to?(:original_filename) }
      errors = []
      files.each do |file|
        name = file.original_filename.to_s
        if @round.submissions.size >= Assessment::MAX_FILES
          errors << "Only #{Assessment::MAX_FILES} files can be uploaded — remove one first"
          break
        elsif file.size > Assessment::MAX_FILE_SIZE
          errors << "“#{name}” is larger than #{Assessment::MAX_FILE_SIZE / 1.megabyte} MB"
        elsif !@round.accepts?(name)
          errors << "“#{name}” — this file type is not allowed here"
        else
          @round.submissions.attach(io: file.tempfile, filename: name, content_type: file.content_type)
          log_round_event("file_uploaded", "#{name} (#{(file.size / 1024.0).round} KB)")
        end
      end
      errors
    end

    def submission_json
      @round.submissions.attachments.map do |a|
        { id: a.id, name: a.filename.to_s, size: a.byte_size, at: a.created_at.strftime("%-I:%M %p") }
      end
    end

    def log_round_event(kind, message)
      @invitation.proctor_events.create!(kind: kind, message: "[#{@round.name}] #{message}", metadata: { round_id: @round.id })
    end

    # Proctoring during a live round (practical assessment or interview): logged with the round
    # and shown to the panel. In an assessment the warning limit submits that assessment;
    # an interview is never ended automatically.
    def record_round_event(round, kind)
      message = params[:message].to_s.first(250).presence
      event = @invitation.proctor_events.create!(kind: kind, message: [ "[#{round.name}]", message ].compact.join(" "),
                                                 snapshot: params[:snapshot], metadata: { round_id: round.id })
      if event.violation?
        ActionCable.server.broadcast("interview_round:#{round.id}", {
          type: "proctor-alert", title: event.label, message: message, severity: event.severity,
          snapshot_url: (rails_blob_path(event.snapshot, only_path: true) if event.snapshot.attached?)
        })
        @invitation.broadcast_rounds # live warning count on the HR page
      end
      warnings = @invitation.proctor_events.for_round(round).violations.count
      limit = round.assessment? ? round.warning_limit.to_i : 0
      if round.assessment? && round.working? && limit.positive? && warnings >= limit
        round.submit_work!(reason: "Warning limit reached (#{warnings}/#{limit})")
      end
      { status: round.assessment? ? "assessment" : "interview", warnings: warnings, max_warnings: limit,
        terminated: round.assessment? && round.reload.submitted?,
        redirect: (exam_assessment_path(@invitation.token) if round.assessment? && round.submitted?) }
    end

    def set_invitation
      @invitation = Invitation.includes(:quiz, :user).find_by!(token: params[:token])
    end

    def session_key
      "exam_#{@invitation.token}"
    end

    def candidate_verified?
      session[session_key].present? && session[session_key] == @invitation.entered_phone
    end
    helper_method :candidate_verified?

    def require_verified
      redirect_to exam_path(@invitation.token), alert: "Please verify your mobile number first." unless candidate_verified?
    end

    def redirect_if_finished
      return unless @invitation.finished?
      # a candidate on a new device may still need the OTP to join an open interview / assessment
      return if (@invitation.interview_open? || @invitation.live_assessment) && action_name.in?(%w[show request_otp verify_otp])

      redirect_to exam_finished_path(@invitation.token)
    end

    def auto_submit_if_time_up
      return unless @invitation.time_up?

      @invitation.submit!(answer_params, reason: "time_up")
      respond_to do |format|
        format.html { redirect_to exam_finished_path(@invitation.token) }
        format.json { render json: { terminated: true, redirect: exam_finished_path(@invitation.token) } }
      end
    end
end
