class AddHindiToQuestionsAndLanguageToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :body_hi, :text
    add_column :questions, :options_hi, :jsonb, null: false, default: []
    add_column :invitations, :language, :string, null: false, default: "en"
    add_column :exam_batches, :language, :string, null: false, default: "en"
  end
end
