class CreateWorkflowDefinitions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :workflow_definitions, id: :uuid do |t|
      t.string :nombre, limit: 200, null: false
      t.text :descripcion
      t.jsonb :drawflow_data, null: false, default: {}
      t.boolean :is_active, null: false, default: true
      t.timestamps
    end
  end
end
