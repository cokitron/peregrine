class AddForeignKeyAndIndexOnDefaultAgentId < ActiveRecord::Migration[8.1]
  def change
    add_index :workflow_definitions, :default_agent_id
    add_foreign_key :workflow_definitions, :agents, column: :default_agent_id, on_delete: :nullify
  end
end
