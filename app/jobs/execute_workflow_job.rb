class ExecuteWorkflowJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    run = WorkflowRun.find(run_id)
    WorkflowExecutionService.new(run).call
  rescue => e
    run&.update!(status: "failed", error_message: e.message, completed_at: Time.current)
    ActionCable.server.broadcast("workflow_run_#{run.id}", { type: "failed", error: e.message }) if run
  end
end
