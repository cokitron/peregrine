class WorkflowRunsController < ApplicationController
  before_action :set_workflow
  before_action :set_run, only: %i[show stop]

  PER_PAGE = 24

  def index
    @runs = @workflow.workflow_runs.recientes.limit(PER_PAGE).offset(page_offset)
  end

  def show
    respond_to do |format|
      format.json { render json: { status: @run.status, node_states: @run.node_states, error_message: @run.error_message } }
      format.html
    end
  end

  def stop
    if @run.status == "running"
      @run.update!(status: "cancelled")
      ActionCable.server.broadcast("workflow_run_#{@run.id}", { type: "cancelled", status: "cancelled" })
    end

    respond_to do |format|
      format.json { render json: { status: @run.status } }
      format.html { redirect_to workflow_path(@workflow), notice: "Workflow stopped" }
    end
  end

  private

  def set_workflow
    @workflow = WorkflowDefinition.find(params[:workflow_id])
  end

  def set_run
    @run = @workflow.workflow_runs.find(params[:id])
  end

  def page_offset
    [ (params[:page].to_i - 1), 0 ].max * PER_PAGE
  end
end
