module KiroFlow
  class Node
    attr_reader :name, :opts

    def initialize(name, **opts)
      @name = name.to_sym
      @opts = opts
    end

    def execute(_context) = raise NotImplementedError, "#{self.class}#execute not implemented"

    def only_if = opts[:only_if]
    def unless_node = opts[:unless_node]

    def self.build(name, type:, **opts)
      case type.to_sym
      when :kiro        then KiroFlow::KiroNode.new(name, **opts)
      when :shell       then KiroFlow::ShellNode.new(name, **opts)
      when :ruby        then KiroFlow::RubyNode.new(name, **opts)
      when :conditional then KiroFlow::ConditionalNode.new(name, **opts)
      else raise ArgumentError, "Unknown node type: #{type}"
      end
    end
  end
end
