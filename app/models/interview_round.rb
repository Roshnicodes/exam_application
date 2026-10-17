# One interview stage for a candidate, e.g. "Technical interview" or "HR interview"
# (or a single combined "Panel interview"). Each round has its own schedule, panel,
# video room and scorecards.
class InterviewRound < ApplicationRecord
  STATUSES = { "scheduled" => "Scheduled", "open" => "Live now", "completed" => "Completed", "cancelled" => "Cancelled" }.freeze

  belongs_to :invitation
  has_many :interview_round_panelists, dependent: :destroy
  has_many :assigned_panelists, through: :interview_round_panelists, source: :employee
  has_many :interview_feedbacks, -> { order(:created_at) }, dependent: :destroy
  has_many :call_messages, -> { chronological }, dependent: :destroy
  has_many :code_pads, dependent: :destroy

  normalizes :name, with: ->(v) { v.to_s.squish }

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :meeting_link, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }, allow_blank: true

  scope :ordered, -> { order(:position, :id) }
  scope :upcoming, -> { where(status: %w[scheduled open]) }

  after_commit :broadcast_changes

  STATUSES.each_key { |s| define_method("#{s}?") { status == s } }

  def status_label
    STATUSES[status]
  end

  def done?
    completed? || cancelled?
  end

  # Opening a round closes any other live round of the same candidate (one room at a time).
  def open!
    transaction do
      invitation.interview_rounds.where(status: "open").where.not(id: id).update_all(status: "completed", ended_at: Time.current)
      update!(status: "open", started_at: started_at || Time.current)
    end
  end

  def complete!
    update!(status: "completed", ended_at: Time.current)
  end

  # What this round's panel scores (defaults to every interview parameter of the vacancy).
  def score_parameters
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

  private
    def broadcast_changes
      invitation.broadcast_rounds
    end
end
