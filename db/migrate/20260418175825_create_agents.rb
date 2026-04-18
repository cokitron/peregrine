class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents, id: :uuid do |t|
      t.string :nombre, limit: 200, null: false
      t.text :descripcion
      t.text :steering_document, null: false, default: ""
      t.timestamps
    end

    add_column :workflow_definitions, :default_agent_id, :uuid
  end
end
