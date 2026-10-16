class RemoveCodeFromDepartments < ActiveRecord::Migration[8.1]
  def change
    remove_column :departments, :code, :string
  end
end
