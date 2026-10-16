class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code
      t.string :head_name
      t.text :description
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :departments, [ :user_id, :name ], unique: true
  end
end
