class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ref, null: false
      t.string :label
      t.string :state, null: false, default: "starting"
      t.string :environment, null: false
      t.string :architecture, null: false
      t.string :os_name, null: false
      t.string :os_version, null: false
      t.string :shell, null: false
      t.string :workspace_root, null: false, default: "/workspace"
      t.jsonb :limits, null: false, default: {}
      t.jsonb :capabilities, null: false, default: {}
      t.string :runner_handle
      t.datetime :last_activity_at, null: false
      t.datetime :expires_at
      t.timestamps
    end
    add_index :workspaces, :ref, unique: true
    add_index :workspaces, %i[user_id state]

    create_table :workspace_executions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :ref, null: false
      t.integer :sequence, null: false
      t.string :state, null: false, default: "running"
      t.jsonb :invocation, null: false, default: {}
      t.string :cwd, null: false, default: "/workspace"
      t.jsonb :env, null: false, default: {}
      t.jsonb :secret_env_names, null: false, default: []
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :exit_code
      t.string :terminating_signal
      t.decimal :requested_timeout_seconds
      t.string :stdout_handle, null: false
      t.string :stderr_handle, null: false
      t.timestamps
    end
    add_index :workspace_executions, :ref, unique: true
    add_index :workspace_executions, %i[workspace_id sequence], unique: true

    create_table :workspace_events do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
    end
    add_index :workspace_events, %i[workspace_id sequence], unique: true
  end
end
