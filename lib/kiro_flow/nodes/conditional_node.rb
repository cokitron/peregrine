module KiroFlow
  class ConditionalNode < Node
    def execute(context)
      opts.fetch(:condition).call(context) ? "true" : "false"
    end
  end
end
