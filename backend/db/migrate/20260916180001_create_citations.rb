class CreateCitations < ActiveRecord::Migration[8.1]
  def change
    create_table :citations do |t|
      t.references :citing, polymorphic: true, null: false
      t.references :stored_file, null: false, foreign_key: true
      t.string :representation_kind, null: false
      t.jsonb :locator, null: false, default: {}
      t.timestamps
    end
    add_index :citations, [:citing_type, :citing_id]
  end
end
