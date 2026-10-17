class AddInterviewRounds < ActiveRecord::Migration[8.1]
  def up
    create_table :interview_rounds do |t|
      t.references :invitation, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 1
      t.jsonb :parameters, null: false, default: []   # selection parameters this round scores
      t.datetime :scheduled_at
      t.string :meeting_link
      t.string :status, null: false, default: "scheduled" # scheduled / open / completed / cancelled
      t.datetime :started_at
      t.datetime :ended_at
      t.text :notes
      t.timestamps
    end

    create_table :interview_round_panelists do |t|
      t.references :interview_round, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.timestamps
    end
    add_index :interview_round_panelists, [ :interview_round_id, :employee_id ], unique: true, name: "index_round_panelists_unique"

    add_reference :interview_feedbacks, :interview_round, foreign_key: true
    remove_index :interview_feedbacks, [ :invitation_id, :employee_id ]
    remove_index :interview_feedbacks, [ :invitation_id, :user_id ]
    add_index :interview_feedbacks, [ :interview_round_id, :employee_id ], unique: true, where: "employee_id IS NOT NULL", name: "index_feedbacks_round_employee"
    add_index :interview_feedbacks, [ :interview_round_id, :user_id ], unique: true, where: "user_id IS NOT NULL", name: "index_feedbacks_round_user"

    add_column :invitations, :interview_plan, :string, null: false, default: "separate" # separate / combined / none
    add_column :invitations, :decision, :string            # selected / on_hold / rejected
    add_column :invitations, :decision_note, :text
    add_column :invitations, :decided_at, :datetime
    add_column :exam_batches, :interview_plan, :string, null: false, default: "separate"

    # Existing single-room interviews become one combined round that keeps their feedback.
    execute <<~SQL
      INSERT INTO interview_rounds (invitation_id, name, position, parameters, status, started_at, meeting_link, created_at, updated_at)
      SELECT i.id, 'Panel interview', 1, '[]'::jsonb,
             CASE i.interview_status WHEN 'open' THEN 'open' ELSE 'completed' END,
             i.interview_started_at, i.meeting_link, NOW(), NOW()
      FROM invitations i
      WHERE i.interview_status IS NOT NULL OR EXISTS (SELECT 1 FROM interview_feedbacks f WHERE f.invitation_id = i.id)
    SQL
    execute <<~SQL
      UPDATE interview_feedbacks f SET interview_round_id = r.id
      FROM interview_rounds r WHERE r.invitation_id = f.invitation_id AND f.interview_round_id IS NULL
    SQL
  end

  def down
    remove_column :exam_batches, :interview_plan
    remove_column :invitations, :decided_at
    remove_column :invitations, :decision_note
    remove_column :invitations, :decision
    remove_column :invitations, :interview_plan
    remove_index :interview_feedbacks, name: "index_feedbacks_round_user"
    remove_index :interview_feedbacks, name: "index_feedbacks_round_employee"
    add_index :interview_feedbacks, [ :invitation_id, :employee_id ], unique: true, where: "employee_id IS NOT NULL"
    add_index :interview_feedbacks, [ :invitation_id, :user_id ], unique: true, where: "user_id IS NOT NULL"
    remove_reference :interview_feedbacks, :interview_round, foreign_key: true
    drop_table :interview_round_panelists
    drop_table :interview_rounds
  end
end
