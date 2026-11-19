# A practical test can carry an answer key: the questions with their correct answer / model
# answer and marks. The candidate fills an answer sheet; it is marked automatically on submit
# (MCQs and numbers exactly, written answers by their key points) and HR can adjust any mark.
class AddAnswerKeyToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_column :assessments, :answer_items, :jsonb, null: false, default: []
    add_column :interview_rounds, :answers, :jsonb, null: false, default: {}
    add_column :interview_rounds, :item_marks, :jsonb, null: false, default: {}
  end
end
