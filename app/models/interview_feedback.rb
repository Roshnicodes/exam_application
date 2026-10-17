# A panelist's (or HR's) scorecard for one candidate's interview.
class InterviewFeedback < ApplicationRecord
  RECOMMENDATIONS = {
    "strong_hire" => "Strong hire",
    "hire" => "Hire",
    "hold" => "Hold",
    "reject" => "Reject"
  }.freeze

  belongs_to :invitation
  belongs_to :interview_round, optional: true
  belongs_to :employee, optional: true
  belongs_to :user, optional: true

  before_validation :clean_scores

  validates :reviewer_name, presence: true
  validates :recommendation, inclusion: { in: RECOMMENDATIONS.keys }

  after_commit :broadcast_summary

  def recommendation_label
    RECOMMENDATIONS[recommendation]
  end

  # Average out of 10 across the parameters that were scored.
  def average
    vals = scores.values.compact
    vals.any? ? (vals.sum.to_f / vals.size).round(1) : nil
  end

  private
    def clean_scores
      self.scores = scores.to_h.transform_values { |v| v.presence && v.to_i.clamp(0, 10) }.compact
    end

    def broadcast_summary
      invitation.broadcast_feedback
    end
end
