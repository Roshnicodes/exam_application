class AddInterviewRoom < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :interview_status, :string     # nil / "open" / "closed"
    add_column :invitations, :interview_started_at, :datetime
    add_column :invitations, :meeting_link, :string          # optional Google Meet / Zoom link
    add_column :exam_batches, :meeting_link, :string

    create_table :interview_feedbacks do |t|
      t.references :invitation, null: false, foreign_key: true
      t.references :employee, foreign_key: true   # panelist (via watch link)
      t.references :user, foreign_key: true       # HR (logged in)
      t.string :reviewer_name, null: false
      t.jsonb :scores, null: false, default: {}   # { "Technical interview" => 8, ... } out of 10
      t.string :recommendation, null: false
      t.text :comments
      t.timestamps
    end
    add_index :interview_feedbacks, [ :invitation_id, :employee_id ], unique: true, where: "employee_id IS NOT NULL"
    add_index :interview_feedbacks, [ :invitation_id, :user_id ], unique: true, where: "user_id IS NOT NULL"
  end
end
