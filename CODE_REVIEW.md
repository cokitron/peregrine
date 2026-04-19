# Code Review — Flight Control

**Branch:** `fix/code-review-findings`
**Date:** 2026-04-18
**Reviewer:** Kiro (automated, against 21 Kreoz lenses)
**Scope:** Full codebase — all models, controllers, services, views, JS, migrations, config, tests

---

## Executive Summary

Flight Control is a Rails 8.1 single-tenant app for orchestrating Kiro CLI workflows. The codebase is well-structured with clean separation of concerns, proper use of UUIDs, CHECK constraints, background jobs, and a solid KiroFlow engine with property-based tests.

**Critical findings:** The app has no authentication or authorization, yet executes arbitrary shell commands and `eval`'d Ruby code from workflow definitions. This is an intentional design choice for trusted-user deployments (documented in `DrawflowConverter`), but it means the app MUST NOT be exposed to untrusted networks without adding auth first.

| Severity | Count |
|----------|-------|
| Blocker  | 1     |
| Critical | 3     |
| Major    | 4     |
| Minor    | 6     |
| Nit      | 3     |

---

## Lens 1: Security

### BLOCKER — No Authentication + Arbitrary Code Execution

**Files:** `app/controllers/application_controller.rb`, `app/services/drawflow_converter.rb`, `lib/kiro_flow/nodes/shell_node.rb`

The app has zero authentication. Any user who can reach the server can:

1. Create a workflow with a Ruby node containing `system("rm -rf /")` — executed via `eval` in `DrawflowConverter` (lines 42–43).
2. Create a workflow with a Shell node containing any command — executed via `Open3.capture3` in `ShellNode`.
3. Create a workflow with a Kiro node that runs `kiro-cli` with `--trust-all-tools`.

The security comment at the top of `DrawflowConverter` acknowledges this:

> WARNING: SECURITY — This service uses `eval` to execute user-defined Ruby code... DO NOT expose workflow creation to untrusted users without sandboxing eval or replacing it with a safe DSL.

**Verdict:** Acceptable for local/trusted deployment. **Blocker for any network-exposed deployment.** Before deploying to a shared network:

- Add authentication (e.g., `has_secure_password` with session-based login).
- Add authorization to restrict who can create/edit workflows.
- Consider replacing `eval` with a safe expression evaluator for gate conditions.

### OK — SQL Injection

No raw SQL with user input. All queries use ActiveRecord parameterized finders (`find`, `find_by`, `where`). CHECK constraint migrations use static SQL strings. ✅

### Minor — Incomplete HTML Escaping in JS

**File:** `app/javascript/controllers/workflow_editor_controller.js` (line ~750)

```js
esc(s) { return s.replace(/"/g, "&quot;").replace(/</g, "&lt;") }
```

Missing `>`, `&`, and `'` escaping. While the data rendered through `esc()` is self-authored workflow content (not third-party input), a complete escaping function prevents future bugs:

```js
esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
          .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
          .replace(/'/g, "&#39;")
}
```

### OK — CSRF Protection

Both layouts include `<%= csrf_meta_tags %>`. All JS `fetch` calls include the CSRF token from the meta tag. `stop` uses POST (not GET). Rails default `protect_from_forgery` is active. ✅

### OK — Mass Assignment

Strong parameters used in all controllers. `sanitize_drawflow_data` allowlists step keys via `ALLOWED_STEP_KEYS.freeze`. `to_unsafe_h` is immediately filtered. ✅

### OK — Secrets & Credentials

`.env` in `.gitignore`. `.env.example` has placeholders only. `config/master.key` gitignored. `filter_parameters` covers `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`. ✅

### Minor — CSP in Report-Only Mode

**File:** `config/initializers/content_security_policy.rb` (line 18)

```ruby
config.content_security_policy_report_only = true
```

CSP is configured correctly (`script_src :self, "https://cdn.jsdelivr.net"`, no `unsafe-eval`/`unsafe-inline`) but is not enforcing. Switch to enforcing in production after verifying no violations.

### Major — No Rate Limiting

No `rack-attack` or equivalent. The `execute` action spawns background jobs that run shell commands. Without rate limiting, a malicious or buggy client could flood the job queue.

### OK — Headers

`force_ssl = true` and `assume_ssl = true` in production. Rails defaults handle `X-Frame-Options`, `X-Content-Type-Options`. ✅

### Nit — ApplicationCable::Connection References Non-Existent Session Model

**File:** `app/channels/application_cable/connection.rb`

References `Session.find_by(id: cookies.signed[:session_id])` but no `Session` model exists. This is dead code from the Rails generator. It will raise `NameError` at runtime if a WebSocket connection is attempted.

