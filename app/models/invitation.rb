class Invitation < ApplicationRecord
  STATUSES = %w[pending otp_requested verified in_progress submitted terminated].freeze
  INTERVIEW_MODES = [ "Online", "In-person", "Telephonic" ].freeze
  OTP_TTL = 10.minutes
  MAX_OTP_ATTEMPTS = 5

  belongs_to :user
  belongs_to :quiz
  belongs_to :exam_batch, optional: true
  belongs_to :opening, class_name: "Vacancy", foreign_key: :vacancy_id, optional: true, inverse_of: :invitations
  has_many :proctor_events, dependent: :destroy
  has_many_attached :recordings

  has_secure_token :token, length: 24
  has_secure_token :watch_token, length: 24 # read-only live view link for panelists

  has_many :interview_feedbacks, -> { order(:created_at) }, dependent: :destroy
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
  validates :meeting_link, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
  scope :live, -> { where(status: "in_progress") }
  scope :completed, -> { where(status: %w[submitted terminated]) }

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

  # ---- Interview room ------------------------------------------------------

  DEFAULT_INTERVIEW_PARAMETERS = [ "Communication", "Technical knowledge", "Problem solving", "Attitude & fit" ].freeze

  def interview_open?
    interview_status == "open"
  end

  def open_interview!
    update!(interview_status: "open", interview_started_at: interview_started_at || Time.current)
  end

  def close_interview!
    update!(interview_status: "closed")
  end

  # What panelists score: the vacancy's selection parameters (minus the online test), else sensible defaults.
  def interview_parameters
    names = Array(opening&.selection_parameters).map { |p| p["name"] }.compact_blank
    names = names.reject { |n| n.match?(/\b(test|exam|assessment|aptitude|written)\b/i) }
    names.presence || DEFAULT_INTERVIEW_PARAMETERS
  end

  def interview_average
    vals = interview_feedbacks.filter_map(&:average)
    vals.any? ? (vals.sum / vals.size).round(1) : nil
  end

  def broadcast_feedback
    broadcast_replace_to [ self, :events ], target: "feedback_invitation_#{id}",
                         partial: "interview_feedbacks/summary", locals: { invitation: self }
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
      if saved_change_to_interview_status?
        broadcast_replace_to [ self, :candidate ], target: "interview_cta",
                             partial: "exams/interview_cta", locals: { invitation: self }
      end
      broadcast_replace_to [ self, :events ], target: "live_state_invitation_#{id}",
                           partial: "invitations/live_state", locals: { invitation: self }
      broadcast_replace_to [ user, :invitations ], target: "invitation_item_#{id}",
                           partial: "invitations/item", locals: { invitation: self }
      broadcast_tile
    end
end
