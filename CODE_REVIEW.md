# Kreoz Code Review — Flight Control

**Branch:** `fix/code-review-findings`
**Date:** 2026-04-18
**Reviewer:** Kiro (automated, all 21 lenses)
**Scope:** Full codebase — models, controllers, services, views, JS, tests, config, KiroFlow engine

---

## Executive Summary

Flight Control is a Rails 8.1 app for orchestrating Kiro CLI workflows via a visual editor. The **KiroFlow engine** (`lib/kiro_flow/`) is well-architected and thoroughly tested (unit + 12 property-based tests). The **Rails web layer**, however, has critical gaps: no authentication, no authorization, `eval()` on user-supplied code with no access control, zero Rails-level tests, and no I18n.

**Verdict: 5 Blockers, 7 Critical, 8 Major, 10 Minor, 3 Nits — PR blocked.**

---

## Findings by Severity

### Blockers (must fix before merge)

| # | Lens | Finding | File(s) |
|---|------|---------|---------|
| B1 | Security | **No authentication.** Every endpoint is publicly accessible. No `has_secure_password`, no Devise, no session management. The `layout "authenticated"` name is misleading — it provides no auth. | `app/controllers/application_controller.rb` |
| B2 | Security | **No authorization.** No Pundit, no `authorize` calls, no `policy_scope`. Any visitor can create, edit, delete workflows and agents, and execute arbitrary workflows. | All controllers |
| B3 | Security | **`eval()` with no access control.** `DrawflowConverter` executes `eval(code)` and `eval(cond)` from workflow step definitions. Combined with B1/B2, any anonymous user can execute arbitrary Ruby on the server. The security comment acknowledges this but the prerequisite (trusted-user deployment) is not enforced. | `app/services/drawflow_converter.rb:38,41` |
| B4 | Security | **`ApplicationCable::Connection` references non-existent `Session` model.** `Session.find_by(id: cookies.signed[:session_id])` will raise `NameError` at runtime, crashing every WebSocket connection attempt. | `app/channels/application_cable/connection.rb:11` |
| B5 | Security | **`WorkflowRunChannel` has no authorization.** Any WebSocket client can subscribe to any `workflow_run_{id}` stream and receive real-time execution data, including node outputs. | `app/channels/workflow_run_channel.rb` |

### Critical (must fix before merge)

| # | Lens | Finding | File(s) |
|---|------|---------|---------|
| C1 | Security | **Incomplete XSS escaping in JS.** `workflow_editor_controller.js` uses `innerHTML` extensively with an `esc()` method that only escapes `"` and `<`. Missing escaping for `>`, `&`, and `'`. User-controlled step names and prompts flow through `innerHTML` via `this.esc()`, enabling XSS if a step name contains `&gt;` sequences or event handler attributes. | `app/javascript/controllers/workflow_editor_controller.js` (esc method, ~line 470) |
| C2 | Security | **No rate limiting.** No `rack-attack` gem, no throttling on any endpoint. Workflow execution (`POST /workflows/:id/execute`) can be called without limit, spawning unbounded background jobs. | Gemfile, all controllers |
| C3 | Performance | **N+1 queries on workflows index.** `workflows/index.html.erb` calls `wf.workflow_runs.recientes.limit(5)` and `wf.last_run` inside the `@workflows.each` loop — two N+1 query sets per workflow card. With 24 workflows per page, this is 48+ extra queries. | `app/views/workflows/index.html.erb`, `app/controllers/workflows_controller.rb` |
| C4 | Testing | **Zero Rails-level tests.** No controller tests, no model tests, no system tests, no fixtures. The only tests cover the KiroFlow engine in `spec/`. The entire web layer (3 controllers, 3 models, 2 services, 8 views, 16 components) is untested. | `test/` (empty) |
| C5 | Testing | **No tests for DrawflowConverter.** This is the most security-sensitive service (contains `eval`). No test verifies step sanitization, sub-workflow expansion, circular reference detection, or `MAX_DEPTH` enforcement. | `app/services/drawflow_converter.rb` |
| C6 | Testing | **No ViewComponent tests.** 16 components under `Kreoz::` namespace with zero test coverage. | `app/components/kreoz/` |
| C7 | Security | **`agent_params` bypasses strong params for `context_files`.** `Array(params[:agent][:context_files])` reads directly from raw params without going through `permit`. While the values are stored as JSONB strings, this pattern circumvents Rails' mass assignment protection. | `app/controllers/agents_controller.rb:30` |

