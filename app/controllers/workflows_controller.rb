class WorkflowsController < ApplicationController
  before_action :set_workflow, only: %i[show update destroy execute]

  PER_PAGE = 24

  def index
    @workflows = WorkflowDefinition.order(updated_at: :desc)
                                   .limit(PER_PAGE)
                                   .offset(page_offset)
  end

  def new
    @workflow = WorkflowDefinition.new(
      nombre: "New Workflow",
      drawflow_data: { "steps" => [] }
    )
    @agents = Agent.order(:nombre)
    @workflows = WorkflowDefinition.where(is_active: true).order(:nombre)
    render :show
  end

  def create
    @workflow = WorkflowDefinition.new(workflow_params)
    if @workflow.save
      respond_to do |format|
        format.json { render json: { url: workflow_path(@workflow) }, status: :created }
        format.html { redirect_to workflow_path(@workflow), notice: "Workflow created" }
      end
    else
      @agents = Agent.order(:nombre)
      respond_to do |format|
        format.json { render json: { errors: @workflow.errors.full_messages }, status: :unprocessable_entity }
        format.html { render :show, status: :unprocessable_entity }
      end
    end
  end

  def show
    @agents = Agent.order(:nombre)
    @workflows = WorkflowDefinition.where.not(id: @workflow.id).where(is_active: true).order(:nombre)
  end

  def update
    if @workflow.update(workflow_params)
      head :ok
    else
      render json: { errors: @workflow.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @workflow.destroy
    redirect_to workflows_path, notice: "Workflow deleted"
  end

  def execute
    run = @workflow.workflow_runs.create!(status: "pending", input_text: params[:input_text])
    ExecuteWorkflowJob.perform_later(run.id)

    respond_to do |format|
      format.json { render json: { run_id: run.id, status_url: workflow_run_path(@workflow, run, format: :json) } }
      format.html { redirect_to workflow_path(@workflow), notice: "Workflow started" }
    end
  end

  ALLOWED_STEP_KEYS = %w[ type name prompt command code condition next on_true on_false agent_id model workflow_id disabled ].freeze

  private

  def set_workflow
    @workflow = WorkflowDefinition.find(params[:id])
  end

  def workflow_params
    permitted = params.require(:workflow_definition).permit(:nombre, :descripcion, :is_active, :default_agent_id)
    if params.dig(:workflow_definition, :drawflow_data).present?
      permitted[:drawflow_data] = sanitize_drawflow_data(params[:workflow_definition][:drawflow_data])
    end
    permitted
  end

  def sanitize_drawflow_data(raw)
    data = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    return { "steps" => [] } unless data.is_a?(Hash)

    steps = Array(data["steps"]).map do |step|
      step.to_h.slice(*ALLOWED_STEP_KEYS)
    end
    { "steps" => steps }
  end

  def page_offset
    [ (params[:page].to_i - 1), 0 ].max * PER_PAGE
  end
end
