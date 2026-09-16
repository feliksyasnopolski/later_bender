class CreateStoredFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :stored_files do |t|
      t.references :project, null: false, foreign_key: true
      t.bigint :number, null: false
      t.string :filename, null: false
      t.string :media_type, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false
      t.timestamps
    end
    add_index :stored_files, [:project_id, :number], unique: true
    create_table :file_tags do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :file_tags, [:stored_file_id, :tag_id], unique: true
    create_table :file_tasks do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true
      t.timestamps
    end
    add_index :file_tasks, [:stored_file_id, :task_id], unique: true
    create_table :file_notes do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :note, null: false, foreign_key: true
      t.timestamps
    end
    add_index :file_notes, [:stored_file_id, :note_id], unique: true
  end
end
