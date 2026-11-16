# Excel tasks can be solved in a spreadsheet built into the assessment page (formulas, sheets,
# autosave): no Excel needed on the candidate's computer, no download / upload, no app switching.
# The candidate's workbook is kept on the round and turned into an .xlsx when they submit.
class AddOnlineSheetToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_column :assessments, :online_sheet, :boolean, null: false, default: true
    add_column :interview_rounds, :sheet_data, :jsonb
    add_column :interview_rounds, :sheet_saved_at, :datetime
  end
end