### Major (fix before merge preferred)

| # | Lens | Finding | File(s) |
|---|------|---------|---------|
| M1 | I18n | **No Spanish locale file.** Only `en.yml` with a stub `hello: "Hello world"`. All user-facing strings are hardcoded in English in views and controllers. Kreoz convention requires Spanish UI with I18n keys. | `config/locales/en.yml` |
| M2 | I18n | **`raise_on_missing_translations` disabled.** Commented out in `development.rb`. Missing translations silently fall through. | `config/environments/development.rb:62` |
| M3 | Error Handling | **Flash messages hardcoded in English.** `"Workflow created"`, `"Workflow deleted"`, `"Agent deleted"`, `"Workflow started"`, `"Workflow stopped"` — all should use `t()` with Spanish locale keys. | All controllers |
| M4 | Security | **CSP is report-only.** `config.content_security_policy_report_only = true` means the policy is not enforced. Also missing `connect_src` for WebSocket (`wss:`) which will block ActionCable in enforcing mode. | `config/initializers/content_security_policy.rb` |
| M5 | Hotwire | **Stimulus controller too large.** `workflow_editor_controller.js` is 530+ lines with rendering, linking, arrow drawing, execution polling, undo/redo, and persistence all in one controller. Should be split into focused controllers (e.g., `workflow-canvas`, `workflow-linker`, `workflow-runner`). | `app/javascript/controllers/workflow_editor_controller.js` |
| M6 | Accessibility | **No `aria-live` regions for dynamic updates.** Workflow run status changes, node state updates, and toast notifications are injected via JS without screen reader announcements. | `app/javascript/controllers/workflow_editor_controller.js` |
| M7 | Accessibility | **Dialog elements don't trap focus.** The delete confirmation `<dialog>` elements in `workflows/index.html.erb` use native `<dialog>` (which has basic focus trapping) but don't restore focus to the trigger button on close. | `app/views/workflows/index.html.erb` |
| M8 | Multi-Tenancy | **No tenant scoping.** The steering doc expects ActsAsTenant with Empresa, but this app has no multi-tenancy. If this is intentional for Flight Control's scope, document the deviation. If not, it's a blocker. | All models |

### Minor (fix or track as tech debt)

| # | Lens | Finding | File(s) |
|---|------|---------|---------|
| m1 | Database | **Missing `on_delete` on `workflow_runs` FK.** The foreign key from `workflow_runs` to `workflow_definitions` has no `on_delete` strategy (defaults to `:restrict`). The model has `dependent: :destroy` but DB-level cascade would be safer. | `db/migrate/20260418153901_create_workflow_runs.rb` |
| m2 | Concurrency | **`Symbol#>>` monkey-patch.** `workflow.rb` reopens `Symbol` to add `>>` for the chain DSL. This is a global monkey-patch that could conflict with other gems. Consider using refinements instead. | `lib/kiro_flow/workflow.rb:8-12` |
| m3 | Performance | **No pagination metadata.** Index actions paginate with `LIMIT/OFFSET` but don't expose total count, current page, or next/prev links to the UI. | All controllers |
| m4 | Scalability | **`workflow_runs` unbounded growth.** No archival or retention strategy for old runs. The `run_dir` column points to filesystem paths that also accumulate. | `app/models/workflow_run.rb` |
| m5 | Configuration | **No `.env.example` file.** Required environment variables (`RAILS_MASTER_KEY`, `FLIGHT_CONTROL_DATABASE_PASSWORD`, `RAILS_MAX_THREADS`) are not documented. | Project root |
| m6 | Dependency | **No SRI hash on Flowbite CDN script.** `importmap.rb` pins Flowbite from `cdn.jsdelivr.net` without subresource integrity. | `config/importmap.rb:7` |
| m7 | Database | **`max_connections` key in `database.yml`.** Rails 8.1 uses `pool` not `max_connections`. Verify this is the correct key for the version. | `config/database.yml:10` |
| m8 | Code Quality | **`WorkflowExecutionService` polling loop.** Uses `sleep 1` in a `while worker.alive?` loop to poll for cancellation. Consider using `Thread#join` with timeout or a `ConditionVariable` for cleaner signaling. | `app/services/workflow_execution_service.rb:14-22` |
| m9 | Accessibility | **No skip-to-content link.** The sidebar layout requires tabbing through all nav links before reaching main content. | `app/views/layouts/authenticated.html.erb` |
| m10 | Security | **`Agent#materialize!` writes to filesystem.** Creates files under `.kiro/steering/` and `.kiro/agents/` based on agent `nombre` (via `parameterize`). While `parameterize` sanitizes, the pattern of writing user-controlled content to the filesystem deserves a note. | `app/models/agent.rb:8-22` |

