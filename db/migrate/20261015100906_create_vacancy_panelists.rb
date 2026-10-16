class CreateVacancyPanelists < ActiveRecord::Migration[8.1]
  def change
    create_table :vacancy_panelists do |t|
      t.references :vacancy, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.string :role

      t.timestamps
    end
    add_index :vacancy_panelists, [ :vacancy_id, :employee_id ], unique: true
  end
end
