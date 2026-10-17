class CreateCodePads < ActiveRecord::Migration[8.1]
  def change
    create_table :code_pads do |t|
      t.references :invitation, null: false, foreign_key: true
      t.references :interview_round, foreign_key: true # nil = the video call during the online test
      t.string :language, null: false, default: "plaintext"
      t.text :content, null: false, default: ""

      t.timestamps
    end
    add_index :code_pads, %i[invitation_id interview_round_id], unique: true
  end
end
