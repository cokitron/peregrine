# Flight Control — Kreoz Code Review Report

**Date:** 2026-04-18
**Reviewer:** Kiro (automated, Kreoz steering v1)
**Project:** Flight Control — Visual workflow engine for chaining kiro-cli AI calls
**Stack:** Ruby 3.4.8, Rails 8.1.3, PostgreSQL (UUIDs), Solid Queue/Cache/Cable, Tailwind v4 + Flowbite, Stimulus, ViewComponent, Kamal 2

---

## Executive Summary

Flight Control is a well-architected Rails 8 application with a clean KiroFlow engine, solid DSL design, and a polished Stimulus-based visual editor. The lib-level test suite (61 tests, 118 assertions) is thorough.

However, the application has **4 blockers** and **7 critical** issues that must be addressed before any production deployment. The most severe are: arbitrary code execution via `eval` in DrawflowConverter, complete absence of authentication/authorization, `force_ssl` disabled in production, and zero Rails-level tests.

### Scorecard

| Severity | Count |
|----------|-------|
| 🔴 Blocker | 4 |
| 🟠 Critical | 7 |
| 🟡 Major | 10 |
| 🔵 Minor | 8 |
| ⚪ Nit | 5 |

---

## Lens 1: Security

### 🔴 BLOCKER — Remote Code Execution via `eval` in DrawflowConverter

**Files:** `app/services/drawflow_converter.rb:30,33`

```ruby
wf.node(name, type: :ruby, callable: ->(ctx) { eval(code) })   # line 30
wf.node(name, type: :gate, condition: ->(ctx) { eval(cond) })   # line 33
```

User-supplied strings from the `drawflow_data` JSONB column are passed directly to `eval`. Any user who can create or edit a workflow can execute arbitrary Ruby code on the server. This is a textbook RCE vulnerability.

The `# rubocop:disable Security/Eval` comments acknowledge the issue but do not mitigate it.

**Fix:** For Ruby nodes, use a sandboxed evaluator or restrict to a safe DSL. For gate conditions, parse a limited expression grammar (e.g., `ctx[:name].include?("success")`) instead of eval. At minimum, document this as an intentional design decision for trusted-user-only deployments and add a prominent warning.

### 🔴 BLOCKER — No Authentication

**File:** `app/controllers/application_controller.rb`

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  layout "authenticated"
end
```

There is no `before_action :authenticate`, no session management, no login flow. Every route is publicly accessible. The layout is named "authenticated" but enforces nothing.

`ApplicationCable::Connection` references `Session` and `cookies.signed[:session_id]` — models that don't exist in this project, so WebSocket connections will always be rejected.

**Fix:** Add authentication. Rails 8's `bin/rails generate authentication` provides a solid starting point.

### 🔴 BLOCKER — No Authorization

No Pundit, no CanCanCan, no policy checks anywhere. Every authenticated user (once auth exists) would have full access to all workflows, agents, and runs.

**Fix:** Add Pundit policies or at minimum scope queries to the current user.

### 🔴 BLOCKER — `force_ssl` Disabled in Production

**File:** `config/environments/production.rb:28-29`

```ruby
# config.assume_ssl = true
# config.force_ssl = true
```

Both are commented out. Production traffic will be served over plain HTTP. Session cookies, CSRF tokens, and all data transmitted in cleartext.

**Fix:** Uncomment both lines. Add the health check exclusion for the `/up` endpoint.

### 🟠 CRITICAL — Shell Command Injection via ShellNode

**File:** `lib/kiro_flow/nodes/shell_node.rb:7`

```ruby
cmd = context.interpolate(opts.fetch(:command))
stdout, stderr, status = Timeout.timeout(opts.fetch(:timeout, 60)) { Open3.capture3(cmd) }
```

`Open3.capture3(cmd)` with a single string argument passes through the shell. If `{{name}}` interpolation injects user-controlled content, it enables command injection. The KiroNode has the same pattern with `IO.popen(cmd)`.

**Fix:** Use the array form of `Open3.capture3` to avoid shell interpretation, or validate/escape interpolated values.

### 🟠 CRITICAL — `permit!` on Nested Params

**File:** `app/controllers/workflows_controller.rb:24,67`

```ruby
@workflow.drawflow_data = params.dig(:workflow_definition, :drawflow_data)&.permit!&.to_h
```

`.permit!` allows any parameter through, bypassing strong parameters entirely. An attacker could inject arbitrary keys into the JSONB column.

**Fix:** Define an explicit permit list for the drawflow_data structure, or validate the JSON schema server-side before saving.

### 🟠 CRITICAL — CSP Entirely Disabled

**File:** `config/initializers/content_security_policy.rb`

The entire CSP configuration is commented out. No Content-Security-Policy header is sent. This leaves the app vulnerable to XSS via injected scripts.

**Fix:** Enable CSP with at minimum `default_src :self`, allowing the Flowbite CDN and Google Fonts explicitly.

### 🟡 MAJOR — No Rate Limiting

No `rack-attack` gem, no throttling on any endpoint. The `execute` action queues background jobs — an attacker could flood the job queue.

**Fix:** Add `rack-attack` with throttles on workflow execution and any future auth endpoints.

### 🟡 MAJOR — WebSocket Channel Has No Authorization

**File:** `app/channels/workflow_run_channel.rb`

```ruby
class WorkflowRunChannel < ApplicationCable::Channel
  def subscribed
    stream_from "workflow_run_#{params[:run_id]}"
  end
