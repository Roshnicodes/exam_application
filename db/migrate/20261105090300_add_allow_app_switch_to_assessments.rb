# Some practical tasks are solved in another app (Excel, Tally): the candidate has to leave the
# browser window, so tab / app-switch warnings can be turned off for that assessment.
# Everything else (camera, second person, phone, screen recording) keeps running.
class AddAllowAppSwitchToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_column :assessments, :allow_app_switch, :boolean, null: false, default: false
    add_column :interview_rounds, :allow_app_switch, :boolean
  end
end
