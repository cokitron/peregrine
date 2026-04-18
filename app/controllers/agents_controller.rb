class AgentsController < ApplicationController
  before_action :set_agent, only: %i[show update destroy]

  PER_PAGE = 24

  def index
    @agents = Agent.order(updated_at: :desc).limit(PER_PAGE).offset(page_offset)
  end

  def create
    @agent = Agent.create!(nombre: "New Agent #{Time.current.strftime('%H:%M')}", steering_document: default_steering)
    redirect_to agent_path(@agent)
  end

  def show
  end

  def update
    if @agent.update(agent_params)
      head :ok
    else
      render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy
    redirect_to agents_path, notice: "Agent deleted"
  end

  private

  def set_agent
    @agent = Agent.find(params[:id])
  end

  def agent_params
    permitted = params.require(:agent).permit(:nombre, :descripcion, :steering_document)
    if params.dig(:agent, :context_files).present?
      permitted[:context_files] = Array(params[:agent][:context_files])
    end
    permitted
  end

  def page_offset
    [ (params[:page].to_i - 1), 0 ].max * PER_PAGE
  end

  def default_steering
    <<~MD
      # Agent Steering Document

      ## Role
      You are a specialized AI assistant.

      ## Guidelines
      - Be concise and direct
      - Follow best practices
      - Output code when asked

      ## Context
      Add project-specific context here.
    MD
  end
end