end
```

Any client can subscribe to any run's channel by guessing/enumerating UUIDs. No ownership check.

**Fix:** Verify the current user owns the workflow run before allowing subscription.

### 🔵 MINOR — `--trust-all-tools` Default in KiroNode

KiroNode defaults to `trust: :all`, which gives kiro-cli unrestricted tool access. This is by design for the workflow engine but should be documented as a security consideration.

### 🔵 MINOR — Filter Parameters Comprehensive ✅

`config/filter_parameters` includes `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`. Good coverage.

---

## Lens 2: Multi-Tenancy

**N/A** — Flight Control is a single-tenant application. No `acts_as_tenant`, no `empresa_id` columns. This is appropriate for a personal/team tool. If multi-tenancy is added later, every model will need tenant scoping.

---

## Lens 3: Database & Data Integrity

### ✅ UUIDs and pgcrypto

All tables use `id: :uuid`. `pgcrypto` extension enabled. Generator configured in `config/application.rb`.

### 🟡 MAJOR — Missing Foreign Key on `default_agent_id`

**File:** `db/migrate/20260418175825_create_agents.rb:9`

```ruby
add_column :workflow_definitions, :default_agent_id, :uuid
```

No `foreign_key: true`, no index. Orphaned references possible if an agent is deleted.

**Fix:**
```ruby
add_reference :workflow_definitions, :default_agent, type: :uuid, foreign_key: { to_table: :agents }, index: true
```

### 🟡 MAJOR — No CHECK Constraint on `workflow_runs.status`

The model validates `inclusion: { in: %w[pending running completed failed] }`, but there's no DB-level CHECK constraint. Direct SQL or `update_column` (used in the job) bypasses model validations.

**Fix:** Add a migration with `CHECK (status IN ('pending', 'running', 'completed', 'failed'))`.

### 🟡 MAJOR — `update_column` Bypasses Validations

**File:** `app/jobs/execute_workflow_job.rb:14`

```ruby
run.update_column(:node_states, build_node_states(runner, run_dir))
```

`update_column` skips validations and callbacks. Combined with the missing CHECK constraint, this could write invalid data.

**Fix:** Use `update!` or add the DB-level CHECK constraint.

### 🔵 MINOR — Timestamps Missing `null: false`

The `agents` and `workflow_definitions` tables have timestamps but the schema shows them as nullable (Rails 8 default may handle this, but explicit `null: false` is safer).

---

## Lens 4: Performance

### 🟠 CRITICAL — N+1 Queries in `workflows#index`

**File:** `app/controllers/workflows_controller.rb:6`

