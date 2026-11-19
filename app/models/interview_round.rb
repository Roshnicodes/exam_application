# One stage of a candidate's selection process.
#
#  * kind "interview"  — a panel round, e.g. "Technical interview" or "HR interview"
#                        (or a single combined "Panel interview"): own schedule, panel,
#                        video room and scorecards.
#  * kind "assessment" — a practical / live task (Excel, Tally, Word, data entry, coding…).
#                        HR uploads the task, the candidate works on it under the same
#                        proctoring as the test and uploads the solved file back.
class InterviewRound < ApplicationRecord
  STATUSES = { "scheduled" => "Scheduled", "open" => "Live now", "completed" => "Completed", "cancelled" => "Cancelled" }.freeze
  KINDS = { "interview" => "Interview round", "assessment" => "Practical assessment" }.freeze
  DEFAULT_DURATION = 45

  belongs_to :invitation
  belongs_to :assessment, optional: true
  has_many :interview_round_panelists, dependent: :destroy
  has_many :assigned_panelists, through: :interview_round_panelists, source: :employee
  has_many :interview_feedbacks, -> { order(:created_at) }, dependent: :destroy
  has_many :call_messages, -> { chronological }, dependent: :destroy
  has_many :code_pads, dependent: :destroy

  has_many_attached :task_files  # HR's files for this candidate's task (used instead of the assessment's own)
  has_many_attached :submissions # what the candidate uploads back

  normalizes :name, with: ->(v) { v.to_s.squish }

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :kind, inclusion: { in: KINDS.keys }
  normalizes :meeting_link, with: ->(v) { v.to_s.strip.presence } # a pasted link may carry spaces
  validates :meeting_link, format: { with: %r{\Ahttps?://\S+\z}i, message: "must start with http:// or https://" }, allow_blank: true
  validates :duration_minutes, numericality: { only_integer: true, in: 1..600 }, allow_nil: true
  validates :max_warnings, numericality: { only_integer: true, in: 0..50 }, allow_nil: true
  validates :max_marks, numericality: { only_integer: true, in: 1..10_000 }, allow_nil: true
  validates :marks, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :marks_within_total
  validate :assessment_has_a_task
  validate :assessment_owned_by_user

  scope :ordered, -> { order(:position, :id) }
  scope :upcoming, -> { where(status: %w[scheduled open]) }
  scope :assessments, -> { where(kind: "assessment") }
  scope :interviews, -> { where(kind: "interview") }

  after_commit :broadcast_changes

  STATUSES.each_key { |s| define_method("#{s}?") { status == s } }

  def status_label
    return "Submitted — to be marked" if assessment? && submitted? && marks.nil?
    return "Working now" if assessment? && working?

    STATUSES[status]
  end

  def kind_label
    KINDS[kind]
  end

  def assessment?
    kind == "assessment"
  end

  def interview?
    !assessment?
  end

  def done?
    completed? || cancelled?
  end

  # Opening a round closes any other live round of the same candidate (one room at a time).
  # A practical assessment the candidate is working on right now is left alone.
  def open!
    transaction do
      invitation.interview_rounds.where(status: "open").where.not(id: id).each do |other|
        next if other.assessment? && other.working?

        other.update_columns(status: "completed", ended_at: Time.current, updated_at: Time.current)
      end
      update!(status: "open", started_at: started_at || Time.current)
    end
  end

  def complete!
    update!(status: "completed", ended_at: Time.current)
  end

  # What this round's panel scores (defaults to every interview parameter of the vacancy).
  def score_parameters
    return Array(parameters).compact_blank if assessment?

    Array(parameters).compact_blank.presence || invitation.interview_parameters
  end

  def panelists
    assigned_panelists.any? ? assigned_panelists : invitation.panelists
  end

  def panelist_ids=(ids)
    self.assigned_panelists = invitation.user.employees.where(id: Array(ids).compact_blank)
  end

  def average
    vals = interview_feedbacks.filter_map(&:average)
    vals.any? ? (vals.sum / vals.size).round(1) : nil
  end

  def recommendation_counts
    interview_feedbacks.group_by(&:recommendation).transform_values(&:size)
  end

  # Proctoring warnings logged while this round was running.
  def warnings_count
    invitation.proctor_events.for_round(self).violations.count
  end

  # ---- Practical assessment ------------------------------------------------

  def task_label
    assessment? ? (assessment&.kind_label || "Practical task") : "Interview"
  end

  def task_icon
    assessment? ? (assessment&.kind_icon || "sheet") : "video"
  end

  def duration
    (duration_minutes.presence || assessment&.duration_minutes || DEFAULT_DURATION).to_i
  end

  def total_marks
    (max_marks.presence || assessment&.max_marks || 100).to_i
  end

  def pass_percentage
    assessment&.pass_percentage || 50
  end

  # Warnings allowed before the assessment is submitted automatically (0 = only alert HR).
  def warning_limit
    return max_warnings.to_i if max_warnings.present?
    return assessment.max_warnings.to_i if assessment

    invitation.max_warnings.to_i
  end

  def task_instructions
    instructions.presence || assessment&.instructions
  end

  # The files the candidate gets: this round's own uploads, else the saved assessment's.
  def task_attachments
    return task_files.attachments.to_a if task_files.attached?

    assessment&.files&.attachments&.to_a || []
  end

  def allow_download?
    assessment ? assessment.allow_download? : true
  end

  def require_upload?
    assessment ? assessment.require_upload? : true
  end

  def allow_notes?
    assessment ? assessment.allow_notes? : true
  end

  # The candidate has to work in another app (Excel / Tally): tab / app-switch and full-screen
  # warnings are paused, everything else (camera, phone, second person, screen recording) stays on.
  def allow_app_switch?
    return allow_app_switch unless allow_app_switch.nil?

    assessment ? assessment.allow_app_switch? : false
  end

  def accepts?(filename)
    return true unless assessment

    assessment.accepts?(filename)
  end

  def accept_attribute
    assessment ? assessment.accept_attribute : Assessment::DEFAULT_EXTENSIONS
  end

  def submitted?
    submitted_at.present?
  end

  # ---- Answer sheet marked from the practical test's answer key ----
  def answer_items
    assessment&.answer_items.presence || []
  end

  def answer_sheet?
    answer_items.any?
  end

  def key_total
    answer_items.sum { |i| i["marks"].to_f }
  end

  # Autosave of the candidate's answers ({ "q1" => "B", "q21a" => "Output CGST 95,000 …" })
  def record_answers(given)
    ids = answer_items.map { |i| i["id"] }
    clean = given.to_h.transform_keys(&:to_s).slice(*ids).transform_values { |v| v.to_s.strip.first(6000) }
    update!(answers: answers.merge(clean))
  end

  def answered_count
    answer_items.count { |i| answers[i["id"]].present? }
  end

  # Marks every question from the key; questions HR has already marked keep HR's marks.
  def auto_mark!
    return unless answer_sheet?

    marks = answer_items.to_h do |item|
      result = AnswerKey.mark(item, answers[item["id"]])
      hr = item_marks[item["id"]]
      result = result.merge("marks" => hr["marks"], "by_hr" => true) if hr&.dig("by_hr")
      [ item["id"], result ]
    end
    apply_item_marks!(marks)
  end

  # HR changes the marks of some questions ({ "q16" => "1.5" }); the total follows.
  def set_item_marks!(given)
    marks = item_marks.deep_dup
    answer_items.each do |item|
      value = given.to_h[item["id"]].to_s.strip
      next if value.blank? || !value.match?(/\A\d+(\.\d+)?\z/)

      max = item["marks"].to_f
      marks[item["id"]] = (marks[item["id"]] || AnswerKey.mark(item, answers[item["id"]]))
                            .merge("marks" => [ value.to_f, max ].min, "max" => max, "by_hr" => true, "review" => false)
    end
    apply_item_marks!(marks)
  end

  # The answer sheet's score (out of the key's total), e.g. 37.5
  def sheet_score
    item_marks.values.sum { |m| m["marks"].to_f }
  end

  def to_review_count
    item_marks.values.count { |m| m["review"] && !m["by_hr"] }
  end

  # ---- Built-in spreadsheet (Excel tasks solved on the page) ----

  # The spreadsheet task file the built-in spreadsheet opens (first .xlsx / .csv / .ods of the task).
  def sheet_task_file
    task_attachments.find { |a| Spreadsheet::WORKBOOK_EXTENSIONS.include?(a.filename.extension_with_delimiter.downcase) }
  end

  def online_sheet?
    assessment.present? && assessment.online_sheet? && sheet_task_file.present?
  end

  # The task workbook as HR uploaded it (cached per file).
  def original_sheets
    file = sheet_task_file
    return [] unless file

    Rails.cache.fetch([ "task-workbook", file.blob.checksum, file.blob.id ], expires_in: 12.hours) do
      file.blob.open { |tmp| Spreadsheet.workbook(tmp.path, file.filename.extension_with_delimiter) }
    end
  end

  # What the candidate sees: their saved work, else the original task.
  def working_sheets
    sheet_data.is_a?(Hash) && sheet_data["sheets"].present? ? sheet_data["sheets"] : original_sheets
  end

  ANSWER_FILE_PREFIX = "Answer - ".freeze

  # Turns the candidate's spreadsheet into an .xlsx on their submissions (replacing the earlier one).
  def attach_sheet_answer!
    return unless sheet_data.is_a?(Hash) && sheet_data["sheets"].present?

    submissions.attachments.select { |a| a.filename.to_s.start_with?(ANSWER_FILE_PREFIX) }.each(&:purge)
    base = File.basename(sheet_task_file&.filename.to_s.presence || "#{name}.xlsx", ".*")
    submissions.attach(io: StringIO.new(Spreadsheet.answer_xlsx(sheet_data["sheets"])),
                       filename: "#{ANSWER_FILE_PREFIX}#{base} - #{invitation.candidate_name}.xlsx".tr("/\\", "-"),
                       content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  rescue StandardError => e
    Rails.logger.error("Could not build the answer workbook for round #{id}: #{e.class} #{e.message}")
  end

  # The candidate has the task open and the clock is running.
  def working?
    assessment? && work_started_at.present? && submitted_at.nil? && !cancelled?
  end

  def work_deadline
    work_started_at && work_started_at + duration.minutes
  end

  def seconds_left
    return duration * 60 unless work_deadline

    [ (work_deadline - Time.current).to_i, 0 ].max
  end

  def time_up?
    working? && seconds_left.zero?
  end

  # The candidate opened the task: the clock starts now.
  def start_work!
    return if work_started_at.present?

    update!(work_started_at: Time.current, started_at: started_at || Time.current, status: "open")
    log!("assessment_started", "#{name} - #{duration} minutes")
  end

  # Candidate finished (or the time / warning limit ended it).
  def submit_work!(reason: nil)
    return if submitted?

    attach_sheet_answer! # the built-in spreadsheet becomes an .xlsx HR can download
    begin_marking = answer_sheet?
    update!(submitted_at: Time.current, ended_at: Time.current, status: "completed", termination_reason: reason)
    case reason
    when nil then log!("assessment_submitted", "#{name} - #{submissions.size} file(s) uploaded")
    when "time_up" then log!("assessment_time_up", "#{name} - #{submissions.size} file(s) uploaded")
    else log!("assessment_ended", "#{name} - #{reason}")
    end
    mark_from_key if begin_marking
  end

  # Auto-marking never stops a submission; a problem is logged for HR to mark by hand.
  def mark_from_key
    auto_mark!
  rescue StandardError => e
    Rails.logger.error("Auto-marking failed for round #{id}: #{e.class} #{e.message}")
  end

  # HR gives the candidate another go (the earlier uploads stay on record).
  def reopen_work!
    update!(work_started_at: nil, submitted_at: nil, ended_at: nil, termination_reason: nil, status: "open", started_at: Time.current)
  end

  def apply_item_marks!(marks)
    update!(item_marks: marks)
    score = marks.values.sum { |m| m["marks"].to_f }
    scaled = key_total.positive? ? (score * total_marks / key_total).round : score.round
    note = grade_note.presence || "Marked from the answer key (written answers by their key points — please check)."
    grade!(scaled.clamp(0, total_marks), note)
  end

  def grade!(marks_value, note = nil)
    update!(marks: marks_value.presence, grade_note: note.presence,
            graded_at: marks_value.present? ? Time.current : nil)
  end

  def graded?
    marks.present?
  end

  def percentage
    return nil unless graded? && total_marks.positive?

    (marks * 100.0 / total_marks).round
  end

  def passed?
    percentage && percentage >= pass_percentage
  end

  def result_label
    return "Not marked yet" unless graded?

    passed? ? "Pass" : "Below cut-off"
  end

  # Auto-submits practical assessments whose time ran out but which were never submitted
  # (the candidate closed the page or lost the connection).
  def self.submit_overdue_work!
    assessments.where(status: "open", submitted_at: nil).where.not(work_started_at: nil).includes(:assessment, :invitation).each do |round|
      next unless round.work_deadline && round.work_deadline < 2.minutes.ago

      round.submit_work!(reason: "time_up")
    end
  end

  private
    def log!(kind, message = nil)
      invitation.proctor_events.create!(kind: kind, message: message, metadata: { round_id: id })
    end

    def marks_within_total
      return if marks.blank?

      errors.add(:marks, "cannot be more than #{total_marks}") if marks > total_marks
    end

    def assessment_owned_by_user
      return unless assessment && invitation

      errors.add(:assessment, "is invalid") if assessment.user_id != invitation.user_id
    end

    def assessment_has_a_task
      return unless assessment?
      return if assessment_id.present? || task_files.attached?

      errors.add(:base, "Pick a saved assessment or upload the task file for this round")
    end

    def broadcast_changes
      invitation.broadcast_rounds
    end
end
