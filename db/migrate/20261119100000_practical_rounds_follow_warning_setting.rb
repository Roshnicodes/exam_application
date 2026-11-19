# Practical rounds used to keep a copy of the test's warning limit from when they were given,
# so changing the practical test to "Never" later didn't reach them. Rounds not yet submitted
# now follow the practical test's current setting (blank = use the test's value).
class PracticalRoundsFollowWarningSetting < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE interview_rounds SET max_warnings = NULL
      WHERE kind = 'assessment' AND assessment_id IS NOT NULL AND submitted_at IS NULL AND max_warnings IS NOT NULL
    SQL
  end

  def down
    # nothing to undo: blank simply means "use the practical test's setting"
  end
end