```ruby
@workflows = WorkflowDefinition.includes(:workflow_runs).order(updated_at: :desc)
```

The `includes(:workflow_runs)` loads all runs, but the view then calls:
- `wf.workflow_runs.recientes.limit(5)` — triggers a new query per workflow (the scope/limit defeats the eager load)
- `wf.last_run` — another query per workflow

**Fix:** Use a window function or preload the latest 5 runs per workflow. Or accept the N+1 for now and add `strict_loading` in development to catch regressions.

### 🟡 MAJOR — No Pagination on Any Index Action

All three index actions (`workflows#index`, `workflow_runs#index`, `agents#index`) load unbounded collections. As data grows, these will degrade.

**Fix:** Add pagination (Pagy or cursor-based) to all index actions.

### 🟡 MAJOR — Polling Loop in ExecuteWorkflowJob

**File:** `app/jobs/execute_workflow_job.rb:11-15`

```ruby
while worker.alive?
  sleep 1
  run.update_column(:node_states, build_node_states(runner, run_dir))
end
```

This spawns a thread inside a Solid Queue job, then polls every second with a DB write. This ties up a job worker thread and hammers the database.

**Fix:** Use `after_commit` callbacks or ActionCable broadcasts from the runner itself instead of polling. Or at minimum increase the poll interval.

### 🔵 MINOR — Client-Side Polling at 15s Intervals

The workflow editor polls run status every 15 seconds via `setInterval`. Consider using ActionCable (already set up) for real-time updates instead.

---

## Lens 5: Code Quality & Ruby Style

### 🟡 MAJOR — `workflow_editor_controller.js` is 500+ Lines

This Stimulus controller handles rendering, linking, drag-and-drop, undo/redo, keyboard shortcuts, SVG arrows, run execution, and polling. It should be decomposed into smaller controllers.

**Fix:** Extract into focused controllers: `workflow-renderer`, `workflow-linker`, `workflow-runner`, `workflow-undo`.

### 🔵 MINOR — `arrowsTarget` Referenced but Not Declared

**File:** `app/javascript/controllers/workflow_editor_controller.js`

The controller references `this.arrowsTarget` in `startLinking`, `onLinkMouseMove`, `onLinkMouseUp`, and `drawArrows`, but `arrowsTarget` is not in the `static targets` list and no element with `data-workflow-editor-target="arrows"` exists in the view. This will cause runtime errors when linking is attempted.

**Fix:** Add `"arrows"` to `static targets` and add an SVG element with the target attribute in the view.

### 🔵 MINOR — Constants Not Frozen in Some Places

`NODE_TYPES` in the JS controller is `const` (fine). In Ruby, `WorkflowsHelper::NODE_STYLES` is properly frozen. `Agent` model constants are fine. No issues found.

### ⚪ NIT — Inconsistent Language

The steering doc specifies "Spanish domain, English infrastructure." This project uses English throughout (model names, routes, views). The only Spanish is `nombre` and `descripcion` on models. This is fine for Flight Control but inconsistent with the Kreoz convention.

---

## Lens 6: Rails Anti-Patterns

### 🟠 CRITICAL — GET Action Creates a Record

**File:** `app/controllers/agents_controller.rb:8-10`

```ruby
def new
  @agent = Agent.create!(nombre: "New Agent #{Time.current.strftime('%H:%M')}", steering_document: default_steering)
  redirect_to agent_path(@agent)
end
```

The `new` action (GET request) creates a database record. This violates HTTP semantics — GET requests must be safe (no side effects). Browser prefetching, crawlers, or accidental navigation will create orphan agents.

**Fix:** Use a POST action for creation. The `new` action should only render a form.

### 🟡 MAJOR — Business Logic in Job

`ExecuteWorkflowJob` contains workflow conversion, runner orchestration, thread management, state polling, and broadcasting. This should be extracted into a service object.

### ⚪ NIT — `default_steering` Method in Controller

The `default_steering` method in `AgentsController` contains a heredoc template. This belongs in the model or a constant.

---

## Lens 7: Testing

### 🟠 CRITICAL — Zero Rails-Level Tests

