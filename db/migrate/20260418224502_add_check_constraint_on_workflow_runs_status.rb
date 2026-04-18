class AddCheckConstraintOnWorkflowRunsStatus < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      ALTER TABLE workflow_runs
      ADD CONSTRAINT workflow_runs_status_check
      CHECK (status IN ('pending', 'running', 'completed', 'failed'))
    SQL
  end

  def down
    execute <<~SQL.squish
      ALTER TABLE workflow_runs
      DROP CONSTRAINT workflow_runs_status_check
    SQL
  end
end
