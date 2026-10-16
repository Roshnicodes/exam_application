class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :quiz, null: false, foreign_key: true
      t.string :candidate_name, null: false
      t.string :candidate_email
      t.string :candidate_phone
      t.string :vacancy, null: false
      t.string :department
      t.string :experience
      t.datetime :interview_date
      t.string :interview_mode
      t.string :location
      t.text :notes
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.string :entered_phone
      t.string :otp_code
      t.datetime :otp_expires_at
      t.integer :otp_attempts, null: false, default: 0
      t.datetime :verified_at
      t.datetime :started_at
      t.datetime :submitted_at
      t.datetime :link_expires_at
      t.integer :score
      t.integer :total_marks
      t.jsonb :answers, null: false, default: {}
      t.integer :warnings_count, null: false, default: 0
      t.integer :max_warnings, null: false, default: 5
      t.string :termination_reason

      t.timestamps
    end
    add_index :invitations, :token, unique: true
  end
end
