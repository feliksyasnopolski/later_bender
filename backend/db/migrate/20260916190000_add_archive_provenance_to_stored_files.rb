class AddArchiveProvenanceToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :stored_files, :archive_source, foreign_key: { to_table: :stored_files }, null: true
    add_column :stored_files, :archive_entry_path, :string
    add_check_constraint :stored_files, "(archive_source_id IS NULL AND archive_entry_path IS NULL) OR (archive_source_id IS NOT NULL AND archive_entry_path IS NOT NULL)", name: "stored_files_archive_provenance_complete"
  end
end
