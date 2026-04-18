# Ticket 7: AgentBuilder with MCP Server Support

## Goal
Auto-generate `.kiro/agents/<name>.json` config files for KiroNodes,
including MCP server definitions, tool permissions, and hooks.

## File
- `lib/kiro_flow/agent_builder.rb`

## Why
Each KiroNode can use a specialized agent with:
- Specific tool permissions (only fs_read, or full access)
- MCP servers for external integrations (databases, APIs, git)
- Hooks for pre/post processing
- Custom system prompt via resources

## Agent Config Format (from Kiro docs)

```json
{
  "description": "Code review agent for KiroFlow",
  "tools": ["fs_read", "fs_write", "execute_bash", "@git/git_status"],
  "allowedTools": ["fs_read", "@git/git_status"],
  "toolsSettings": {
    "execute_bash": {
      "autoAllowReadonly": true
    }
  },
  "resources": [
    "file://README.md"
  ],
  "mcpServers": {
    "git": {
      "command": "mcp-server-git",
      "args": ["--repository", "."],
      "timeout": 10000
    }
  },
  "hooks": {
    "postToolUse": [
      {
        "command": "ruby",
        "args": ["hooks/log_tool_use.rb"],
        "matcher": "*",
        "timeout_ms": 5000
      }
    ]
  }
}
```

## AgentBuilder API

```ruby
agent = KiroFlow::AgentBuilder.new("code-reviewer")
  .description("Reviews code changes for issues")
  .tools(["fs_read", "execute_bash"])
  .allow_tools(["fs_read"])
  .mcp_server("git",
    command: "mcp-server-git",
    args: ["--repository", "."],
    timeout: 10000
  )
  .resource("file://README.md")
  .hook(:postToolUse,
    command: "ruby",
    args: ["hooks/log.rb"],
    matcher: "*"
  )
  .build!  # writes to .kiro/agents/code-reviewer.json
```

### Methods
- `#description(text)` — sets agent description
- `#tools(list)` — sets available tools
- `#allow_tools(list)` — sets auto-approved tools
- `#tool_settings(tool_name, settings_hash)` — configures a specific tool
- `#mcp_server(name, command:, args:, timeout:, env:)` — adds an MCP server
- `#resource(path)` — adds a resource file
- `#hook(event, command:, args:, matcher:, timeout_ms:)` — adds a hook
- `#build!` — writes JSON to `.kiro/agents/<name>.json`, returns path
- `#to_h` — returns the config as a Hash (for inspection)

## Workflow Integration

In the DSL, agents can be defined inline:

```ruby
flow = KiroFlow::Workflow.define("review") do
  agent :reviewer do
    description "Code review specialist"
    tools ["fs_read", "execute_bash"]
    mcp_server "git", command: "mcp-server-git", args: ["--repository", "."]
  end

  node :review, type: :kiro, agent: :reviewer,
    prompt: "Review the changes in {{input}}"
end
```

The `agent` DSL block creates the agent config file before the workflow runs.

## Cleanup
- `AgentBuilder.cleanup(name)` — removes the generated agent file
- Runner calls cleanup after workflow completes (optional, configurable)

## Acceptance Criteria
- [ ] Generates valid .kiro/agents/<name>.json
- [ ] Supports MCP server definitions
- [ ] Supports hooks (all event types)
- [ ] Supports tool permissions and settings
- [ ] Supports resources
- [ ] DSL `agent` block works inside workflow definition
- [ ] Generated config matches Kiro CLI expected format
