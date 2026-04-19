<p align="center">
  <img src="app/assets/images/logo.svg" alt="Peregrine" width="200" height="200">
</p>

<h1 align="center">Peregrine</h1>

<p align="center">
  A visual workflow engine for chaining AI calls into multi-step pipelines.<br>
  Build, execute, and audit AI workflows through a web UI or a Ruby DSL.
</p>

<p align="center">
  <img src="https://github.com/your-org/peregrine/actions/workflows/ci.yml/badge.svg" alt="CI">
  <img src="https://img.shields.io/badge/ruby-3.4.8-red" alt="Ruby 3.4.8">
  <img src="https://img.shields.io/badge/rails-8.1.3-red" alt="Rails 8.1.3">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
</p>

---

## What is Peregrine?

Peregrine lets you chain `kiro-cli` AI calls, shell commands, Ruby code, and conditional gates into repeatable workflows. Think n8n or Zapier, but for AI-powered developer pipelines that run locally.

**Use it to:**
- Break complex AI tasks into composable, debuggable steps
- Build code review, feature planning, or refactoring pipelines
- Audit every run — each node's output is persisted to disk
- Run workflows from the web UI or the command line

## Features

- **Visual editor** — drag-and-drop card flow built with Stimulus. No external graph library.
- **Four node types** — Kiro (AI), Shell, Ruby, and Gate (conditional branching).
- **Template syntax** — reference upstream outputs with `{{node_name}}` in any prompt or command.
- **Parallel execution** — fan-out groups run concurrently (max 3 threads), then rejoin.
- **Live status** — Action Cable broadcasts run progress to the browser in real time.
- **File-based audit trail** — every run produces timestamped `.txt` files optimized for AI context intake.
- **Standalone engine** — `lib/kiro_flow/` is pure Ruby, usable without Rails.

## Prerequisites