```
test/models/       → empty
test/controllers/  → empty
test/system/       → empty
test/fixtures/     → no fixture files
```

The only tests are in `spec/kiro_flow_spec.rb` (61 tests for the lib-level engine). There are no tests for:
- Model validations and associations
- Controller actions and response codes
- Service objects (DrawflowConverter)
- Background jobs (ExecuteWorkflowJob)
- System/integration tests
- ViewComponent rendering

The CI pipeline runs `bin/rails test` and `bin/rails test:system` but both will pass vacuously with zero tests.

**Fix:** Add at minimum:
1. Model tests for all 3 models (validations, associations, scopes)
2. Controller tests for CRUD operations and authorization
3. DrawflowConverter unit tests
4. ExecuteWorkflowJob tests
5. Fixtures for all models

### 🔵 MINOR — Spec File Uses Minitest, Not in Standard Location

`spec/kiro_flow_spec.rb` uses Minitest but lives in `spec/` (RSpec convention). It also requires files manually instead of using Rails test infrastructure. This is fine for a standalone lib but should be noted.

---

## Lens 8: Hotwire (Turbo + Stimulus)

### 🟡 MAJOR — Missing `arrowsTarget` SVG Element

The workflow editor controller references `this.arrowsTarget` extensively for SVG arrow drawing, but no corresponding SVG element exists in `workflows/show.html.erb` and `"arrows"` is not in the `static targets` declaration. The entire visual linking feature is broken.

**Fix:** Add to `static targets`: `"arrows"`. Add to the view:
```erb
<svg data-workflow-editor-target="arrows" class="absolute inset-0 pointer-events-none overflow-visible"></svg>
```

### ✅ CSRF Tokens Handled Correctly

All fetch calls in Stimulus controllers read the CSRF token from the meta tag and include it in headers. Good.

### ✅ Progressive Enhancement

The editor degrades to server-rendered HTML. Links work without JS. Turbo Drive provides the free upgrade.

---

## Lens 9: ViewComponent

### ✅ Namespace and Structure

All 17 components live under `Kreoz::` namespace in `app/components/kreoz/`. They use keyword arguments and variant hashes.

### 🟡 MAJOR — No Component Tests

Zero ViewComponent tests exist. Every component should have a `render_inline` test covering all variants.

### ⚪ NIT — Some Components Are Minimal

`DrawerComponent`, `FabComponent`, and `ModalComponent` have very thin Ruby files (1-3 lines). Consider if they add value over plain partials.

---

## Lens 10: Error Handling & Logging

### 🟡 MAJOR — No `rescue_from` in ApplicationController

No global error handling. `ActiveRecord::RecordNotFound` will render a raw 500 error in production (since `consider_all_requests_local = false`).

**Fix:** Add:
```ruby
rescue_from ActiveRecord::RecordNotFound, with: :not_found

private
def not_found
  render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
end
```

### 🔵 MINOR — Broad Rescue in ExecuteWorkflowJob

```ruby
rescue => e
  run&.update!(status: "failed", error_message: e.message, completed_at: Time.current)
  raise
end
```

Rescuing `StandardError` is acceptable here since it re-raises. The job will be retried by Solid Queue. Good pattern.

---

## Lens 11: Internationalization

### 🔵 MINOR — All Strings Hardcoded in English

All user-facing text is hardcoded in views and controllers. No I18n keys used. The Kreoz convention calls for Spanish domain text via locale files, but Flight Control appears to be an English-only project. This is acceptable if intentional.

### 🔵 MINOR — `raise_on_missing_translations` Disabled

Both `development.rb` and `test.rb` have `config.i18n.raise_on_missing_translations` commented out.

---

## Lens 12: Accessibility

### 🟡 MAJOR — Form Inputs Lack Labels

Throughout the views, inputs are used without associated `<label>` elements:

- `workflows/show.html.erb`: The nombre input has no label
- `agents/show.html.erb`: nombre, descripcion, steering inputs have visible labels but no `for` attribute linking them to the inputs (they use `<label class="block...">` without `for`)
- All JS-generated inputs in the workflow editor have no labels or `aria-label`

