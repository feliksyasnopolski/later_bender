class AddOriginToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :stored_files, :origin, :jsonb
  end
end
