# KiroFlow — Project Overview

## What
A Ruby script-based workflow engine that chains `kiro-cli` calls in an n8n-style DAG pattern.
Each "node" performs a task (Kiro AI call, shell command, Ruby block, or conditional branch)
and passes output to downstream nodes via .txt files optimized for Kiro context intake.

## Key Constraints
- Max 3 concurrent parallel nodes
- File-based persistence: all node I/O stored as .txt files in `./kiro_flow_runs/<run_id>/`
- Agent configs auto-generated with MCP server support
- Script-first approach (no gem packaging yet)
- Invocation: `kiro-cli chat --no-interactive --trust-all-tools --agent <name> --wrap never "<prompt>"`

## Node Types
- KiroNode: invokes kiro-cli chat
- ShellNode: runs a shell command
- RubyNode: executes a Ruby block
- ConditionalNode: routes to branches based on output

## Data Flow
- Each node reads upstream .txt files as context
- Each node writes its output to `<run_dir>/<node_name>.txt`
- Prompts use `{{node_name}}` template syntax to reference upstream outputs
- .txt files use a Kiro-optimized format with clear section headers

## Tickets
1. Core DSL & Context — tickets/01-core-dsl.md
2. KiroNode — tickets/02-kiro-node.md
3. ShellNode & RubyNode — tickets/03-shell-ruby-nodes.md
4. ConditionalNode — tickets/04-conditional-node.md
5. Runner (parallel) — tickets/05-runner.md
6. File persistence — tickets/06-persistence.md
7. AgentBuilder + MCP — tickets/07-agent-builder.md
8. Example + test — tickets/08-example.md
