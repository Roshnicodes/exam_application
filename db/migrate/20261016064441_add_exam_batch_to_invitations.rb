class AddExamBatchToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :invitations, :exam_batch, foreign_key: true
  end
end