- **Ruby** 3.4.8+
- **PostgreSQL** 14+
- **Node.js** 20+ (for Tailwind CSS build only)
- **kiro-cli** — installed and available on `$PATH` ([install instructions](https://github.com/aws/kiro))

## Getting Started

```bash
# Clone the repo
git clone https://github.com/your-org/peregrine.git
cd peregrine

# Install dependencies
bundle install
npm install

# Copy environment config
cp .env.example .env
# Edit .env with your DATABASE_URL and RAILS_MASTER_KEY

# Set up the database
bin/rails db:prepare

# Start the dev server (Rails + Tailwind watcher + Solid Queue)
bin/dev
```

Visit [http://localhost:3000](http://localhost:3000) to open the workflow editor.

## Usage

### Web UI

1. Click **New Workflow** to create a workflow.
2. Add steps using the toolbar: ⚡ Kiro, ▶ Shell, ◆ Ruby, ◇ Gate.
3. Configure each step's name and prompt/command/code.
4. Reference upstream outputs with `{{step_name}}` in any field.
5. Click **▶ Ejecutar** to run. Progress streams live via WebSocket.
6. View run history and per-node output on the runs page.

### Command Line

The KiroFlow engine works standalone without Rails:

```ruby
require_relative "lib/kiro_flow"

flow = KiroFlow.chain("feature_build") do
  ask  :analyze,   "Analyze this feature request: {{input}}"
  ask  :plan,      "Write an implementation plan based on: {{analyze}}"
  gate :ready,     ->(ctx) { ctx[:plan].to_s.length > 50 }
  ask  :implement, "Implement this plan: {{plan}}"
  sh   :lint,      "rubocop {{implement_file}}"
  step :summary,   ->(ctx) { "Done: #{ctx[:implement].to_s.lines.count} lines" }
end

result = flow.run(input: "Add a health check endpoint")
puts result[:summary]
```

Run the included examples:

```bash
ruby examples/kiro_chain.rb "Add input validation to the registration form"
ruby examples/code_review_flow.rb
```

### DSL Reference

| Method | Node Type | Description |
|--------|-----------|-------------|
| `ask(name, prompt)` | Kiro | Invokes `kiro-cli chat` with the given prompt |
| `sh(name, command)` | Shell | Runs a shell command via `Open3.capture3` |
| `step(name, callable)` | Ruby | Executes a Ruby proc with access to `ctx` |
| `gate(name, condition)` | Gate | Evaluates a condition; downstream steps auto-skip if false |
| `parallel { ... }` | Group | Nodes inside run concurrently, then rejoin |

### Template Variables

- `{{node_name}}` — inline content from an upstream node's output
- `{{node_name_file}}` — file path to the node's output (useful for shell commands to avoid escaping issues)
- `{{input}}` — the initial input text provided when executing the workflow

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Browser (Stimulus + Tailwind CSS v4 + Flowbite)        │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐          │
│  │ ⚡ Kiro │ ──▶ │ ▶ Shell │ ──▶ │ ◆ Ruby  │          │
│  └─────────┘     └─────────┘     └─────────┘          │
│       ↕ auto-save steps JSON via fetch                  │
├─────────────────────────────────────────────────────────┤
│  Rails 8.1 Backend                                      │
│  WorkflowDefinition → DrawflowConverter → Runner        │
│  Solid Queue (jobs) · Solid Cable (live status)         │
├─────────────────────────────────────────────────────────┤
│  KiroFlow Engine (lib/kiro_flow/)                       │
│  Pure Ruby · No Rails dependency · File-based output    │
└─────────────────────────────────────────────────────────┘
```

### Execution Flow

1. User creates a workflow in the editor (or via DSL).
2. Clicking **Execute** creates a `WorkflowRun` and enqueues an `ExecuteWorkflowJob`.
3. The job converts the steps JSON into a `KiroFlow::Workflow` and runs it.
4. Each node executes in topological order (with parallel fan-out where configured).
5. Outputs are stored in context and persisted to `~/.kiro_flow/runs/<timestamp>/`.
6. Status updates broadcast to the browser via Action Cable.

### Persistence Format

Every run creates a timestamped directory. Each node produces a `.txt` file:

```
~/.kiro_flow/runs/20260418_123456_abc123/
├── _manifest.txt      # Run metadata + node summary
├── analyze.txt        # Output of :analyze node
├── plan.txt           # Output of :plan node
└── implement.txt      # Output of :implement node
```

## Project Structure

```
peregrine/
├── app/
│   ├── controllers/        # WorkflowsController, WorkflowRunsController
│   ├── models/             # WorkflowDefinition, WorkflowRun, Agent
│   ├── jobs/               # ExecuteWorkflowJob (Solid Queue)
│   ├── channels/           # WorkflowRunChannel (Solid Cable)
│   ├── services/           # DrawflowConverter
│   ├── components/         # ViewComponent UI components
│   ├── javascript/         # Stimulus controllers
│   └── views/              # ERB templates
├── lib/
│   └── kiro_flow/          # Standalone workflow engine
│       ├── context.rb      # Thread-safe data store
│       ├── node.rb         # Base class + factory
│       ├── nodes/          # KiroNode, ShellNode, RubyNode, ConditionalNode
│       ├── runner.rb       # Parallel executor
│       ├── persistence.rb  # .txt file I/O
│       ├── workflow.rb     # DAG DSL
│       └── chain_builder.rb # Simplified linear DSL
├── examples/               # Runnable workflow scripts
├── tickets/                # Implementation specs
├── spec/                   # KiroFlow engine tests
└── test/                   # Rails tests (Minitest + fixtures)
```

## Running Tests

```bash
# Rails tests (models, controllers, system)
bin/rails test
bin/rails test:system

# KiroFlow engine tests
ruby -Ilib spec/kiro_flow_spec.rb

# Linting
bin/rubocop

# Security scans
bin/brakeman --no-pager
bin/bundler-audit
```

All checks run automatically on pull requests via GitHub Actions.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Ruby 3.4.8 (YJIT, Prism parser) |
| Framework | Rails 8.1.3 |
| Database | PostgreSQL (UUID primary keys, jsonb columns) |
| Background Jobs | Solid Queue |
| WebSockets | Solid Cable |
| Caching | Solid Cache |
| Frontend | Hotwire (Turbo + Stimulus) |
| CSS | Tailwind CSS v4 + Flowbite |
| Components | ViewComponent |
| Assets | Propshaft + Importmap |
| Deployment | Kamal 2 |
| AI Runtime | kiro-cli (`--no-interactive` mode) |

## Deployment

Peregrine ships with a Kamal 2 configuration for container-based deployment:

```bash
# Set up secrets in .kamal/secrets
# Configure your server in config/deploy.yml

kamal setup    # First deploy
kamal deploy   # Subsequent deploys
kamal rollback # Roll back if needed
```

See `config/deploy.yml` and the [Kamal docs](https://kamal-deploy.org) for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Write tests for your changes.
4. Ensure all checks pass (`bin/rails test && bin/rubocop && bin/brakeman --no-pager`).
5. Open a pull request with a clear description of what changed and why.

### Development Guidelines

- **Spanish domain, English infrastructure** — model attributes and user-facing text are in Spanish; code, comments, and infrastructure are in English.
- **Minitest + fixtures** for Rails tests; RSpec-style specs for the KiroFlow engine.
- **ViewComponent** for reusable UI elements.
- Follow the existing code style enforced by RuboCop.

## License

This project is licensed under the [MIT License](LICENSE).

## Acknowledgments

Built with [kiro-cli](https://github.com/aws/kiro), [Rails](https://rubyonrails.org), [Hotwire](https://hotwired.dev), [Tailwind CSS](https://tailwindcss.com), and [Flowbite](https://flowbite.com).
