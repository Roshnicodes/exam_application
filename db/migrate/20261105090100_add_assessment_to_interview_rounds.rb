class AddAssessmentToInterviewRounds < ActiveRecord::Migration[8.1]
  def change
    add_column :interview_rounds, :kind, :string, null: false, default: "interview"
    add_reference :interview_rounds, :assessment, foreign_key: true
    add_column :interview_rounds, :duration_minutes, :integer
    add_column :interview_rounds, :max_warnings, :integer
    add_column :interview_rounds, :max_marks, :integer
    add_column :interview_rounds, :marks, :integer
    add_column :interview_rounds, :instructions, :text
    add_column :interview_rounds, :candidate_notes, :text
    add_column :interview_rounds, :work_started_at, :datetime
    add_column :interview_rounds, :submitted_at, :datetime
    add_column :interview_rounds, :termination_reason, :string
    add_column :interview_rounds, :graded_at, :datetime
    add_column :interview_rounds, :grade_note, :text
    add_index :interview_rounds, [ :kind, :status ]
  end
end
