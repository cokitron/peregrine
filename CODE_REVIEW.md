# Flight Control — Code Review Report

**Date:** 2026-04-18
**Reviewer:** Kiro (automated, against Kreoz steering document — 21 lenses)
**Scope:** Full codebase review of the Flight Control visual workflow engine

---

## Executive Summary

Flight Control is a Rails 8.1 application that orchestrates AI agent workflows via a visual editor (Drawflow) backed by a pure-Ruby DAG execution engine (`KiroFlow`). The codebase is young (single-day build) and functional, but has **2 blockers**, **6 critical**, **8 major**, and several minor findings.

The most urgent issue is a **runner infinite loop bug** (reproduced live) caused by missing cycle-termination logic, plus the use of `eval()` on workflow-defined code without sandboxing.

---

## Blocker Findings

### B1: `eval()` in DrawflowConverter — Remote Code Execution (Lens 1: Security)

**File:** `app/services/drawflow_converter.rb:48-51`

```ruby
wf.node(name, type: :ruby, callable: ->(ctx) { eval(code) })
# ...
wf.node(name, type: :conditional, condition: ->(ctx) { eval(cond) })
```

The `code` and `condition` strings come from `drawflow_data`, which is user-submitted JSON. Even though `sanitize_drawflow_data` allowlists step keys, it does **not** sanitize the *values*. Any user who can create a workflow can execute arbitrary Ruby on the server.

The comment at the top of the file acknowledges this but defers to "trusted-user deployments." Since there is **no authentication** (see B2), every user is untrusted.

**Fix:** Replace `eval` with a safe expression evaluator (e.g., a simple DSL that only allows context lookups and comparisons), or at minimum gate workflow creation behind authentication + authorization.

---

### B2: No Authentication or Authorization (Lens 1: Security)

There is no authentication system. No login, no `has_secure_password`, no session management. Every route is publicly accessible. Combined with B1, this means anyone with network access can execute arbitrary code.

- `ApplicationController` has no `before_action` for auth.
- No Pundit policies exist anywhere.
- `WorkflowRunChannel` streams to anyone who knows a run ID — no subscription auth.

**Fix:** Add authentication before any other work. Even a simple `has_secure_password` + session-based login would close the most critical attack surface.

---

## Critical Findings

### C1: Runner Infinite Loop on Cyclic Workflows (Lens 4: Performance / Lens 6: Anti-Patterns)

**Reproduced on workflow `39e3187d-...`**

**Root cause:** The runner's `enqueue_downstream` method re-enqueues already-processed nodes without any guard:

```ruby
# lib/kiro_flow/runner.rb — enqueue_downstream
@workflow.downstream(node_name).each do |dn|
  should_enqueue = @mutex.synchronize do
    in_degree[dn] -= 1
    in_degree[dn] <= 0
  end
  ready << dn if should_enqueue
end
```

When a cycle exists (gate `on_true` → upstream node → gate), and a node in the cycle is skipped (because an earlier node failed), both nodes in the cycle keep re-enqueuing each other as `:skipped` infinitely. The `in_degree` counter goes negative with no floor, and `<= 0` is always true.

**What happened in the live run:**
1. `shell_6` ✓ → `Code Review` ✓ → `Tend Concerns` ✗ (failed)
2. `Validate Changes` skipped (upstream failed)
3. `Needs more Attention?` skipped (upstream skipped)
4. Gate's `on_true` edge re-enqueues `Validate Changes` → skips → re-enqueues gate → skips → ∞

**Fix:** Add a processed-node guard in `enqueue_downstream`:

```ruby
def enqueue_downstream(node_name, in_degree, ready)
  @workflow.downstream(node_name).each do |dn|
    should_enqueue = @mutex.synchronize do
      next false unless @state[dn] == :pending  # ← guard
      in_degree[dn] -= 1
      in_degree[dn] <= 0
    end
    ready << dn if should_enqueue
  end
end
```

---

### C2: Gate Nodes Don't Wire `only_if` Guards via DrawflowConverter (Lens 6: Anti-Patterns)

**File:** `app/services/drawflow_converter.rb:56-58`

The `ChainBuilder` DSL correctly sets `only_if: gate_name` on nodes downstream of a gate. But `DrawflowConverter` does not — it creates the edge but never sets the guard. This means the gate's `"true"`/`"false"` output is stored in context but **never consulted**. Both `on_true` and `on_false` targets execute unconditionally.

**Fix:** When wiring gate edges, set `only_if` on the `on_true` target and `unless_node` on the `on_false` target:

