# Ticket 1: Core DSL & Context

## Goal
Implement the foundational classes: `Workflow` (DSL for defining node graphs),
`Context` (data carrier between nodes), and `Node` (base class).

## Files
- `lib/kiro_flow/workflow.rb`
- `lib/kiro_flow/context.rb`
- `lib/kiro_flow/node.rb`

## Workflow DSL

```ruby
flow = KiroFlow::Workflow.define("my_flow") do
  node :step1, type: :kiro, prompt: "Analyze {{input}}"
  node :step2, type: :shell, command: "echo done"
  connect :step1 >> :step2
end
```

### Workflow class responsibilities
- `define(name, &block)` — class method, evaluates DSL block, returns Workflow instance
- Stores nodes as a Hash `{ name => Node }`
- Stores edges as adjacency list `{ name => [downstream_names] }`
- `#nodes` — returns all nodes
- `#edges` — returns adjacency list
- `#roots` — nodes with no incoming edges (entry points)
- `#downstream(node_name)` — returns array of downstream node names
- `#upstream(node_name)` — returns array of upstream node names

### DSL methods (evaluated inside block)
- `node(name, type:, **opts)` — registers a node; type determines subclass
- `connect(*chains)` — accepts chain expressions built via `Symbol#>>` operator

### Symbol#>> monkey-patch
- `Symbol#>>(other)` returns a `KiroFlow::Chain` object
- `Chain#>>(other)` appends to the chain
- `Chain#pairs` returns `[[:a, :b], [:b, :c]]` edge pairs
- Keep the monkey-patch minimal and namespaced

## Context

```ruby
ctx = KiroFlow::Context.new(run_dir: "./kiro_flow_runs/abc123")
ctx[:step1] = "output text"
ctx[:step1] # => "output text"
ctx.interpolate("Result: {{step1}}") # => "Result: output text"
```

### Context responsibilities
- Hash-like storage keyed by node name (Symbol)
- `#interpolate(template)` — replaces `{{name}}` with stored values
- `#run_dir` — path to the run directory
- `#run_id` — unique identifier for this run
- Read/write delegated to persistence layer (Ticket 6), but Context holds in-memory state

## Node (base)

```ruby
class KiroFlow::Node
  attr_reader :name, :opts
  def execute(context) = raise NotImplementedError
end
```

### Node responsibilities
- `name` — Symbol identifier
- `opts` — Hash of configuration (prompt, command, agent, etc.)
- `#execute(context)` — runs the node, returns output string
- Subclasses: KiroNode, ShellNode, RubyNode, ConditionalNode (separate tickets)

### Factory
- `Node.build(name, type:, **opts)` — returns the correct subclass instance based on `type`

## Acceptance Criteria
- [ ] `Workflow.define` parses DSL block and builds node/edge graph
- [ ] `Symbol#>>` chaining works: `:a >> :b >> :c` produces correct edge pairs
- [ ] `Context#interpolate` replaces all `{{name}}` tokens
- [ ] `Node.build` returns correct subclass for `:kiro`, `:shell`, `:ruby`, `:conditional`
- [ ] Workflow can identify root nodes (no upstream)
