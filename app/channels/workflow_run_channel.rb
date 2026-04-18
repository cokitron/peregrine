class WorkflowRunChannel < ApplicationCable::Channel
  def subscribed
    stream_from "workflow_run_#{params[:run_id]}"
  end
end
