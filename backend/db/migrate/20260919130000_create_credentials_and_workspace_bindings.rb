class CreateCredentialsAndWorkspaceBindings < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ref, null: false
      t.integer :public_number, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.string :env_name
      t.string :file_path
      t.integer :file_mode
      t.text :secret, null: false
      t.timestamps
    end
    add_index :credentials, :ref, unique: true
    add_index :credentials, "user_id, lower(name)", unique: true, name: "index_credentials_on_user_and_lower_name"

    add_column :workspaces, :credential_bindings, :jsonb, null: false, default: []
  end
end
