# A chat message sent in a video call: the call during the online test (no round) or an interview round.
class CallMessage < ApplicationRecord
  ROLES = { "candidate" => "Candidate", "hr" => "HR", "panelist" => "Panelist" }.freeze

  belongs_to :invitation
  belongs_to :interview_round, optional: true

  validates :sender_name, presence: true
  validates :sender_role, inclusion: { in: ROLES.keys }
  validates :body, presence: true, length: { maximum: 2000 }

  scope :chronological, -> { order(:created_at, :id) }

  def as_chat
    { id: id, name: sender_name, role: sender_role, body: body, at: created_at.iso8601 }
  end
end
