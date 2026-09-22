class AddRemoteAgentSessionGeneration < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_agents, :session_generation, :bigint, null: false, default: 0
    add_column :remote_agent_sessions, :generation, :bigint, null: false, default: 0
  end
end