### Nits (optional, author's discretion)

| # | Lens | Finding | File(s) |
|---|------|---------|---------|
| n1 | Code Quality | `hello_controller.js` is a Stimulus scaffold leftover. Remove it. | `app/javascript/controllers/hello_controller.js` |
| n2 | Code Quality | `password_validation_controller.js` and `dynamic_fields_controller.js` appear unused by any view in this app. Verify or remove. | `app/javascript/controllers/` |
| n3 | Asset Pipeline | `layouts/application.html.erb` is unused (all pages use `authenticated` layout). Consider removing or documenting its purpose. | `app/views/layouts/application.html.erb` |

---

## Lens-by-Lens Summary

### Lens 1: Security — ❌ BLOCKED

5 blockers (B1–B5), 2 critical (C1, C2, C7). The app has no authentication, no authorization, and executes `eval()` on user-supplied code. This is the most urgent area.

**Recommended fix priority:**
1. Add authentication (even basic `has_secure_password` with session management)
2. Add authorization (Pundit or at minimum `before_action :authenticate`)
3. Fix or remove `ApplicationCable::Connection` Session reference
4. Add channel-level authorization to `WorkflowRunChannel`
5. Add `rack-attack` for rate limiting
6. Fix JS `esc()` function to properly escape all HTML entities
7. Enforce CSP (after adding `wss:` to `connect_src`)

### Lens 2: Multi-Tenancy — ⚠️ N/A (deviation noted)

No multi-tenancy. If Flight Control is a single-tenant tool, this is acceptable but should be documented. If it will join the Kreoz ecosystem with Empresa scoping, this is a blocker.

### Lens 3: Database & Data Integrity — ✅ PASS (minor issues)

Good foundation: UUIDs, `pgcrypto`, CHECK constraints on status, foreign keys with indexes, reversible migrations. Minor: missing `on_delete` strategy on one FK.

### Lens 4: Performance — ❌ CRITICAL

N+1 queries on the main workflows index page. Fix with `includes(:workflow_runs)` or a counter cache.

### Lens 5: Code Quality & Ruby Style — ✅ PASS

Clean, well-structured Ruby. Models are lean, services follow conventions, constants are frozen. The KiroFlow engine DSL is elegant.

### Lens 6: Rails Anti-Patterns — ✅ PASS

Controllers are thin. No callback abuse. Service objects follow the `#call` pattern. No default scopes.

### Lens 7: Testing — ❌ CRITICAL

The KiroFlow engine has excellent test coverage (unit + 12 property-based tests — genuinely impressive). The Rails web layer has zero tests. This asymmetry must be addressed before merge.

### Lens 8: Hotwire — ⚠️ MAJOR

Functional but the main Stimulus controller is too large. No Turbo Frames or Streams used (acceptable for this SPA-like editor pattern). `innerHTML` usage creates XSS surface.

### Lens 9: ViewComponent — ⚠️ MAJOR (no tests)

Components are well-structured with proper `Kreoz::` namespace, keyword args, and VARIANTS hashes. Zero test coverage.

### Lens 10: Error Handling & Logging — ⚠️ MAJOR

`rescue_from` for 404 ✅. Tagged logging ✅. But flash messages are hardcoded English strings, not I18n keys.

### Lens 11: I18n — ❌ MAJOR

