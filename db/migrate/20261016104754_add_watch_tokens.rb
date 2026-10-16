class AddWatchTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :watch_token, :string
    add_index :invitations, :watch_token, unique: true
    add_column :exam_batches, :watch_token, :string
    add_index :exam_batches, :watch_token, unique: true

    create_table :invitation_panelists do |t|
      t.references :invitation, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.timestamps
    end
    add_index :invitation_panelists, [ :invitation_id, :employee_id ], unique: true

    create_table :exam_batch_panelists do |t|
      t.references :exam_batch, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.timestamps
    end
    add_index :exam_batch_panelists, [ :exam_batch_id, :employee_id ], unique: true

    reversible do |dir|
      dir.up do
        execute "UPDATE invitations SET watch_token = md5(random()::text || id::text) WHERE watch_token IS NULL"
        execute "UPDATE exam_batches SET watch_token = md5(random()::text || id::text) WHERE watch_token IS NULL"
      end
    end
  end
end
