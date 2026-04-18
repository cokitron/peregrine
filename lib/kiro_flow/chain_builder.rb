module KiroFlow
  # Sugar DSL for linear workflows. Auto-connects nodes sequentially.
  # Use KiroFlow.chain for simple pipelines, KiroFlow::Workflow.define for complex DAGs.
  def self.chain(name, &block)
    builder = ChainBuilder.new(name)
    builder.instance_eval(&block)
    builder.to_workflow
  end

  class ChainBuilder
    def initialize(name)
      @name = name
      @steps = []
      @branches = {}
    end

    # KiroNode — ask Kiro a question
    def ask(name, prompt, **opts)
      add(name, type: :kiro, prompt: prompt, **opts)
    end

    # ShellNode — run a command
    def sh(name, command, **opts)
      add(name, type: :shell, command: command, **opts)
    end

    # RubyNode — run a block. Block receives context.
    def step(name, callable = nil, &block)
      add(name, type: :ruby, callable: callable || block)
    end

    # ConditionalNode — next nodes auto-get only_if guard.
    # Pass a proc/lambda. Receives context.
    def gate(name, condition = nil, &block)
      add(name, type: :conditional, condition: condition || block)
      @branches[name] = true
    end

    # Parallel group — nodes inside run concurrently, then rejoin.
    def parallel(&block)
      group = ParallelGroup.new
      group.instance_eval(&block)
      @steps << { parallel: group.steps }
    end

    def to_workflow
      Workflow.define(@name) do |wf_unused|
        # We need access to @steps and @branches from the builder,
        # but instance_eval changes self. So we build outside the DSL.
      end.tap { |wf| wire(wf) }
    end

    private

    def add(name, **opts)
      @steps << { name: name.to_sym, **opts }
    end

    def wire(wf)
      prev = nil
      active_gate = nil

      @steps.each do |s|
        if s[:parallel]
          wire_parallel(wf, s[:parallel], prev).then { |join_name| prev = join_name }
          active_gate = nil
          next
        end

        node_opts = s.except(:name)
        node_opts[:only_if] = active_gate if active_gate && s[:type] != :conditional
        wf.node(s[:name], **node_opts)
        wf.connect(prev >> s[:name]) if prev
        active_gate = @branches.key?(s[:name]) ? s[:name] : active_gate
        prev = s[:name]
      end
    end

    def wire_parallel(wf, steps, prev)
      steps.each do |s|
        wf.node(s[:name], **s.except(:name))
        wf.connect(prev >> s[:name]) if prev
      end
      # Create a join node that waits for all parallel steps
      join_name = :"_join_#{steps.map { it[:name] }.join('_')}"
      wf.node(join_name, type: :ruby, callable: ->(_) { "joined" })
      steps.each { wf.connect(it[:name] >> join_name) }
      join_name
    end
  end

  class ParallelGroup
    attr_reader :steps

    def initialize
      @steps = []
    end

    def ask(name, prompt, **opts)
      @steps << { name: name.to_sym, type: :kiro, prompt: prompt, **opts }
    end

    def sh(name, command, **opts)
      @steps << { name: name.to_sym, type: :shell, command: command, **opts }
    end

    def step(name, callable = nil, &block)
      @steps << { name: name.to_sym, type: :ruby, callable: callable || block }
    end
  end
end
