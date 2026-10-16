class InvitationPanelist < ApplicationRecord
  belongs_to :invitation
  belongs_to :employee
end
