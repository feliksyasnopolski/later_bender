class CreateFileRepresentations < ActiveRecord::Migration[8.1]
  def change
    create_table :file_representations do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :content
      t.string :media_type
      t.string :generator, null: false
      t.string :generator_version, null: false
      t.string :status, null: false, default: "ready"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :file_representations, [:stored_file_id, :kind], unique: true
  end
end
