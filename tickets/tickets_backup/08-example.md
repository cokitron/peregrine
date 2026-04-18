# Ticket 8: Example Workflow + Integration Test

## Goal
Create a working example workflow and a test suite that validates
the entire pipeline end-to-end.

## Files
- `examples/code_review_flow.rb`
- `spec/workflow_spec.rb`
- `spec/runner_spec.rb`
- `spec/node_spec.rb`

## Example: Code Review Pipeline

```ruby
#!/usr/bin/env ruby
require_relative "../lib/kiro_flow"

flow = KiroFlow::Workflow.define("code_review") do
  # Define a specialized agent
  agent :reviewer do
    description "Analyzes code for issues"
    tools ["fs_read", "execute_bash"]
    mcp_server "git", command: "mcp-server-git", args: ["--repository", "."]
  end

  # Nodes
  node :diff, type: :shell,
    command: "git diff HEAD~1"

  node :analyze, type: :kiro, agent: :reviewer,
    prompt: "Analyze this git diff for bugs, security issues, and style problems:\n\n{{diff}}"

  node :tests, type: :shell,
    command: "bundle exec rspec --format json 2>&1 || true"

  node :check, type: :conditional,
    condition: ->(ctx) { !ctx[:tests].include?('"failure_count":0') }

  node :summary, type: :kiro,
    prompt: "Create a PR review summary.\nCode analysis: {{analyze}}\nTest results: {{tests}}"

  # Graph: diff and tests run in parallel, then analyze, then check+summary
  connect :diff >> :analyze >> :summary
  connect :tests >> :check
  connect :tests >> :summary
end

result = flow.run
puts "Run completed: #{result.run_dir}"
puts "Summary:\n#{result[:summary]}"
```

## Unit Tests (minitest)

### spec/node_spec.rb
- ShellNode executes `echo hello` and returns "hello"
- RubyNode executes lambda and returns result
- ConditionalNode returns "true"/"false" based on proc
- KiroNode builds correct command string (mock Open3, don't call real kiro-cli)

### spec/workflow_spec.rb
- DSL parses nodes and edges correctly
- `Symbol#>>` chaining produces correct pairs
- Roots identified correctly
- Upstream/downstream queries work

### spec/runner_spec.rb
- Sequential execution respects order
- Parallel execution runs independent nodes concurrently
- Guards (only_if/unless_node) skip correctly
- Failed nodes cause downstream skips
- Max 3 concurrent threads enforced

### Running tests
```bash
ruby -Ilib -Ispec spec/workflow_spec.rb
# or
bundle exec ruby -Ilib -Ispec spec/workflow_spec.rb
```

## Integration Test (requires kiro-cli installed)

```ruby
# spec/integration_spec.rb — run manually, not in CI
flow = KiroFlow::Workflow.define("smoke_test") do
  node :greet, type: :kiro,
    prompt: "Reply with exactly: HELLO_KIROFLOW"

  node :check, type: :ruby,
    callable: ->(ctx) { ctx[:greet].include?("HELLO_KIROFLOW") ? "pass" : "fail" }

  connect :greet >> :check
end

result = flow.run
assert_equal "pass", result[:check]
```

## Acceptance Criteria
- [ ] Example workflow file runs without errors (with kiro-cli available)
- [ ] Unit tests pass for all node types
- [ ] Workflow DSL tests pass
- [ ] Runner tests validate parallel execution and guards
- [ ] Run directory created with all .txt output files
- [ ] Manifest file generated correctly
