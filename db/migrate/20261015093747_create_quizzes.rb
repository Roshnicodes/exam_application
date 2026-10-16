class CreateQuizzes < ActiveRecord::Migration[8.1]
  def change
    create_table :quizzes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :duration_minutes, null: false, default: 30
      t.integer :pass_percentage, null: false, default: 60

      t.timestamps
    end
  end
end
