class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.references :user, null: false, foreign_key: true
      t.string :employee_code
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :department_name
      t.string :designation

      t.timestamps
    end
    add_index :employees, [ :user_id, :employee_code ], unique: true
  end
end
