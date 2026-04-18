# Ticket 4: ConditionalNode

## Goal
Implement a node that evaluates a condition and signals which branch to take,
enabling if/else routing in workflows.

## File
- `lib/kiro_flow/nodes/conditional_node.rb`

## Design

```ruby
class KiroFlow::ConditionalNode < KiroFlow::Node
  # opts:
  #   condition: Proc that receives (context) and returns truthy/falsy

  def execute(context)
    result = opts[:condition].call(context)
    result ? "true" : "false"
  end
end
```

## How Branching Works

The ConditionalNode itself just outputs "true" or "false".
Downstream nodes use `only_if` or `unless` guards to decide whether to run:

```ruby
flow = KiroFlow::Workflow.define("branching") do
  node :check, type: :conditional,
    condition: ->(ctx) { ctx[:tests].include?("0 failures") }

  node :deploy, type: :shell, command: "deploy.sh",
    only_if: :check          # runs when check == "true"

  node :alert, type: :kiro, prompt: "Tests failed: {{tests}}",
    unless_node: :check       # runs when check == "false"

  connect :check >> :deploy
  connect :check >> :alert
end
```

### Node-level guards (on base Node class)
- `opts[:only_if]` — Symbol node name; skip this node unless that node's output == "true"
- `opts[:unless_node]` — Symbol node name; skip this node if that node's output == "true"
- When skipped, node output is `nil` and downstream nodes that depend on it are also skipped

### Runner integration
- Before executing a node, Runner checks guards against context
- Skipped nodes store `nil` in context and are marked as `:skipped` in run state

## Acceptance Criteria
- [ ] ConditionalNode evaluates proc and returns "true"/"false"
- [ ] `only_if` guard prevents execution when condition is "false"
- [ ] `unless_node` guard prevents execution when condition is "true"
- [ ] Skipped nodes propagate — downstream of skipped nodes also skip
- [ ] Guards reference context values by node name
