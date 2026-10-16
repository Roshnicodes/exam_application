class AddVacancyTitleToExamBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :exam_batches, :vacancy_title, :string
    add_column :exam_batches, :department, :string
  end
end
