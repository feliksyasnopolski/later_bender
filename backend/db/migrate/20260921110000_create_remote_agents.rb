class CreateRemoteAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_agents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ref, null: false
      t.integer :public_number, null: false
      t.string :name, null: false
      t.text :public_key, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :revoked_at
      t.string :platform, null: false
      t.string :architecture, null: false
      t.jsonb :supported_executors, null: false, default: []
      t.jsonb :capabilities, null: false, default: {}
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :remote_agents, %i[user_id public_number], unique: true
    add_index :remote_agents, %i[user_id ref], unique: true

    create_table :remote_agent_enrollment_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :remote_agent_enrollment_tokens, :token_digest, unique: true, name: "index_remote_agent_enrollment_tokens_on_digest"

    create_table :remote_agent_challenges do |t|
      t.references :remote_agent, null: false, foreign_key: true
      t.string :challenge_id, null: false
      t.string :nonce_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :remote_agent_challenges, :challenge_id, unique: true

    create_table :remote_agent_sessions do |t|
      t.references :remote_agent, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :connected_at, null: false
      t.datetime :last_heartbeat_at, null: false
      t.datetime :disconnected_at
      t.timestamps
    end
    add_index :remote_agent_sessions, :token_digest, unique: true
    add_index :remote_agent_sessions, %i[remote_agent_id disconnected_at]
  end
end
