# Re-Review Verdict — Flight Control

**Date:** 2026-04-18
**Reviewer:** Kiro (re-review against CODE_REVIEW.md)
**Scope:** Verify whether blocker/critical findings from initial review have been addressed
**Cross-ref:** Trilium QA §9 "Frontend — Cross-Cutting Concerns"

---

## Verdict: ❌ PR REMAINS BLOCKED — Request Changes

The fix commit `8f0c4aa` addressed infrastructure-level items (force_ssl, CSP scaffold, pagination, rescue_from, .env.example, FK+index, CHECK constraint, aria-labels). **None of the 5 blockers or 7 critical findings have been resolved.** The app remains publicly accessible with no authentication, no authorization, and `eval()` on user-supplied code.

---

## Blocker Status (5/5 still open)

| # | Finding | Status | Evidence |
|---|---------|--------|----------|
| B1 | No authentication | ❌ OPEN | `ApplicationController` has no `before_action :authenticate`, no User model, no `has_secure_password`. Every endpoint is public. |
| B2 | No authorization | ❌ OPEN | No `pundit` in Gemfile. No `authorize` calls in any controller. No `policy_scope`. |
| B3 | `eval()` with no access control | ❌ OPEN | `drawflow_converter.rb:38,41` — `eval(code)` and `eval(cond)` still present. Security comment added but the prerequisite (trusted-user deployment) is not enforced since B1/B2 are open. |
| B4 | `Session` model reference crashes WebSocket | ❌ OPEN | `application_cable/connection.rb:11` — `Session.find_by(...)` references a model that does not exist. Every WebSocket connection will raise `NameError`. |
| B5 | `WorkflowRunChannel` has no authorization | ❌ OPEN | `workflow_run_channel.rb` — `stream_from "workflow_run_#{params[:run_id]}"` with no access check. Any client can subscribe to any run. |

## Critical Status (7/7 still open)

| # | Finding | Status | Evidence |
|---|---------|--------|----------|
| C1 | Incomplete XSS `esc()` | ❌ OPEN | `workflow_editor_controller.js:764` — `esc(s)` only escapes `"` and `<`. Missing `>`, `&`, `'`. Used with `innerHTML` throughout. |
| C2 | No rate limiting | ❌ OPEN | No `rack-attack` in Gemfile. `POST /workflows/:id/execute` can spawn unbounded background jobs. |
| C3 | N+1 on workflows index | ❌ OPEN | `workflows/index.html.erb` calls `wf.workflow_runs.recientes.limit(5)` and `wf.last_run` inside `@workflows.each` loop. Controller has no `includes`. |
| C4 | Zero Rails-level tests | ❌ OPEN | `test/controllers/`, `test/models/`, `test/system/` are empty directories with only `.keep` files. |
| C5 | No DrawflowConverter tests | ❌ OPEN | Most security-sensitive service (contains `eval`) has zero test coverage. |
| C6 | No ViewComponent tests | ❌ OPEN | 16 components under `Kreoz::` namespace, zero tests. |
| C7 | `context_files` bypasses strong params | ❌ OPEN | `agents_controller.rb:30` — `Array(params[:agent][:context_files])` reads raw params outside `permit`. |

## Major Status (spot-checked, all still open)

| # | Finding | Status |
|---|---------|--------|
| M1 | No Spanish locale file | ❌ Only `en.yml` with stub `hello: "Hello world"` |
| M2 | `raise_on_missing_translations` disabled | ❌ Still commented out in `development.rb:65` |
| M4 | CSP report-only, missing `wss:` | ❌ `content_security_policy_report_only = true`, no `wss:` in `connect_src` |
| M6 | No `aria-live` regions | ❌ No `aria-live` in layouts or JS |
| M9 | No skip-to-content link | ❌ Not present in `authenticated.html.erb` |

## What the fix commit DID address

These items from the original review were resolved by `8f0c4aa`:

- ✅ `force_ssl` + `assume_ssl` enabled in production
- ✅ Dockerfile Ruby version corrected (3.2.2 → 3.4.8)
- ✅ Security warning comment on `eval` in DrawflowConverter
- ✅ Shell injection fix in ShellNode (`Shellwords.shellescape`)
- ✅ `params.permit!` removed, replaced with allowlisted key sanitization
- ✅ CSP initializer created (report-only mode)
- ✅ `agents#new` GET changed to `agents#create` POST
- ✅ FK + index on `workflow_definitions.default_agent_id`
- ✅ CHECK constraint on `workflow_runs.status`
- ✅ Pagination added (PER_PAGE=24) to all index actions
- ✅ `rescue_from ActiveRecord::RecordNotFound` in ApplicationController
- ✅ `WorkflowExecutionService` extracted from job
- ✅ `aria-label` on icon-only buttons
- ✅ `.env.example` added

## Trilium QA §9 Cross-Reference

The "Frontend — Cross-Cutting Concerns" test plan (note `GsJxjLdxANtA`) is written for the Kreoz Finanzas module. Most items (sidebar modules, currency formatting, CFDI detail pages, PLD error handling, sucursal switcher) are **not applicable** to Flight Control.

Cross-cutting items that **do apply** and remain unaddressed:

| QA Item | Applicability | Status |
|---------|--------------|--------|
| 9.1.3 Route guards enforce RBAC | ✅ Applies | ❌ No auth/authz exists |
| 9.2.6 Empty states | ✅ Applies | ✅ `EmptyStateComponent` used |
| 9.3.1 Client-side validation matches server-side | ✅ Applies | ❌ No client-side validation |
| 9.3.2 API error messages displayed to user | ✅ Applies | ⚠️ Partial — JSON errors returned but no structured RFC 9457 format |
| 9.4.3 Session expired → redirect to login | ✅ Applies | ❌ No session management exists |

---

## Required Changes Before Merge

Priority order — each item unblocks the next:

### 1. Authentication (unblocks B1, B3, B4)
- Add a `User` model with `has_secure_password`
- Add a `Session` model (fixes B4 — the cable connection already expects it)
- Add `SessionsController` with login/logout
- Add `before_action :authenticate` in `ApplicationController`

### 2. Authorization (unblocks B2, B5)
- Add `pundit` gem and basic policies
- Add `authorize` calls in all controller actions
- Add channel-level auth in `WorkflowRunChannel` (verify subscriber can access the run)

### 3. Rate Limiting (unblocks C2)
- Add `rack-attack` gem
- Throttle login attempts and workflow execution endpoint

### 4. Fix XSS escaping (unblocks C1)
- Replace `esc()` with proper HTML entity escaping for all 5 characters: `&`, `<`, `>`, `"`, `'`

### 5. Fix N+1 (unblocks C3)
- Add `includes(:workflow_runs)` to `WorkflowsController#index` query
- Or use a counter cache for run counts + a single query for recent runs

### 6. Fix strong params bypass (unblocks C7)
- Route `context_files` through `permit` properly

### 7. Add tests (unblocks C4, C5, C6)
- Model tests for validations and associations
- Controller integration tests for auth + CRUD
- `DrawflowConverter` unit tests (especially `eval` paths, `MAX_DEPTH`, circular refs)
- ViewComponent unit tests for at least the most-used components

---

**Bottom line:** The infrastructure fixes in `8f0c4aa` were good housekeeping, but the security foundation (auth + authz) was not built. Until items 1–2 above are in place, the remaining fixes are moot — there's no point rate-limiting or fixing XSS on an app that has no login gate. Start with authentication.
