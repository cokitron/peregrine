class AddContextFilesToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :context_files, :jsonb, default: [], null: false
  end
end
