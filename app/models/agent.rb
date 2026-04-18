class Agent < ApplicationRecord
  has_many :workflow_definitions, foreign_key: :default_agent_id

  validates :nombre, presence: true, length: { maximum: 200 }

  # Generates the .kiro/agents/<name>.json file with the steering doc as a resource.
  # Returns the agent name (used with --agent flag).
  def materialize!
    steering_path = Rails.root.join(".kiro", "steering", "#{slug}.md")
    FileUtils.mkdir_p(steering_path.dirname)
    File.write(steering_path, steering_document)

    builder = KiroFlow::AgentBuilder.new(slug)
      .description(descripcion || nombre)
      .tools(["fs_read", "fs_write", "execute_bash"])
      .allow_tools(["fs_read", "execute_bash"])
      .resource("file://#{steering_path}")
      .tool_settings("execute_bash", { "autoAllowReadonly" => true })

    context_files.each { |path| builder.resource("file://#{path}") if path.present? }

    builder.build!(Rails.root.join(".kiro", "agents").to_s)

    slug
  end

  def slug
    nombre.parameterize
  end
end
