class CreateProctorEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :proctor_events do |t|
      t.references :invitation, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :message
      t.string :severity, null: false, default: "warning"
      t.jsonb :metadata, null: false, default: {}
      t.datetime :acknowledged_at

      t.timestamps
    end
  end
end