```ruby
if s["type"] == "gate"
  if s["on_true"].present?
    wf.connect(name >> s["on_true"].to_sym)
    wf.nodes[s["on_true"].to_sym]&.opts&.[]=(:only_if, name)
  end
  if s["on_false"].present?
    wf.connect(name >> s["on_false"].to_sym)
    wf.nodes[s["on_false"].to_sym]&.opts&.[]=(:unless_node, name)  
  end
end
```

---

### C3: Gate Condition Hardcoded to `"true"` (Lens 6: Anti-Patterns)

The workflow's gate node `Needs more Attention?` has `"condition": "true"` — a hardcoded string that always evaluates to true via `eval("true")`. The user's intent was for the gate to evaluate based on the output of `Validate Changes`, but there's no mechanism to do that.

The gate condition should reference the previous node's output, e.g.:
```
ctx[:"Validate Changes"].include?("needs more")
```

But the UI doesn't provide a way to write context-aware conditions. The condition field is a free-text `eval` target with no guidance.

**Fix:** Either provide a structured condition builder in the UI (e.g., "if output of [node] contains [text]"), or document the `ctx[:node_name]` API for gate conditions.

---

### C4: No Model or Controller Tests (Lens 7: Testing)

- `test/models/` — empty
- `test/controllers/` — empty
- `test/system/` — empty

Only `spec/kiro_flow_spec.rb` exists (61 tests for the lib engine). Zero tests for Rails models, controllers, services, jobs, or channels.

**Minimum required:**
- Model validations and associations
- `WorkflowsController` CRUD + execute action
- `DrawflowConverter` edge cases (cycles, missing nodes, malformed data)
- `WorkflowExecutionService` happy path + failure handling
- `ExecuteWorkflowJob` error recovery

---

### C5: WorkflowRun Stuck in `running` Status After Crash (Lens 10: Error Handling)

The workflow run `39e3187d-...` is still `status: "running"` because the Puma process was killed with Ctrl+C. There is no mechanism to detect and recover stale running jobs.

**Fix:** Add a startup task or periodic job that marks stale `running` runs as `failed`:

```ruby
WorkflowRun.where(status: "running")
           .where("updated_at < ?", 10.minutes.ago)
           .update_all(status: "failed", error_message: "Stale run recovered")
```

---

### C6: CSRF Protection Not Explicitly Verified (Lens 1: Security)

`ApplicationController` inherits from `ActionController::Base` which includes CSRF protection by default in Rails 8. The layout includes `<%= csrf_meta_tags %>`. However:

- No explicit `protect_from_forgery` declaration.
- The `update` actions return `head :ok` for JSON — verify Turbo includes CSRF tokens on these requests.
- `WorkflowRunChannel` has no CSRF or auth verification on subscription.

**Severity:** Critical only because there's no auth at all (B2). Once auth is added, verify CSRF is enforced on all state-changing actions.

---

## Major Findings

### M1: N+1 Query in WorkflowsController#index (Lens 4: Performance)

```ruby
# app/views/workflows/index.html.erb calls @workflow.last_run for each card
def last_run = workflow_runs.order(created_at: :desc).first
```

Each workflow card triggers a separate query for `last_run`. With 24 workflows per page, that's 25 queries.

**Fix:** `@workflows = WorkflowDefinition.includes(:workflow_runs).order(...)` or preload only the latest run with a subquery.

---

### M2: `Agent#materialize!` Writes to Filesystem from Model (Lens 6: Anti-Patterns)

**File:** `app/models/agent.rb:5-20`

The `materialize!` method writes files to `.kiro/agents/` and `.kiro/steering/`. This is a side effect in a model — it should be a service object. It also runs during `DrawflowConverter.resolve_agent`, meaning every workflow execution triggers filesystem writes.

---

### M3: Missing `dependent:` on Agent Association (Lens 3: Data Integrity)

```ruby
# app/models/agent.rb
has_many :workflow_definitions, foreign_key: :default_agent_id
```

No `dependent:` declaration. The DB has `on_delete: :nullify` which is correct, but the model should declare `dependent: :nullify` to match and make the behavior explicit in Ruby.

---

### M4: Unbounded Collection in WorkflowsController#show (Lens 4: Performance)

```ruby
@workflows = WorkflowDefinition.where.not(id: @workflow.id).where(is_active: true).order(:nombre)
```

No `.limit()`. If there are thousands of workflows, this loads them all for the sub-workflow dropdown.