**Fix:** Add `for` attributes to labels matching input `id`s, or use `aria-label` on inputs.

### 🟡 MAJOR — Icon-Only Buttons Lack Accessible Names

Multiple buttons use only SVG icons with no text or `aria-label`:
- Back navigation buttons (arrow SVGs)
- Delete buttons (X SVGs)
- The `⋮` actions button in workflow cards

**Fix:** Add `aria-label` to all icon-only buttons.

### 🔵 MINOR — No Skip Navigation Link

No skip-to-content link for keyboard users to bypass the sidebar.

### 🔵 MINOR — No `aria-live` Regions for Dynamic Updates

Turbo Stream updates and toast notifications have no `aria-live` attributes. Screen readers won't announce changes.

---

## Lens 13: Concurrency & Thread Safety

### ✅ Mutex Usage in Runner and Context

`KiroFlow::Runner` uses `@mutex` for all shared state access. `KiroFlow::Context` uses `@mutex` for the store. Thread-safe.

### 🟡 MAJOR — Thread Spawned Inside Background Job

**File:** `app/jobs/execute_workflow_job.rb:10-15`

```ruby
worker = Thread.new { ctx = runner.run(input: run.input_text, run_dir: run_dir) }
while worker.alive?
  sleep 1
  run.update_column(:node_states, build_node_states(runner, run_dir))
end
```

Spawning threads inside Solid Queue jobs is risky. If the job is killed (timeout, deploy), the thread may be orphaned. The `ctx` variable is assigned inside the thread but read outside — this is a race condition (though `worker.join` mitigates it).

**Fix:** Run the workflow synchronously in the job and use ActionCable broadcasts from the runner for live updates.

---

## Lens 14: Dependency Management

### 🟠 CRITICAL — Dockerfile Ruby Version Mismatch

**File:** `Dockerfile:10`

```dockerfile
ARG RUBY_VERSION=3.2.2
```

`.ruby-version` specifies `3.4.8`. The Docker image will build with Ruby 3.2.2, missing all Ruby 3.4 features the codebase relies on (e.g., `it` block parameter).

**Fix:** Change to `ARG RUBY_VERSION=3.4.8`.

### ✅ Gem Versions Properly Constrained

Gemfile uses pessimistic constraints (`~>`) for key gems. Flowbite CDN pinned to `4.0.1`.

### ⚪ NIT — No `rack-attack` in Gemfile

As noted in Security, rate limiting gem is missing.

---

## Lens 15: Asset Pipeline & Frontend

### ✅ Propshaft + Importmap Properly Configured

Assets use Propshaft with content-based fingerprinting. JS dependencies pinned in `config/importmap.rb` with exact versions.

### ✅ Tailwind CSS + Flowbite Integration

`app/assets/tailwind/application.css` properly imports Flowbite theme and defines custom brand colors.

### ⚪ NIT — Dynamic Tailwind Classes Safelisted

The view includes a hidden div with safelisted dynamic classes. This is a valid workaround but should be documented.

---

## Lens 16: Deployment & Infrastructure

### 🔴 (Already counted above) — `force_ssl` Disabled

### 🟡 MAJOR — Dockerfile Ruby Version Mismatch (counted in Lens 14)

### ✅ Kamal 2 Configuration

`config/deploy.yml` is properly configured with Kamal 2, Thruster, and Solid Queue in Puma.

### ✅ CI Pipeline

`.github/workflows/ci.yml` covers: Brakeman, bundler-audit, importmap audit, RuboCop, Rails tests, and system tests. Well-structured.

### ✅ Health Check Endpoint

`/up` route mapped to `rails/health#show`. Custom `bin/healthcheck` for KiroFlow runner.

---

## Lens 17: Scalability

### 🟡 MAJOR — No Pagination (counted in Lens 4)

### 🔵 MINOR — `workflow_runs` Table Will Grow Unbounded

No archival or cleanup strategy for old runs. The `run_dir` on disk (`~/.kiro_flow/runs/`) will also accumulate indefinitely.

