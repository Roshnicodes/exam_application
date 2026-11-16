# A candidate can be invited for a practical assessment only (Excel / Tally / Word …),
# so the MCQ question paper becomes optional on invitations and batches.
class AllowPracticalOnlyInvitations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :invitations, :quiz_id, true
    change_column_null :exam_batches, :quiz_id, true
    add_reference :invitations, :assessment, foreign_key: true
    add_reference :exam_batches, :assessment, foreign_key: true
  end
end
