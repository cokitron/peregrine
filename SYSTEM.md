# Flight Control

A visual workflow engine for chaining `kiro-cli` AI calls. Build multi-step AI pipelines through a web UI or Ruby DSL, execute them locally, and audit every run.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Browser (Stimulus + Tailwind + Kreoz Design System)    │
│                                                         │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐          │
│  │ ⚡ Kiro │ ──▶ │ ▶ Shell │ ──▶ │ ◆ Ruby  │          │
│  └─────────┘     └─────────┘     └─────────┘          │
│       ↕ auto-save steps JSON via fetch                  │
├─────────────────────────────────────────────────────────┤
│  Rails 8.1 Backend                                      │
│                                                         │
│  WorkflowDefinition (steps JSON in jsonb column)        │
│  WorkflowRun (status, node_states, run_dir)             │
│  DrawflowConverter → KiroFlow.chain DSL → Runner        │
│  Solid Queue → ExecuteWorkflowJob                       │
│  Solid Cable → WorkflowRunChannel (live status)         │
└─────────────────────────────────────────────────────────┘
│  KiroFlow Engine (lib/kiro_flow/)                        │
│                                                         │
│  Invokes: kiro-cli chat --no-interactive                │
│           --trust-all-tools --wrap never "prompt"        │
│  Output: ~/.kiro_flow/runs/<timestamp>/*.txt             │
└─────────────────────────────────────────────────────────┘
```

## How It Works

### 1. Visual Editor (Browser)

The editor is a simple linear card flow built with Stimulus. No external graph library — just HTML cards connected by arrows.

**Adding steps:** Click one of the toolbar buttons (⚡ Kiro, ▶ Shell, ◆ Ruby, ◇ Gate) to append a step to the pipeline.

**Configuring steps:** Each card has:
- **Name** — identifier used for `{{name}}` references
- **Type** — determines what the step does
- **Config field** — depends on type (prompt, command, code, or condition)

**Auto-save:** Every change triggers a debounced (600ms) PATCH request that saves the steps array as JSON to the `drawflow_data` jsonb column on `WorkflowDefinition`.

**Executing:** Click "▶ Ejecutar" to queue a background job that runs the workflow.

### 2. Node Types

| Type | Color | What it does | Config field |
|------|-------|-------------|--------------|
| **Kiro** | Green | Invokes `kiro-cli chat --no-interactive` with the prompt | `prompt` (textarea) |
| **Shell** | Amber | Runs a shell command via `Open3.capture3` | `command` (text input) |
| **Ruby** | Purple | Evaluates a Ruby expression with access to `ctx` | `code` (textarea) |
| **Gate** | Red | Evaluates a condition; downstream steps auto-skip if false | `condition` (text input) |

### 3. Data Flow Between Steps

Steps execute sequentially. Each step's output is stored in the context under its name. Downstream steps reference upstream outputs using `{{name}}` template syntax:

```
Step 1 (name: "analyze")
  prompt: "Analyze this feature: {{input}}"
  → output stored as ctx[:analyze]

Step 2 (name: "plan")  
  prompt: "Write a plan based on: {{analyze}}"
  → output stored as ctx[:plan]

Step 3 (name: "implement")
  prompt: "Implement this plan: {{plan}}"
  → output stored as ctx[:implement]
```

The special `{{input}}` references the initial input text provided when executing the workflow.

For shell nodes, use `{{name_file}}` to reference the file path instead of inline content (avoids shell escaping issues with multi-line AI output).

### 4. Execution Pipeline

```
User clicks "Ejecutar"
    │
    ▼
WorkflowsController#execute
    │ creates WorkflowRun (status: "pending")
    │ enqueues ExecuteWorkflowJob
    ▼
ExecuteWorkflowJob#perform
    │ converts steps JSON → KiroFlow::Workflow via DrawflowConverter
    │ calls KiroFlow::Runner.new(workflow).run
    ▼
KiroFlow::Runner
    │ computes topological order
    │ executes nodes (max 3 parallel threads)
    │ evaluates guards (only_if / unless_node)
    │ stores output in Context + persists to .txt files
    ▼
WorkflowRun updated
    │ status: "completed" or "failed"
    │ node_states: { analyze: "completed", plan: "completed", ... }
    │ run_dir: "~/.kiro_flow/runs/20260418_123456_abc123"
    ▼
ActionCable broadcast → browser updates
```

### 5. KiroFlow Engine (`lib/kiro_flow/`)

The engine is pure Ruby, independent of Rails. It can be used standalone via scripts:

```ruby
require_relative "lib/kiro_flow"

flow = KiroFlow.chain("my_workflow") do
  ask  :analyze,   "Analyze: {{input}}"
  ask  :plan,      "Plan based on: {{analyze}}"
  gate :ready,     ->(ctx) { ctx[:plan].to_s.length > 50 }
  ask  :implement, "Implement: {{plan}}"
  sh   :lint,      "rubocop {{implement_file}}"
  step :summary,   ->(ctx) { "Done: #{ctx[:implement].to_s.lines.count} lines" }
end

result = flow.run(input: "Add a health check endpoint")
puts result[:summary]
```

**DSL methods:**
- `ask(name, prompt)` — KiroNode (invokes kiro-cli)
- `sh(name, command)` — ShellNode (runs shell command)
- `step(name, callable)` — RubyNode (executes a proc)
- `gate(name, condition)` — ConditionalNode (branches; downstream auto-skips if false)
- `parallel { ... }` — fan-out group (nodes inside run concurrently, then rejoin)

### 6. Persistence Format

Every run creates a timestamped directory under `~/.kiro_flow/runs/`. Each node's output is stored as a `.txt` file optimized for Kiro context intake:

```
~/.kiro_flow/runs/20260418_123456_abc123/
├── _manifest.txt          # Run metadata + node summary
├── analyze.txt            # Output of :analyze node
├── plan.txt               # Output of :plan node
├── implement.txt          # Output of :implement node
└── summary.txt            # Output of :summary node
```

Each `.txt` file follows this structure:

```
--- NODE OUTPUT: analyze ---
Status: completed
Duration: 18.3s
Upstream: input
Timestamp: 2026-04-18T12:34:56-06:00

--- CONTENT BEGIN ---
<actual node output here>
--- CONTENT END ---
```

This format uses clear section delimiters so Kiro can easily parse the content when fed back as context in future sessions.

### 7. kiro-cli Integration

Each KiroNode invokes:

```bash
kiro-cli chat --no-interactive --trust-all-tools --wrap never "<prompt>"
```

Key flags:
- `--no-interactive` — runs without expecting user input (headless mode)
- `--trust-all-tools` — auto-approves all tool usage (no interactive prompts)
- `--wrap never` — raw output without line wrapping

The output is captured via `Open3.capture3`, ANSI escape codes are stripped, and the clean text is stored in context + persisted to disk.

### 8. Project Structure

```
flight-control/
├── app/
│   ├── controllers/
│   │   └── workflows_controller.rb      # CRUD + execute action
│   ├── helpers/
│   │   └── workflows_helper.rb          # run_status_dot helper
│   ├── javascript/controllers/
│   │   └── workflow_editor_controller.js # Stimulus card flow editor
│   ├── jobs/
│   │   └── execute_workflow_job.rb       # Solid Queue job
│   ├── channels/
│   │   └── workflow_run_channel.rb       # Action Cable live updates
│   ├── models/
│   │   ├── workflow_definition.rb        # steps JSON in jsonb
│   │   └── workflow_run.rb              # execution state
│   ├── services/
│   │   └── drawflow_converter.rb        # JSON → KiroFlow DSL
│   └── views/workflows/
│       ├── index.html.erb               # workflow cards list
│       └── show.html.erb                # card flow editor
├── lib/
│   ├── kiro_flow.rb                     # engine entrypoint
│   └── kiro_flow/
│       ├── context.rb                   # thread-safe data store
│       ├── node.rb                      # base class + factory
│       ├── nodes/
│       │   ├── kiro_node.rb             # kiro-cli invocation
│       │   ├── shell_node.rb            # shell command
│       │   ├── ruby_node.rb             # ruby proc
│       │   └── conditional_node.rb      # gate/branch
│       ├── persistence.rb               # .txt file I/O
│       ├── workflow.rb                   # DAG DSL (Symbol#>>)
│       ├── runner.rb                    # parallel executor
│       ├── agent_builder.rb             # .kiro/agents/*.json
│       └── chain_builder.rb             # simplified linear DSL
├── spec/
│   └── kiro_flow_spec.rb               # 61 tests, 118 assertions
├── examples/
│   ├── kiro_chain.rb                    # CLI example
│   └── code_review_flow.rb             # multi-step example
├── tickets/                             # implementation specs
└── STEERING.md                          # Ruby 3.4 + Rails 8 reference
```

### 9. Running

```bash
# Start the Rails app (editor UI)
bin/dev

# Visit http://localhost:3000/workflows

# Or run a workflow from the command line
ruby examples/kiro_chain.rb "Add a health check endpoint"

# Run the test suite
ruby -Ilib spec/kiro_flow_spec.rb
```

### 10. Tech Stack

- **Ruby 3.4.8** (Prism parser, YJIT)
- **Rails 8.1.3** (Propshaft, Importmap, Hotwire)
- **PostgreSQL** (UUID primary keys, jsonb columns)
- **Solid Queue** (database-backed job processing)
- **Solid Cable** (database-backed Action Cable)
- **Tailwind CSS v4** + Flowbite (Kreoz design system)
- **ViewComponent** (17 reusable UI components)
- **Stimulus** (workflow editor controller)
- **kiro-cli** (AI execution via `--no-interactive` mode)