---

### M5: No I18n — Hardcoded English Strings (Lens 11: I18n)

All user-facing text is hardcoded in views and controllers:
- `"Workflow created"`, `"Workflow deleted"`, `"Agent deleted"`
- `"New Workflow"`, `"New Agent #{Time.current.strftime('%H:%M')}"`
- Button labels, headings, empty states — all inline English

The steering doc requires Spanish domain with I18n locale files. Currently there's only a default `config/locales/en.yml` with no custom keys.

---

### M6: Missing Database Indexes (Lens 3: Database)

- `workflow_runs.status` — no index. Querying by status (e.g., finding stale `running` runs) will seq-scan.
- `agents` table — no indexes beyond PK. If agent count grows, `Agent.order(:nombre)` and `Agent.find_by(id:)` are fine on PK but `order(:nombre)` has no index.
- `workflow_runs.created_at` — used in `scope :recientes` ordering, no index.

---

### M7: `to_unsafe_h` in WorkflowsController (Lens 1: Security)

```ruby
# app/controllers/workflows_controller.rb
data = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
```

`to_unsafe_h` bypasses strong parameters. The subsequent `slice(*ALLOWED_STEP_KEYS)` mitigates this for top-level keys, but nested values within each step are not sanitized. Combined with `eval()` (B1), this is part of the attack chain.

---

### M8: CSP in Report-Only Mode (Lens 1: Security)

```ruby
config.content_security_policy_report_only = true
```

CSP is configured but not enforced. `script_src` allows `cdn.jsdelivr.net` which is fine for Flowbite, but report-only mode means XSS payloads would still execute.

**Fix:** Switch to enforcing mode once the app is stable.

---

## Minor Findings

### m1: Unfrozen Constants (Lens 13: Concurrency)

```ruby
# app/controllers/workflows_controller.rb
ALLOWED_STEP_KEYS = %w[...].freeze  # ✓ frozen

# app/helpers/workflows_helper.rb
NODE_STYLES = { ... }.freeze  # ✓ frozen, but inner hashes are NOT frozen
```

The inner hashes in `NODE_STYLES` (`{ icon: "⚡", bg: "..." }`) are mutable. Under Puma's threaded model, a thread could theoretically mutate them.

**Fix:** `NODE_STYLES = { ... }.transform_values(&:freeze).freeze`

---

### m2: `password_validation_controller.js` Exists Without Auth (Lens 15: Assets)

A Stimulus controller for password validation exists but there's no authentication system. Dead code.

---

### m3: `hello_controller.js` — Rails Scaffold Leftover (Lens 15: Assets)

Default Rails scaffold file. Should be removed.

---

### m4: `run_dir` Stored as String Path (Lens 3: Data Integrity)

`WorkflowRun.run_dir` stores an absolute filesystem path like `~/.kiro_flow/runs/20260418_...`. This is fragile — if the home directory or server changes, paths break. Consider storing only the run ID and computing the path.

---

### m5: `WorkflowExecutionService` Holds DB Connection During Polling Loop (Lens 13: Concurrency)

```ruby
while worker.alive?
  sleep 1
  @run.update!(node_states: build_node_states(runner, run_dir))
end
```

The main thread holds an ActiveRecord connection for the entire workflow duration (potentially minutes). With a pool of 5 and 3 Solid Queue threads, this could exhaust connections.

---

### m6: No `config.filter_parameters` Customization (Lens 1: Security)

Rails defaults filter `:password`, but the app should also filter `:token`, `:secret`, `:_key`, `:steering_document` (may contain sensitive instructions).

---

### m7: Kamal Deploy Target is `192.168.0.1` (Lens 16: Deployment)

`config/deploy.yml` points to a private IP. This is fine for local/dev but should be parameterized for production.

---

### m8: `action_mailer.default_url_options` Set to `example.com` (Lens 20: Configuration)

```ruby
config.action_mailer.default_url_options = { host: "example.com" }
```

Placeholder value in production config. If mailer is ever used, links will point to example.com.

---

## Lens-by-Lens Summary

