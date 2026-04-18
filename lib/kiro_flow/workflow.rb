module KiroFlow
  class Chain
    attr_reader :symbols

    def initialize(*syms)
      @symbols = syms.map(&:to_sym)
    end

    def >>(other)
      Chain.new(*@symbols, other.is_a?(Chain) ? other.symbols : other)
    end

    def pairs
      @symbols.each_cons(2).to_a
    end
  end
end

class Symbol
  def >>(other)
    KiroFlow::Chain.new(self, other.is_a?(KiroFlow::Chain) ? other.symbols : other)
  end
end

module KiroFlow
  class Workflow
    attr_reader :name, :nodes, :edges, :agents

    def initialize(name)
      @name = name
      @nodes = {}
      @edges = Hash.new { |h, k| h[k] = [] }
      @agents = {}
    end

    def self.define(name, &block)
      wf = new(name)
      wf.instance_eval(&block)
      wf
    end

    def node(name, type:, **opts)
      @nodes[name.to_sym] = Node.build(name, type: type, **opts)
    end

    def agent(name, &block)
      builder = AgentBuilder.new(name.to_s)
      builder.instance_eval(&block)
      @agents[name.to_sym] = builder
    end

    def connect(*chains)
      chains.each do |chain|
        chain.pairs.each { |from, to| @edges[from.to_sym] << to.to_sym unless @edges[from.to_sym].include?(to.to_sym) }
      end
    end

    def roots
      downstream_nodes = @edges.values.flatten.uniq
      @nodes.keys.reject { downstream_nodes.include?(it) }
    end

    def downstream(node_name) = @edges[node_name.to_sym]

    def upstream(node_name)
      target = node_name.to_sym
      @edges.each_with_object([]) { |(from, tos), acc| acc << from if tos.include?(target) }
    end

    def run(input: nil)
      Runner.new(self).run(input: input)
    end
  end
end
