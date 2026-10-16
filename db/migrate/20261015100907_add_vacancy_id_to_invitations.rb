class AddVacancyIdToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :invitations, :vacancy, foreign_key: true
  end
end