| # | Lens | Verdict | Key Findings |
|---|------|---------|-------------|
| 1 | Security | 🔴 FAIL | `eval()` RCE (B1), no auth (B2), `to_unsafe_h` (M7), CSP report-only (M8) |
| 2 | Multi-Tenancy | ⚪ N/A | Single-tenant app, no ActsAsTenant needed yet |
| 3 | Database & Data Integrity | 🟡 WARN | Missing indexes (M6), missing `dependent:` (M3), `run_dir` as string (m4) |
| 4 | Performance | 🟡 WARN | N+1 on index (M1), unbounded collection (M4), connection hold (m5) |
| 5 | Code Quality & Ruby Style | 🟢 PASS | Clean code, good use of Ruby 3.4 features (`it`, endless methods), RuboCop configured |
| 6 | Rails Anti-Patterns | 🟡 WARN | `materialize!` side effect in model (M2), gate wiring bug (C2) |
| 7 | Testing | 🔴 FAIL | Zero Rails tests (C4). Only lib specs exist. |
| 8 | Hotwire | 🟢 PASS | Turbo Streams for live updates, Stimulus controllers well-structured, ActionCable for real-time |
| 9 | ViewComponent | 🟢 PASS | 16 components under `Kreoz::` namespace, variant-driven, slot-based. No component tests though. |
| 10 | Error Handling | 🟡 WARN | Stale run recovery missing (C5), `rescue => e` in job re-raises (good) |
| 11 | I18n | 🔴 FAIL | All strings hardcoded in English (M5), no locale files |
| 12 | Accessibility | 🟡 WARN | Not audited in detail — Flowbite components provide baseline a11y, but custom views need review |
| 13 | Concurrency | 🟢 PASS | Runner uses Mutex correctly, Context is thread-safe, minor constant freezing issue (m1) |
| 14 | Dependency Management | 🟢 PASS | Gems pinned with `~>`, Flowbite CDN pinned to exact version, `bundler-audit` + `brakeman` in Gemfile |
| 15 | Asset Pipeline | 🟢 PASS | Propshaft + Importmap configured correctly, dead JS files (m2, m3) |
| 16 | Deployment | 🟢 PASS | Kamal 2 configured, Dockerfile is solid (jemalloc, multi-stage, non-root), `force_ssl = true` |
| 17 | Scalability | 🟡 WARN | `workflow_runs` will grow unbounded — no archival/cleanup strategy |
| 18 | API Design | 🟢 PASS | RESTful routes, correct status codes, `respond_to` handles HTML + JSON |
| 19 | Soft Deletes | ⚪ N/A | No soft deletes implemented (hard deletes via `destroy`) |
| 20 | Configuration | 🟢 PASS | Production config is solid, `.env.example` exists, secrets in credentials |
| 21 | Git & PR Hygiene | 🟡 WARN | Entire project in one commit (216 files). Should be broken into logical commits. |

---

## Infinite Loop Post-Mortem

**Workflow:** `39e3187d-6953-487c-91f3-c664da5a7724` ("New Workflow")
**Run status:** Stuck in `running` (process killed with Ctrl+C)

### Workflow Structure
```
shell_6 → Code Review → Tend Concerns → Validate Changes → Needs more Attention?
                                                ↑                    │
                                                └────── on_true ─────┘
```

### Timeline
1. `shell_6` completed (empty `cd` command)
2. `Code Review` completed (kiro-cli returned review)
3. `Tend Concerns` **failed** (kiro-cli error — output truncated at 3966 chars)
4. `Validate Changes` **skipped** (upstream `Tend Concerns` failed)
5. `Needs more Attention?` **skipped** (upstream `Validate Changes` skipped)
6. Gate's `on_true` edge re-enqueued `Validate Changes`
7. `Validate Changes` checked upstream → `Needs more Attention?` is skipped → skip
8. `Validate Changes` enqueued `Needs more Attention?` via `next` edge
9. `Needs more Attention?` checked upstream → `Validate Changes` is skipped → skip
10. **Steps 6-9 repeated infinitely** until Ctrl+C

### Three Contributing Bugs
1. **Runner has no re-processing guard** — `enqueue_downstream` doesn't check if a node was already processed
2. **DrawflowConverter doesn't wire `only_if` guards** — gate output is ignored
3. **Gate condition is hardcoded `"true"`** — should evaluate based on previous node's output

---

## Recommended Priority

1. **Fix the runner infinite loop** (C1) — add processed-node guard
2. **Fix gate wiring in DrawflowConverter** (C2) — wire `only_if`/`unless_node`
3. **Add authentication** (B2) — even basic session auth
4. **Replace `eval()` with safe DSL** (B1) — or gate behind auth as interim
5. **Add model + controller tests** (C4)
6. **Add stale run recovery** (C5)
7. **Fix N+1 and missing indexes** (M1, M6)
8. **Set up I18n** (M5)
