class AddShowResultToQuizzes < ActiveRecord::Migration[8.1]
  def change
    add_column :quizzes, :show_result_to_candidate, :boolean, null: false, default: false
  end
end
