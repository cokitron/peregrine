# Ticket 5: Runner with Parallel Execution

## Goal
Implement the workflow executor that traverses the node graph, respects
dependencies, and runs up to 3 nodes in parallel.

## File
- `lib/kiro_flow/runner.rb`

## Design

```ruby
class KiroFlow::Runner
  MAX_CONCURRENT = 3

  def initialize(workflow)
    @workflow = workflow
  end

  def run(input: nil)
    context = KiroFlow::Context.new(run_dir: generate_run_dir)
    context[:input] = input if input
    execute_graph(context)
    context
  end
end
```

## Execution Algorithm (topological with parallelism)

```
1. Compute in-degree for each node
2. Initialize ready_queue with all nodes where in-degree == 0 (roots)
3. While ready_queue is not empty OR threads are running:
   a. Take up to MAX_CONCURRENT nodes from ready_queue
   b. Execute them in parallel threads
   c. On completion of each node:
      - Store output in context
      - Persist output to .txt file
      - Decrement in-degree of all downstream nodes
      - If any downstream node reaches in-degree 0, add to ready_queue
   d. On failure: mark node as :failed, skip all downstream nodes
4. Return context with all outputs
```

### Thread Safety
- Use `Mutex` for ready_queue and context writes
- Use `Thread` (not Process) for simplicity — kiro-cli calls are I/O bound
- `ThreadPool` of size 3: simple array of threads, join when full

### Run State Tracking
Each node has a state: `:pending`, `:running`, `:completed`, `:failed`, `:skipped`

```ruby
# Accessible after run:
runner.state  # => { step1: :completed, step2: :failed, step3: :skipped }
```

### Guard Evaluation
Before executing a node, check:
1. `only_if` guard → skip if referenced node output != "true"
2. `unless_node` guard → skip if referenced node output == "true"
3. If any upstream node is `:failed` or `:skipped` → skip this node

### Error Handling
- Individual node failures don't crash the whole run
- Failed nodes are recorded with error message in context
- Downstream of failed nodes are skipped
- `runner.success?` returns true only if all non-skipped nodes completed

### Logging
- Print to STDERR: `[KiroFlow] Running :node_name...`
- Print to STDERR: `[KiroFlow] :node_name completed (2.3s)`
- Print to STDERR: `[KiroFlow] :node_name FAILED: <error>`

## Acceptance Criteria
- [ ] Executes nodes in topological order
- [ ] Runs up to 3 nodes in parallel when graph allows
- [ ] Waits for upstream dependencies before running a node
- [ ] Evaluates guards (only_if, unless_node) before execution
- [ ] Skips downstream of failed/skipped nodes
- [ ] Tracks per-node state
- [ ] Thread-safe context writes
- [ ] Logs execution progress to STDERR
