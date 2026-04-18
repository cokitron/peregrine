# Ticket 2: KiroNode

## Goal
Implement the `KiroNode` class that invokes `kiro-cli chat --no-interactive`
and captures its output.

## File
- `lib/kiro_flow/nodes/kiro_node.rb`

## Invocation Pattern

```bash
kiro-cli chat --no-interactive --trust-all-tools --agent <agent_name> --wrap never "<prompt>"
```

## Class Design

```ruby
class KiroFlow::KiroNode < KiroFlow::Node
  # opts:
  #   prompt:  String template with {{name}} placeholders
  #   agent:   String agent name (optional, uses default if omitted)
  #   model:   String model name (optional)
  #   trust:   Array of tool names, or :all (default :all)
  #   timeout: Integer seconds (default 120)

  def execute(context)
    prompt = context.interpolate(opts[:prompt])
    cmd = build_command(prompt)
    stdout, stderr, status = Open3.capture3(cmd)
    raise "KiroNode #{name} failed: #{stderr}" unless status.success?
    stdout.strip
  end
end
```

## Command Building
- Base: `kiro-cli chat --no-interactive --wrap never`
- If `opts[:trust]` is `:all` → add `--trust-all-tools`
- If `opts[:trust]` is an Array → add `--trust-tools=tool1,tool2`
- If `opts[:agent]` → add `--agent <name>`
- If `opts[:model]` → add `--model <name>`
- Prompt is the positional argument, properly shell-escaped

## Input Context
- The prompt template can reference any upstream node output via `{{node_name}}`
- For large context, the prompt should reference the .txt file path instead:
  `"Read the file at {{step1_file}} and summarize it"`
- Context provides both `ctx[:name]` (content) and `ctx.file_for(:name)` (path)

## Output
- Raw STDOUT from kiro-cli, stripped of leading/trailing whitespace
- Stored in context and persisted to `<run_dir>/<node_name>.txt`

## Error Handling
- Non-zero exit code → raise with stderr content
- Timeout via `Timeout.timeout(opts[:timeout])` wrapping the Open3 call
- Log command (without prompt content) for debugging

## Acceptance Criteria
- [ ] KiroNode builds correct CLI command string from opts
- [ ] Shell-escapes prompt content properly
- [ ] Captures stdout on success
- [ ] Raises on non-zero exit with stderr message
- [ ] Respects timeout setting
- [ ] Works with and without --agent flag
