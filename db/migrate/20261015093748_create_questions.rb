class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.references :quiz, null: false, foreign_key: true
      t.text :body, null: false
      t.jsonb :options, null: false, default: []
      t.integer :correct_index, null: false, default: 0
      t.integer :marks, null: false, default: 1
      t.integer :position

      t.timestamps
    end
  end
end
