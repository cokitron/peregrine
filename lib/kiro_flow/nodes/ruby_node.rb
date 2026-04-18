module KiroFlow
  class RubyNode < Node
    def execute(context)
      opts.fetch(:callable).call(context).to_s
    end
  end
end
