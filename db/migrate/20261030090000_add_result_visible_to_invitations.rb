# HR decides, per candidate, when the candidate may see their result (hidden by default).
# The paper-wide "show result" tick is switched off everywhere so nobody sees a result by default.
class AddResultVisibleToInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :invitations, :result_visible, :boolean, null: false, default: false
    execute "UPDATE quizzes SET show_result_to_candidate = FALSE"
  end

  def down
    remove_column :invitations, :result_visible
  end
end
