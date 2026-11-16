class CreateAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :assessments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :kind, null: false, default: "excel"
      t.text :description
      t.text :instructions
      t.integer :duration_minutes, null: false, default: 45
      t.integer :max_marks, null: false, default: 100
      t.integer :pass_percentage, null: false, default: 50
      t.integer :max_warnings, null: false, default: 5
      t.boolean :allow_download, null: false, default: true
      t.boolean :require_upload, null: false, default: true
      t.boolean :allow_notes, null: false, default: true
      t.string :allowed_extensions
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :assessments, [ :user_id, :title ]
  end
end
