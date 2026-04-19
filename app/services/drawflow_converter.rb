# WARNING: SECURITY — This service uses `eval` to execute user-defined Ruby code
# and gate conditions from workflow definitions. This is intentional for trusted-user
# deployments where workflow authors are trusted operators. DO NOT expose workflow
# creation to untrusted users without sandboxing eval or replacing it with a safe DSL.
# See: https://ruby-doc.org/core/Kernel.html#method-i-eval
class DrawflowConverter
  MAX_DEPTH = 5

  def self.call(data, default_agent_id: nil)
    new(data, default_agent_id: default_agent_id).convert
  end

  def initialize(data, default_agent_id: nil)
    @steps = data["steps"] || []
    @default_agent_id = default_agent_id
  end

  def convert
    flat = flatten_steps(@steps, depth: 0)
    default_agent_id = @default_agent_id

    # Build a name→step map and collect explicit edges
    step_map = {}
    flat.each { |s| step_map[s["name"]] = s }

    KiroFlow::Workflow.new("visual").tap do |wf|
      # Register all nodes
      flat.each do |s|
        type = (s["type"] || "kiro").to_sym
        name = (s["name"] || "step").to_sym
        case type
        when :kiro
          agent_id = s["agent_id"].presence || default_agent_id
          agent_slug = self.class.resolve_agent(agent_id)
          opts = { type: :kiro, prompt: s["prompt"] || "" }
          opts[:agent] = agent_slug if agent_slug
          opts[:model] = s["model"] if s["model"].present?
          opts[:timeout] = s["timeout"].to_i if s["timeout"].present?
          wf.node(name, **opts)
        when :shell
          wf.node(name, type: :shell, command: s["command"] || "echo ok")
        when :ruby
          code = s["code"] || "''"
          wf.node(name, type: :ruby, callable: ->(ctx) { eval(code) }) # rubocop:disable Security/Eval
        when :gate
          cond = s["condition"] || "true"
          wf.node(name, type: :conditional, condition: ->(ctx) { eval(cond) }) # rubocop:disable Security/Eval
        end
      end

      # Wire edges using explicit next/on_true/on_false, falling back to array order
      flat.each_with_index do |s, i|
        name = s["name"]&.to_sym
        next unless name

        if s["type"] == "gate"
          wf.connect(name >> s["on_true"].to_sym) if s["on_true"].present?
          wf.connect(name >> s["on_false"].to_sym) if s["on_false"].present?
        elsif s["next"].present?
          wf.connect(name >> s["next"].to_sym)
        elsif i < flat.length - 1
          # Fallback: connect to next step in array order
          next_name = flat[i + 1]["name"]&.to_sym
          wf.connect(name >> next_name) if next_name
        end
      end
    end
  end

  def self.resolve_agent(agent_id)
    return nil if agent_id.blank?
    agent = Agent.find_by(id: agent_id)
    agent&.materialize!
  end

  private

  def flatten_steps(steps, depth:, seen: Set.new, prefix: nil)
    steps.flat_map do |s|
      if s["type"] == "workflow"
        expand_sub_workflow(s, depth: depth, seen: seen, prefix: prefix)
      else
        step = prefix ? s.merge("name" => "#{prefix}_#{s["name"]}") : s
        [step]
      end
    end
  end

  def expand_sub_workflow(step, depth:, seen:, prefix:)
    raise "Sub-workflow nesting too deep (max #{MAX_DEPTH})" if depth >= MAX_DEPTH

    wf_id = step["workflow_id"]
    raise "Circular workflow reference: #{wf_id}" if seen.include?(wf_id)

    sub_wf = WorkflowDefinition.find_by(id: wf_id)
    return [] unless sub_wf

    sub_prefix = [prefix, step["name"]].compact.join("_")
    sub_steps = sub_wf.drawflow_data["steps"] || []
    flatten_steps(sub_steps, depth: depth + 1, seen: seen | [wf_id], prefix: sub_prefix)
  end
end