**Fix:** Either implement the Session model or simplify to allow all connections (since there's no auth):

```ruby
class Connection < ActionCable::Connection::Base
end
```

---

## Lens 2: Multi-Tenancy

**Not applicable.** Flight Control is a single-tenant application. No `empresa_id` columns, no `ActsAsTenant`, no tenant scoping. ✅

---

## Lens 3: Database & Data Integrity

### OK — Migrations

All tables use `id: :uuid` with `pgcrypto` extension. Migrations are reversible (CHECK constraint migrations have explicit `up`/`down`). ✅

### OK — Indexes

All foreign key columns are indexed:
- `workflow_runs.workflow_definition_id` ✅
- `workflow_definitions.default_agent_id` ✅

### OK — Constraints

- `status` has DB-level CHECK constraint + model-level `validates :inclusion` ✅
- `nombre` has `null: false` + `validates :presence` ✅
- Foreign keys with appropriate `on_delete` strategies ✅
- `drawflow_data`, `node_states`, `context_files` have `null: false, default: {}` or `default: []` ✅

### OK — Data Types

UUIDs, JSONB for schemaless data, proper timestamp constraints. ✅

---

## Lens 4: Performance

### Major — N+1 Queries in Workflows Index

**File:** `app/views/workflows/index.html.erb`

Each workflow card executes:
1. `wf.drawflow_data["steps"]` — already loaded (JSONB column).
2. `wf.workflow_runs.recientes.limit(5)` — **separate query per workflow**.
3. `wf.last_run` — **another separate query per workflow**.

With 24 workflows per page, this is 48 extra queries.

**Fix in controller:**

```ruby
def index
  @workflows = WorkflowDefinition.order(updated_at: :desc)
                                 .includes(:workflow_runs)
                                 .limit(PER_PAGE)
                                 .offset(page_offset)
end
```

Or use `preload` and limit in the view with already-loaded associations.

### OK — Pagination

All index actions paginate with `PER_PAGE = 24`. Offset-based pagination is acceptable for the current scale. ✅

### OK — Background Jobs

Workflow execution runs in Solid Queue. `discard_on ActiveRecord::RecordNotFound` prevents retrying deleted runs. Error handling updates the run status. ✅

### OK — Memory

`WorkflowExecutionService` limits output to 4KB per node (`byteslice(-4000..)`). Runner caps concurrency at 3 threads. ✅

---

## Lens 5: Code Quality & Ruby Style

### OK — Naming Conventions

Spanish domain names (`nombre`, `descripcion`) with English infrastructure (`status`, `run_dir`). Consistent throughout. ✅

### OK — Method Sizes

All Ruby methods are within the 25-line limit. Controllers are lean. Services have clear single responsibilities. ✅

### OK — Constants

All constants are frozen: `ALLOWED_STEP_KEYS.freeze`, `NODE_STYLES.freeze`, `TERMINAL_STATES.freeze`. ✅

### Nit — `WorkflowExecutionService#build_node_states` Complexity

The method chains multiple transformations (file read → byteslice → encode → gsub). Consider extracting the ANSI-stripping and encoding into a helper method for readability.

---

## Lens 6: Rails Anti-Patterns

### OK — Controller Thickness

Controllers are thin. Business logic lives in `WorkflowExecutionService` and `DrawflowConverter`. ✅

### OK — No Callback Abuse

No model callbacks. Side effects (job enqueuing, broadcasting) happen in services and controllers. ✅

### OK — Service Object Pattern

`WorkflowExecutionService`: initialize with dependencies, `#call` as entry point. `DrawflowConverter`: class method `.call`. Both follow conventions. ✅

---

## Lens 7: Testing

### Critical — No Rails-Layer Tests

**Missing entirely:**
- Controller/integration tests for all 5 controllers (WorkflowsController, WorkflowRunsController, AgentsController)
- Model tests for validations, associations, scopes
- System tests for critical user journeys
- Service tests for `WorkflowExecutionService` and `DrawflowConverter`
- ViewComponent tests

**What exists:**
- Comprehensive KiroFlow engine unit tests (Context, Chain, Node, Workflow, Runner, Persistence, AgentBuilder, ChainBuilder) ✅
- Property-based tests with 12 properties covering termination, state coverage, failure propagation, concurrency limits ✅

The KiroFlow engine is well-tested. The Rails integration layer has zero test coverage.

**Priority tests to add:**
1. `WorkflowsController` — CRUD operations, `execute` action, strong parameter filtering
2. `WorkflowRun` model — validations, `duration` method, `recientes` scope
3. `DrawflowConverter` — step flattening, sub-workflow expansion, circular reference detection
4. `WorkflowExecutionService` — happy path, cancellation, error handling

---

## Lens 8: Hotwire (Turbo + Stimulus)

### Major — Oversized Stimulus Controller

**File:** `app/javascript/controllers/workflow_editor_controller.js` — **~750 lines**

The Kreoz guideline is <50 lines per Stimulus controller. This controller handles:
- Step CRUD (add, remove, duplicate, move, toggle)
- Undo/redo history
- Visual graph rendering (tree layout, SVG arrows)
- Drag-and-drop linking
- Workflow execution and polling
- Output panel rendering
- Keyboard shortcuts
- Auto-save

**Recommended split:**
- `workflow_steps_controller.js` — step CRUD, undo/redo
- `workflow_graph_controller.js` — tree rendering, SVG arrows, linking
- `workflow_runner_controller.js` — execution, polling, status banners
- `workflow_editor_controller.js` — orchestrator, keyboard shortcuts, auto-save

### OK — Turbo Usage

`respond_to` handles both `format.html` and `format.json`/`format.turbo_stream`. Validation failures return `:unprocessable_entity`. `button_to` with `method: :delete` uses Turbo. ✅

### OK — Stimulus Patterns

Uses `static targets`, `static values`. `connect()` for setup, `disconnect()` for cleanup (removes event listeners, clears intervals). ✅

---

## Lens 9: ViewComponent

### Minor — No Component Tests

Components exist under `Kreoz::` namespace (`AlertComponent`, `EmptyStateComponent`, `BadgeComponent`, etc.) but no unit tests with `render_inline`. No preview classes.

---

## Lens 10: Error Handling & Logging

### OK — Controller Error Handling

`rescue_from ActiveRecord::RecordNotFound` in ApplicationController handles 404s for both HTML and JSON. ✅

### OK — Job Error Handling

`ExecuteWorkflowJob` rescues errors, updates run status to "failed", and broadcasts the failure. `discard_on ActiveRecord::RecordNotFound` prevents retrying deleted runs. ✅

### Minor — Hardcoded Flash Messages

Flash messages are hardcoded English strings (`"Workflow created"`, `"Workflow deleted"`, `"Agent deleted"`). Should use I18n keys for maintainability, even in an English-only app.

---

## Lens 11: Internationalization

### Minor — No I18n Setup

All user-facing strings are hardcoded in English. No locale files beyond the Rails default. `raise_on_missing_translations` is commented out in development.

**Acceptable** for an internal English-only tool. If internationalization is ever needed, the hardcoded strings will need extraction.

---

## Lens 12: Accessibility

### Major — Dynamic Content Lacks Accessibility

**File:** `app/javascript/controllers/workflow_editor_controller.js`

1. **Form fields generated by JS** lack proper `<label>` associations and ARIA attributes. The `expandedCard()` method generates inputs with visible labels but no `for`/`id` pairing.
2. **Visual linking** (drag from port to port) is mouse-only — no keyboard alternative exists.
3. **Status changes** (run started, completed, failed) update the DOM but don't announce to screen readers. The run status banner should use `role="status"` or `aria-live="polite"`.
4. **Action menus** (⋮ button) open on click but don't trap focus or support Escape to close (Escape is handled globally but not scoped to the menu).
5. **Toast notifications** should use `role="alert"` for screen reader announcement.

### OK — Static HTML Accessibility

Server-rendered HTML uses semantic elements (`<main>`, `<nav>`, `<aside>`), proper `aria-label` on icon buttons, `aria-hidden="true"` on decorative SVGs, and `<h1>` on each page. ✅

---

## Lens 13: Concurrency & Thread Safety

### OK — Runner Thread Safety

`Runner` uses `Mutex` for all shared state (`@state`, `@timings`, `@errors`, `@cancelled`). `Context` uses `Mutex` for its store. `MAX_CONCURRENT = 3` bounds thread count. Property tests verify termination and correctness under concurrent execution. ✅

### OK — WorkflowExecutionService

Uses `Thread.new` for the runner with `sleep 1` polling loop. Checks cancellation via `@run.reload.status`. `runner.cancel!` sets a mutex-protected flag. `worker.join(5) || worker.kill` handles cleanup. ✅

---

## Lens 14: Dependency Management

### OK — Gem Versions

All gems use pessimistic constraints (`~>`) or minimum versions (`>=`). `prop_check` is test-only. No suspicious or typosquatted gem names. ✅

### OK — JavaScript Dependencies

Flowbite pinned to exact version `4.0.1` in importmap. No `@latest` references. ✅

### Nit — Missing SRI Hashes on CDN Script

**File:** `config/importmap.rb`

```ruby
pin "flowbite", to: "https://cdn.jsdelivr.net/npm/flowbite@4.0.1/dist/flowbite.turbo.min.js"
```

No Subresource Integrity (SRI) hash. If the CDN is compromised, malicious JS could be served. Low risk but worth adding.

---

## Lens 15: Asset Pipeline & Frontend

### OK — Propshaft + Importmap

Uses Propshaft with `stylesheet_link_tag :app` and `javascript_importmap_tags`. Stimulus controllers auto-register. ✅

### OK — Tailwind CSS

Dynamic classes in JS are safelisted via a hidden div in `workflows/show.html.erb`. ✅

---

## Lens 16: Deployment & Infrastructure

### OK — Kamal Configuration

`config/deploy.yml` configured for Kamal 2. `force_ssl = true`, `assume_ssl = true`. Health check at `/up`. Asset bridging configured. ✅

### OK — Zero-Downtime Migrations

All migrations are additive (new tables, new columns, new constraints). No column renames or removals. ✅

---

## Lens 17: Scalability

### Minor — No Data Retention for Workflow Runs

`workflow_runs` will grow unbounded. Each run stores `node_states` (JSONB) and `error_message` (text). No archival or cleanup strategy.

**Recommendation:** Add a periodic job to delete runs older than N days, or add a `deleted_at` column for soft deletes with background cleanup.

---

## Lens 18: API Design

### OK — Response Conventions

Correct HTTP status codes (200, 201, 404, 422). `respond_to` handles HTML and JSON. Redirects after successful mutations. ✅

### OK — URL Design

RESTful routes with one level of nesting (`workflows/:id/runs`). Custom `execute` and `stop` actions use POST. ✅

---

## Lens 19: Soft Deletes & Data Lifecycle

### OK — Hard Deletes

No soft delete pattern. `dependent: :destroy` on `has_many :workflow_runs` ensures children are cleaned up. Acceptable for current scope. ✅

---

## Lens 20: Configuration & Environment Hygiene

### OK — Production Configuration

- `force_ssl = true` ✅
- `log_level = :info` ✅
- `dump_schema_after_migration = false` ✅
- `filter_parameters` comprehensive ✅
- `cache_store = :solid_cache_store` ✅
- `active_job.queue_adapter = :solid_queue` ✅

### Minor — Development Missing `raise_on_missing_translations`

**File:** `config/environments/development.rb` (line 63)

```ruby
# config.i18n.raise_on_missing_translations = true
```

Commented out. Should be enabled to catch missing translation keys early.

---

## Lens 21: Git & PR Hygiene

### OK — Commit Quality

Commits are logical and well-described:
- `fix: address code review findings`
- `Fix infinite loop on cyclic workflows with failed upstream`
- `Add property-based tests for KiroFlow runner (12 properties, 1200 graphs)`
- `Add stop button to cancel running workflows`

No secrets committed. `.gitignore` is comprehensive. ✅

---

## Summary of Findings

| # | Severity | Lens | Finding | Action |
|---|----------|------|---------|--------|
| 1 | **Blocker** | Security | No auth + eval/shell execution = RCE for anyone on the network | Add auth before network deployment |
| 2 | **Critical** | Testing | Zero Rails-layer test coverage (controllers, models, services) | Add tests before merge |
| 3 | **Critical** | Security | No rate limiting on workflow execution endpoint | Add rack-attack or equivalent |
| 4 | **Critical** | Accessibility | Dynamic JS content lacks ARIA attributes, keyboard alternatives | Fix before merge |
| 5 | **Major** | Performance | N+1 queries in workflows index (2 queries per workflow) | Add `includes(:workflow_runs)` |
| 6 | **Major** | Hotwire | Stimulus controller at ~750 lines (guideline: <50) | Split into focused controllers |
| 7 | **Major** | Security | CSP in report-only mode | Enforce in production |
| 8 | **Major** | Accessibility | Visual linking is mouse-only, no keyboard alternative | Add keyboard flow |
| 9 | **Minor** | Security | Incomplete `esc()` function in JS | Add full HTML entity escaping |
| 10 | **Minor** | Security | Dead code in ApplicationCable::Connection | Remove or implement Session model |
| 11 | **Minor** | ViewComponent | No component tests | Add render_inline tests |
| 12 | **Minor** | I18n | Hardcoded English strings, no I18n | Track as tech debt |
| 13 | **Minor** | Scalability | No data retention for workflow_runs | Add cleanup job |
| 14 | **Minor** | Config | `raise_on_missing_translations` commented out | Uncomment in development |
| 15 | **Nit** | Code Quality | `build_node_states` method could be cleaner | Author's discretion |
| 16 | **Nit** | Dependencies | Missing SRI hash on Flowbite CDN pin | Add integrity hash |
| 17 | **Nit** | I18n | Flash messages not using I18n keys | Author's discretion |
