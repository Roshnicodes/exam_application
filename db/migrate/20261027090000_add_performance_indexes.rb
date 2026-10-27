# Indexes for the lists that grow with use (candidates, proctoring events, interviews).
# Built CONCURRENTLY so running tests aren't blocked while the migration runs on production.
class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # candidates lists, tabs, counts and the dashboard
    add_index :invitations, [ :user_id, :created_at ], algorithm: :concurrently, if_not_exists: true
    add_index :invitations, [ :user_id, :status, :submitted_at ], algorithm: :concurrently, if_not_exists: true
    add_index :invitations, [ :user_id, :vacancy ], algorithm: :concurrently, if_not_exists: true
    add_index :invitations, [ :status, :started_at ], algorithm: :concurrently, if_not_exists: true # overdue tests job

    # proctoring timeline, snapshots, warnings (the biggest table: a snapshot every 30 s per candidate)
    add_index :proctor_events, [ :invitation_id, :created_at ], algorithm: :concurrently, if_not_exists: true
    add_index :proctor_events, [ :invitation_id, :kind, :created_at ], algorithm: :concurrently, if_not_exists: true
    add_index :proctor_events, :created_at, algorithm: :concurrently, if_not_exists: true

    # interview schedule / today's interviews
    add_index :interview_rounds, :scheduled_at, algorithm: :concurrently, if_not_exists: true
    add_index :interview_rounds, :status, algorithm: :concurrently, if_not_exists: true

    # question paper in order
    add_index :questions, [ :quiz_id, :position ], algorithm: :concurrently, if_not_exists: true

    # call chat history
    add_index :call_messages, [ :invitation_id, :created_at ], algorithm: :concurrently, if_not_exists: true
  end
end
