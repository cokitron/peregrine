class CreateWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_runs, id: :uuid do |t|
      t.references :workflow_definition, type: :uuid, null: false, foreign_key: true
      t.string :status, limit: 20, null: false, default: "pending"
      t.string :run_dir
      t.jsonb :node_states, null: false, default: {}
      t.text :input_text
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
