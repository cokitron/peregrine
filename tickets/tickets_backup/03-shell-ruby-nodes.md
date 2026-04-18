# Ticket 3: ShellNode & RubyNode

## Goal
Implement two simple node types for non-Kiro tasks within workflows.

## Files
- `lib/kiro_flow/nodes/shell_node.rb`
- `lib/kiro_flow/nodes/ruby_node.rb`

## ShellNode

Runs a shell command via Open3, captures stdout.

```ruby
class KiroFlow::ShellNode < KiroFlow::Node
  # opts:
  #   command: String shell command with {{name}} placeholders
  #   timeout: Integer seconds (default 60)

  def execute(context)
    cmd = context.interpolate(opts[:command])
    stdout, stderr, status = Open3.capture3(cmd)
    raise "ShellNode #{name} failed: #{stderr}" unless status.success?
    stdout.strip
  end
end
```

### Features
- Command string supports `{{name}}` interpolation from context
- Timeout wrapping
- Returns stdout stripped

## RubyNode

Executes a Ruby callable (Proc/lambda) with context access.

```ruby
class KiroFlow::RubyNode < KiroFlow::Node
  # opts:
  #   callable: Proc that receives (context) and returns a String

  def execute(context)
    result = opts[:callable].call(context)
    result.to_s
  end
end
```

### DSL usage

```ruby
node :transform, type: :ruby,
  callable: ->(ctx) {
    data = JSON.parse(ctx[:fetch_data])
    data.select { |r| r["status"] == "active" }.to_json
  }
```

### Features
- Callable receives full context object
- Must return a String (or something that responds to `.to_s`)
- Errors propagate naturally (no special wrapping needed)

## Acceptance Criteria
- [ ] ShellNode executes command and captures stdout
- [ ] ShellNode interpolates {{name}} in command string
- [ ] ShellNode raises on non-zero exit
- [ ] RubyNode calls the proc with context
- [ ] RubyNode returns string output