**Fix:** Add a periodic cleanup job or retention policy.

---

## Lens 18: API Design

### ✅ RESTful Routes

Routes follow REST conventions. Nested resources one level deep. `execute` is a member POST action.

### ✅ Proper Status Codes

JSON responses use correct status codes: 201 for create, 422 for validation errors, 200 for success.

### ⚪ NIT — `execute` Action Returns Different Formats

The `execute` action responds to both JSON and HTML. The JSON response returns `{ run_id, status_url }` which is clean. The HTML response redirects. Good dual-format handling.

---

## Lens 19: Soft Deletes & Data Lifecycle

### Not Implemented

No soft deletes. All deletions are hard deletes via `destroy`. This is acceptable for an early-stage project but should be considered before production use, especially for workflow runs (audit trail).

### ✅ `dependent: :destroy` Set

`WorkflowDefinition has_many :workflow_runs, dependent: :destroy` — cascading deletes are explicit.

---

## Lens 20: Configuration & Environment Hygiene

### ✅ Secrets Management

- `.env*` in `.gitignore`
- `config/*.key` in `.gitignore`
- `config/master.key` exists but is gitignored
- `.kamal/secrets` reads master key from file, not hardcoded

### ✅ Filter Parameters

Comprehensive list including `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc`.

### 🔵 MINOR — No `.env.example` File

No documentation of required environment variables.

---

## Lens 21: Git & PR Hygiene

### ✅ `.gitignore` Comprehensive

Covers logs, tmp, storage, node_modules, builds, keys, env files.

### ✅ CI Pipeline Complete

Brakeman, bundler-audit, RuboCop, tests, system tests all in CI.

### 🔵 MINOR — Junk File in Project Root

```
/home/jorge/work/flight-control/[0m[0m[0m
```

A file with ANSI escape codes as its name exists in the project root. Should be deleted before committing.

---

## Priority Action Items

### Must Fix Before Any Deployment

1. **Enable `force_ssl`** in production.rb
2. **Fix Dockerfile** Ruby version: `3.2.2` → `3.4.8`
3. **Add authentication** (Rails 8 generator or manual)
4. **Add authorization** (Pundit or equivalent)
5. **Address `eval` in DrawflowConverter** — document as intentional for trusted users or sandbox it
6. **Remove `.permit!`** — validate drawflow_data structure explicitly
7. **Enable CSP** — uncomment and configure content_security_policy.rb
8. **Fix `agents#new`** — don't create records on GET requests

### Should Fix Soon

9. Add Rails-level tests (models, controllers, at minimum)
10. Add missing foreign key and index on `default_agent_id`
11. Add CHECK constraint on `workflow_runs.status`
12. Add pagination to all index actions
13. Fix `arrowsTarget` missing from Stimulus controller
14. Add `rescue_from` in ApplicationController
15. Add `aria-label` to icon-only buttons
16. Add form labels with proper `for` attributes

### Track as Tech Debt

17. Decompose `workflow_editor_controller.js` into smaller controllers
18. Extract job logic into a service object
19. Add ViewComponent tests
20. Add run cleanup/archival strategy
21. Add rate limiting with `rack-attack`
22. Delete junk file `[0m[0m[0m` from project root
23. Add `.env.example` documenting required env vars
24. Add `aria-live` regions for dynamic content updates

---

## What's Done Well

- **KiroFlow engine design** — Clean DSL, proper separation of concerns, thread-safe context, well-tested (61 tests)
- **Database design** — UUIDs everywhere, JSONB for flexible data, proper foreign keys on workflow_runs
- **Stimulus editor** — Sophisticated visual editor with undo/redo, keyboard shortcuts, drag-and-drop linking, loop detection
- **CI pipeline** — Comprehensive: security scanning, linting, tests, system tests
- **ViewComponent library** — 17 reusable components under proper namespace
- **Ruby 3.4 idioms** — Uses `it` block parameter, mutable string buffers (`+""`)
- **Kamal 2 deployment** — Properly configured with Thruster, Solid Queue in Puma
