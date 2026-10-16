class CreateExamBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :exam_batches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :quiz, null: false, foreign_key: true
      t.references :vacancy, foreign_key: true
      t.string :name, null: false
      t.datetime :interview_date
      t.string :interview_mode
      t.string :location
      t.text :notes
      t.integer :max_warnings, null: false, default: 5
      t.datetime :link_expires_at

      t.timestamps
    end
  end
end