No Spanish locale file. No I18n keys. `raise_on_missing_translations` disabled. Every user-facing string is hardcoded.

### Lens 12: Accessibility — ⚠️ MAJOR

Good baseline: semantic HTML, `aria-label` on icon buttons, `aria-hidden` on decorative elements. Missing: `aria-live` for dynamic content, focus management in dialogs, skip-to-content link.

### Lens 13: Concurrency & Thread Safety — ✅ PASS

Proper Mutex usage in KiroFlow Context and Runner. Thread-safe design throughout the engine.

### Lens 14: Dependency Management — ✅ PASS (minor)

Gems pinned correctly. `bundler-audit` and `brakeman` present. Flowbite CDN version pinned. Missing SRI hash.

### Lens 15: Asset Pipeline — ✅ PASS

Propshaft + Importmap configured correctly. Tailwind dynamic classes safelisted. Flowbite integration clean.

### Lens 16: Deployment & Infrastructure — ✅ PASS

Kamal 2 configured. `force_ssl`, `assume_ssl`, proper log level, health check endpoint all present.

### Lens 17: Scalability — ✅ PASS (minor)

Pagination present. OFFSET-based (acceptable at current scale). No archival strategy for workflow runs.

### Lens 18: API Design — ✅ PASS

RESTful routes, correct status codes, proper `respond_to` blocks for HTML/JSON.

### Lens 19: Soft Deletes — N/A

No soft delete pattern. Hard deletes used. Acceptable for current scope.

### Lens 20: Configuration & Environment — ⚠️ MAJOR

Production config is solid. Development config missing `raise_on_missing_translations`. No `.env.example`. Broken `Session` model reference in cable connection.

### Lens 21: Git & PR Hygiene — ✅ PASS

Feature branch, clean `.gitignore`, no committed secrets.

---

## What's Done Well

1. **KiroFlow engine architecture** — Clean separation of concerns: Workflow, Runner, Node types, Context, Persistence, ChainBuilder. The DAG execution with topological ordering, cycle detection, and MAX_CONCURRENT threading is solid.

2. **Property-based testing** — 12 properties covering termination, state coverage, failure propagation, concurrency limits, and timing correctness. This is above-average test quality for a workflow engine.

3. **Database design** — UUIDs, CHECK constraints, proper foreign keys, JSONB for flexible data. Good foundation.

4. **Stimulus controller UX** — The workflow editor has undo/redo, keyboard shortcuts, visual linking with SVG arrows, loop detection, drag-and-drop, and live execution status. Rich interaction well-implemented.

5. **ViewComponent library** — 16 components with consistent patterns: `Kreoz::` namespace, VARIANTS hashes, keyword arguments, semantic Tailwind tokens.

6. **Shell injection prevention** — `ShellNode#safe_interpolate` uses `Shellwords.shellescape` for all interpolated values. Good security practice.

---

## Recommended Action Plan

### Before merge (blockers + critical)

1. **Authentication**: Add `has_secure_password` to a User model, session controller, `before_action :authenticate` in ApplicationController
2. **Authorization**: Add Pundit or simple role checks. At minimum, verify a logged-in user exists
3. **Fix `ApplicationCable::Connection`**: Either create the Session model or remove the reference
4. **Channel auth**: Verify the subscriber owns/can access the workflow run
5. **Rate limiting**: Add `rack-attack` with throttles on login and workflow execution
6. **Fix JS `esc()`**: Replace with proper HTML entity escaping (`&`, `<`, `>`, `"`, `'`)
7. **Fix N+1**: Add `includes(:workflow_runs)` to workflows index query
8. **Add Rails tests**: At minimum — model validations, controller auth/CRUD, DrawflowConverter

### After merge (major + minor)

9. Add Spanish locale file and convert all hardcoded strings to I18n keys
10. Enable `raise_on_missing_translations` in development
11. Enforce CSP (add `wss:` to `connect_src` first)
12. Split `workflow_editor_controller.js` into smaller controllers
13. Add `aria-live` regions for dynamic content
14. Add ViewComponent tests
15. Add `.env.example`
16. Consider replacing `Symbol#>>` monkey-patch with refinements
