class CreateCallMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :call_messages do |t|
      t.references :invitation, null: false, foreign_key: true
      t.references :interview_round, foreign_key: true # nil = the video call during the online test
      t.string :sender_name, null: false
      t.string :sender_role, null: false
      t.text :body, null: false

      t.timestamps
    end
  end
end
