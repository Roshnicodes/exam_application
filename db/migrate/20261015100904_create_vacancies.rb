class CreateVacancies < ActiveRecord::Migration[8.1]
  def change
    create_table :vacancies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :department, null: false, foreign_key: true
      t.string :title, null: false
      t.string :code
      t.date :issue_date
      t.date :end_date
      t.integer :positions, null: false, default: 1
      t.text :qualification
      t.string :experience_required
      t.jsonb :selection_parameters, null: false, default: []
      t.text :description

      t.timestamps
    end
  end
end
