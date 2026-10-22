class AddRoughNotesToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :rough_notes, :text
  end
end
