class AddPublicTokenToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :stored_files, :public_token, :string
    add_index :stored_files, :public_token, unique: true
  end
end
