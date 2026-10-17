class InterviewRoundPanelist < ApplicationRecord
  belongs_to :interview_round
  belongs_to :employee
end
