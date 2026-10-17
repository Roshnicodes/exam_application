class Invitation < ApplicationRecord
  STATUSES = %w[pending otp_requested verified in_progress submitted terminated].freeze
  INTERVIEW_MODES = [ "Online", "In-person", "Telephonic" ].freeze
  INTERVIEW_PLANS = {
    "separate" => [ "Separate rounds", "Test, then each interview stage (e.g. Technical, HR) as its own round — own date, panel and room" ],
    "combined" => [ "One combined interview", "Test, then a single panel interview that scores all stages together" ],
    "none" => [ "Test only", "No interview rounds (you can still add one later)" ]
  }.freeze
  DECISIONS = { "selected" => "Selected", "on_hold" => "On hold", "rejected" => "Rejected" }.freeze
  OTP_TTL = 10.minutes
  MAX_OTP_ATTEMPTS = 5

  belongs_to :user
  belongs_to :quiz
  belongs_to :exam_batch, optional: true
  belongs_to :opening, class_name: "Vacancy", foreign_key: :vacancy_id, optional: true, inverse_of: :invitations
  has_many :proctor_events, dependent: :destroy
  has_many :call_messages, -> { chronological }, dependent: :destroy
  has_many_attached :recordings

  has_secure_token :token, length: 24
  has_secure_token :watch_token, length: 24 # read-only live view link for panelists

  has_many :interview_rounds, -> { ordered }, dependent: :destroy, inverse_of: :invitation
  has_many :interview_feedbacks, -> { order(:created_at) }, dependent: :destroy
  has_one_attached :resume
  has_many :invitation_panelists, dependent: :destroy
  has_many :assigned_panelists, through: :invitation_panelists, source: :employee

  normalizes :candidate_email, with: ->(e) { e.strip.downcase }
  normalizes :candidate_phone, :entered_phone, with: ->(p) { p.to_s.gsub(/\D/, "").last(10) }

  before_validation :copy_opening_details

  validates :candidate_name, :vacancy, presence: true
  validates :candidate_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :candidate_phone, length: { is: 10 }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :max_warnings, numericality: { only_integer: true, in: 0..50 }
  validates :interview_plan, inclusion: { in: INTERVIEW_PLANS.keys }
  validates :decision, inclusion: { in: DECISIONS.keys }, allow_nil: true
  validate :resume_is_a_document
  validates :meeting_link, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
  scope :live, -> { where(status: "in_progress") }
  scope :completed, -> { where(status: %w[submitted terminated]) }

  after_create :build_interview_rounds
  after_update_commit :broadcast_live_state

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def finished?
    submitted? || terminated?
  end

  def link_expired?
    link_expires_at.present? && link_expires_at.past? && !finished? && !in_progress?
  end

  def status_label
    return "Link expired" if link_expired?

    { "pending" => "Link shared", "otp_requested" => "Awaiting OTP", "verified" => "Verified",
      "in_progress" => "Live now", "submitted" => "Submitted", "terminated" => "Terminated" }[status]
  end

  # ---- OTP flow -----------------------------------------------------------

  def request_otp!(phone)
    phone = phone.to_s.gsub(/\D/, "").last(10)
    raise ArgumentError, "Please enter a valid 10 digit mobile number" unless phone.length == 10
    if candidate_phone.present? && candidate_phone != phone
      raise ArgumentError, "This mobile number does not match the one registered by HR"
    end

    update!(entered_phone: phone, otp_code: format("%06d", SecureRandom.random_number(1_000_000)),
            otp_expires_at: OTP_TTL.from_now, otp_attempts: 0,
            status: (verified? || in_progress? || finished? ? status : "otp_requested"))
    log!("otp_requested", "Mobile +91 #{phone} - OTP #{otp_code}")
  end

  def verify_otp!(code)
    raise ArgumentError, "Please request an OTP first" if otp_code.blank?
    raise ArgumentError, "OTP expired. Please request a new one" if otp_expires_at.past?
    raise ArgumentError, "Too many wrong attempts. Please request a new OTP" if otp_attempts >= MAX_OTP_ATTEMPTS

    if ActiveSupport::SecurityUtils.secure_compare(otp_code, code.to_s.strip)
      update!(status: (in_progress? || finished? ? status : "verified"), verified_at: verified_at || Time.current,
              otp_code: nil, otp_expires_at: nil)
      log!("verified", "Mobile +91 #{entered_phone}")
      true
    else
      increment!(:otp_attempts)
      log!("otp_failed", "Attempt #{otp_attempts} of #{MAX_OTP_ATTEMPTS}")
      raise ArgumentError, "Incorrect OTP. #{MAX_OTP_ATTEMPTS - otp_attempts} attempt(s) left"
    end
  end

  def otp_active?
    otp_code.present? && otp_expires_at&.future?
  end

  # ---- Exam flow ----------------------------------------------------------

  def start!
    return if in_progress?

    update!(status: "in_progress", started_at: Time.current, answers: {})
    log!("exam_started", "#{quiz.questions.size} questions - #{quiz.duration_minutes} minutes")
  end

  def deadline
    started_at && started_at + quiz.duration_minutes.minutes
  end

  def seconds_left
    return 0 unless deadline

    [ (deadline - Time.current).to_i, 0 ].max
  end

  def time_up?
    in_progress? && seconds_left.zero?
  end

  def save_answer!(question_id, option_index)
    return unless in_progress? && quiz.questions.exists?(question_id)

    self.answers = answers.merge(question_id.to_s => option_index.presence&.to_i)
    save!
  end

  def submit!(final_answers = nil, reason: nil)
    return if finished?

    if final_answers.present?
      valid_ids = quiz.questions.pluck(:id).map(&:to_s)
      self.answers = answers.merge(final_answers.to_h.slice(*valid_ids).transform_values { |v| v.presence&.to_i })
    end

    questions = quiz.questions.to_a
    self.total_marks = questions.sum(&:marks)
    self.score = questions.sum { |q| q.correct?(answers[q.id.to_s]) ? q.marks : 0 }
    self.submitted_at = Time.current
    self.termination_reason = reason
    self.status = reason.present? && reason != "time_up" ? "terminated" : "submitted"
    save!

    case reason
    when nil then log!("exam_submitted", "Score #{score}/#{total_marks}")
    when "time_up" then log!("time_up", "Score #{score}/#{total_marks}")
    else log!("exam_terminated", "#{reason} - Score #{score}/#{total_marks}")
    end
  end

  # Records a proctoring signal. Returns the event; terminates the exam when warnings run out.
  def record_event!(kind, message: nil, snapshot: nil, metadata: {})
    counts = ProctorEvent::KINDS.dig(kind, 2) == true && in_progress?
    increment!(:warnings_count) if counts
    event = proctor_events.create!(kind: kind, message: message, snapshot: snapshot, metadata: metadata)

    if counts && max_warnings.positive? && warnings_count >= max_warnings
      submit!(reason: "Warning limit reached (#{warnings_count}/#{max_warnings})")
    end
    event
  end

  def answered_count
    answers.values.compact.size
  end

  def percentage
    return 0 if total_marks.to_i.zero?

    (score.to_f * 100 / total_marks).round
  end

  def passed?
    finished? && percentage >= quiz.pass_percentage
  end

  def time_taken
    submitted_at && started_at ? (submitted_at - started_at).to_i : nil
  end

  # Position among everyone who finished the same paper: higher % first, then faster.
  def rank
    return unless finished?

    peers = quiz.invitations.completed.to_a
    peers.sort_by { |i| [ -i.percentage, i.time_taken || Float::INFINITY ] }.index(self).to_i + 1
  end

  def result_label
    return "Pending" unless finished?

    passed? ? "Pass" : "Fail"
  end

  def risk_level
    v = proctor_events.violations.count
    return "low" if v.zero?
    return "medium" if v < 4

    "high"
  end

  # Interview panel: chosen for this candidate, else the batch's, else the vacancy's.
  def panelists
    return assigned_panelists if assigned_panelists.any?
    return exam_batch.panelists if exam_batch&.panelists&.any?

    opening ? opening.panelists : Employee.none
  end

  def panelist_ids=(ids)
    self.assigned_panelists = user.employees.where(id: Array(ids).compact_blank)
  end

  # Logged-in owner, or a panelist holding this candidate's / batch's watch link.
  def watchable_with?(user: nil, watch_token: nil)
    return true if user && user_id == user.id
    return false if watch_token.blank?

    [ self.watch_token, exam_batch&.watch_token ].compact.any? { |t| ActiveSupport::SecurityUtils.secure_compare(t, watch_token.to_s) }
  end

  # ---- Interview rounds ----------------------------------------------------

  DEFAULT_SELECTION = [ { name: "Online test", weight: 40 }, { name: "Technical interview", weight: 40 }, { name: "HR interview", weight: 20 } ].freeze

  def current_round
    interview_rounds.find(&:open?)
  end

  def interview_open?
    current_round.present?
  end

  # Creates rounds from the interview plan: one per interview stage, one combined round, or none.
  def build_interview_rounds
    return if interview_plan == "none" || interview_rounds.exists?

    params = interview_parameters
    if interview_plan == "combined"
      interview_rounds.create!(name: "Panel interview", position: 1, parameters: params, meeting_link: meeting_link)
    else
      params.each_with_index do |name, i|
        interview_rounds.create!(name: name, position: i + 1, parameters: [ name ], meeting_link: meeting_link)
      end
    end
  end

  # Re-plan only while nothing has happened in the rounds yet.
  def replan_rounds!
    return false if interview_rounds.any? { |r| !r.scheduled? } || interview_feedbacks.exists?

    interview_rounds.destroy_all
    interview_rounds.reset
    build_interview_rounds
    true
  end

  def interview_average
    vals = interview_feedbacks.filter_map(&:average)
    vals.any? ? (vals.sum / vals.size).round(1) : nil
  end

  def broadcast_feedback
    broadcast_replace_to [ self, :events ], target: "feedback_invitation_#{id}",
                         partial: "interview_feedbacks/summary", locals: { invitation: self }
    broadcast_replace_to [ self, :events ], target: "selection_invitation_#{id}",
                         partial: "invitations/selection_card", locals: { invitation: self }
    broadcast_rounds
  end

  # Round list for HR / panelists, and the candidate's "Join interview" prompt.
  def broadcast_rounds
    interview_rounds.reset
    broadcast_replace_to [ self, :events ], target: "rounds_invitation_#{id}",
                         partial: "interview_rounds/list", locals: { invitation: self }
    broadcast_replace_to [ self, :events ], target: "rounds_watch_#{id}",
                         partial: "interview_rounds/watch_list", locals: { invitation: self, watch_token: watch_token }
    broadcast_replace_to [ self, :candidate ], target: "interview_cta",
                         partial: "exams/interview_cta", locals: { invitation: self }
  end

  # ---- Decision & pipeline -------------------------------------------------

  PIPELINE = {
    "invited" => "Invited", "testing" => "Taking test", "interviews" => "Interviews",
    "decision" => "Decision pending", "selected" => "Selected", "on_hold" => "On hold", "rejected" => "Rejected"
  }.freeze

  def decide!(value, note = nil)
    update!(decision: value.presence, decision_note: note.presence, decided_at: value.present? ? Time.current : nil)
  end

  def decision_label
    DECISIONS[decision]
  end

  def pipeline_stage
    return decision if decision.present?
    return "testing" if in_progress?
    return "invited" unless finished?
    return "interviews" if interview_rounds.any? { |r| !r.done? }

    "decision"
  end

  # A selection parameter is the online test when its name says so; everything else is
  # scored by the interview panel.
  TEST_PARAMETER = /\b(test|exam|assessment|aptitude|written|mcq)\b/i

  # The vacancy's selection stages with weightage, e.g. Online test 30 / Technical 50 / HR 20.
  # Without a vacancy: online test and interview count half each.
  def selection_parameters
    list = Array(opening&.selection_parameters).filter_map do |p|
      { name: p["name"], weight: p["weight"].to_i } if p["name"].present? && p["weight"].to_i.positive?
    end
    list.presence || DEFAULT_SELECTION.map(&:dup)
  end

  # Interview stages the panel scores: every non-test selection parameter.
  def interview_parameters
    selection_parameters.map { |p| p[:name] }.grep_v(TEST_PARAMETER)
  end

  # Each stage with its score (0-100) once available:
  # online test -> test percentage; interview stage -> panel average for that parameter x 10
  # (a generic "Interview" stage uses the overall panel average).
  def selection_breakdown
    feedbacks = interview_feedbacks.select(&:persisted?)
    selection_parameters.map do |param|
      if param[:name].match?(TEST_PARAMETER)
        score = finished? ? percentage : nil
        source = finished? ? "#{self.score}/#{total_marks} marks" : "Test not taken yet"
      else
        vals = feedbacks.filter_map { |f| f.scores[param[:name]] }
        score = vals.any? ? (vals.sum.to_f / vals.size * 10).round : nil
        source = vals.any? ? "#{(vals.sum.to_f / vals.size).round(1)}/10 from #{vals.size} panelist#{'s' unless vals.size == 1}" : "Not scored yet"
      end
      param.merge(test: param[:name].match?(TEST_PARAMETER), score: score, source: source,
                  points: score && (score * param[:weight] / 100.0).round(1))
    end
  end

  # Weighted final score over the stages done so far.
  # => { percent:, done:, total:, complete: }
  def final_score
    stages = selection_breakdown
    done = stages.select { |s| s[:score] }
    total_weight = stages.sum { |s| s[:weight] }
    done_weight = done.sum { |s| s[:weight] }
    percent = done_weight.positive? ? (done.sum { |s| s[:score] * s[:weight] }.to_f / done_weight).round : nil
    { percent: percent, done: done.size, total: stages.size, complete: done.size == stages.size && total_weight.positive? }
  end

  def interview_average
    vals = interview_feedbacks.filter_map(&:average)
    vals.any? ? (vals.sum / vals.size).round(1) : nil
  end

  def broadcast_feedback
    broadcast_replace_to [ self, :events ], target: "feedback_invitation_#{id}",
                         partial: "interview_feedbacks/summary", locals: { invitation: self }
    broadcast_replace_to [ self, :events ], target: "selection_invitation_#{id}",
                         partial: "invitations/selection_card", locals: { invitation: self }
  end

  # Live monitor grid tile (also refreshed on every proctoring event / snapshot).
  def broadcast_tile
    broadcast_replace_to [ user, :invitations ], target: "monitor_tile_#{id}",
                         partial: "monitor/tile_info", locals: { invitation: self }
    # panelists watching a batch only get that batch's updates
    if exam_batch_id
      broadcast_replace_to [ exam_batch, :live ], target: "monitor_tile_#{id}",
                           partial: "monitor/tile_info", locals: { invitation: self }
    end
  end

  def latest_snapshot_event
    proctor_events.with_snapshots.order(created_at: :desc).first
  end

  def last_alert
    proctor_events.where.not(kind: "snapshot").order(created_at: :desc).first
  end

  private
    def resume_is_a_document
      return unless resume.attached?

      errors.add(:resume, "must be a PDF or Word file") unless resume.content_type.in?(%w[application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document])
      errors.add(:resume, "must be smaller than 10 MB") if resume.byte_size > 10.megabytes
    end

    # A vacancy picked from the master fills in the post name and department.
    def copy_opening_details
      return unless opening && (new_record? || will_save_change_to_vacancy_id?)

      self.vacancy = opening.title
      self.department = opening.department.name
    end

    def log!(kind, message = nil)
      proctor_events.create!(kind: kind, message: message)
    end

    def broadcast_live_state
      broadcast_replace_to [ self, :events ], target: "live_state_invitation_#{id}",
                           partial: "invitations/live_state", locals: { invitation: self }
      broadcast_replace_to [ user, :invitations ], target: "invitation_item_#{id}",
                           partial: "invitations/item", locals: { invitation: self }
      broadcast_tile
    end
end
