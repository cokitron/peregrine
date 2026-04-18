# Kreoz — Code Review Steering

## Purpose

Every pull request goes through this checklist before merge. The reviewer walks each lens in order. A single failure in Security or Data Integrity blocks the PR. Other lenses produce "fix before merge" or "track as tech debt" depending on severity.

This document is tailored to Kreoz's actual stack: Rails 8.1.3, PostgreSQL (UUIDs), has_secure_password, Pundit, ActsAsTenant (Empresa), Hotwire, Tailwind CSS v4 + Flowbite v4, Propshaft, Importmap, Solid Queue/Cache/Cable, Kamal 2, Minitest + fixtures, ViewComponent under `Kreoz::` namespace. Spanish domain, English infrastructure.

---

## Lens 1: Security

### SQL Injection

- Never use string interpolation (`"WHERE name = '#{params[:name]}'"`) in queries. Use parameterized forms: `where("name = ?", val)` or `where(name: val)`.
- Audit every `find_by_sql`, `execute`, `connection.select_all`, and `Arel.sql` call. Each must use bind parameters.
- `order()` with user input is dangerous — Rails does not parameterize ORDER BY. Allowlist sort columns explicitly.
- Reference: [rails-sqli.org](https://rails-sqli.org) for the full attack surface.

### Cross-Site Scripting (XSS)

- Never call `raw`, `html_safe`, or `safe_concat` on user-supplied data. If you must render HTML, sanitize with `sanitize(content, tags: %w[b i em strong])`.
- Verify `<%= %>` (escaped) is used, not `<%== %>` (unescaped), for any dynamic content.
- Watch for `javascript:` protocol in `link_to` when the URL comes from user input. Validate URLs server-side.
- In ViewComponents: pass user content through slots (auto-sanitized), never as constructor string arguments rendered with `raw`.

### Cross-Site Request Forgery (CSRF)

- `protect_from_forgery with: :exception` must be in ApplicationController with no `except:` or `skip_before_action` clauses.
- Every layout must include `<%= csrf_meta_tags %>`.
- GET requests must never perform state changes (create, update, delete).
- Turbo forms include CSRF tokens automatically — verify custom fetch/XHR calls include the token.

### Mass Assignment

- Every controller action uses strong parameters. Verify `permit` lists contain only the fields the user should control.
- Sensitive attributes must never appear in permit: `empresa_id`, `rol_id`, `admin`, `setup_status`, `deleted_at`, `deleted_by`.
- Flag any occurrence of `params.permit!` — this is always a bug.

### Insecure Direct Object References (IDOR)

- Every `find(params[:id])` must be scoped to the current tenant or current user. With ActsAsTenant this is automatic for tenant-scoped models, but verify the model actually has `acts_as_tenant :empresa`.
- For non-tenant models (User, Empresa, Session): verify explicit authorization via Pundit policy.
- Nested resources: verify the parent is scoped before finding the child.

### Authentication

- Kreoz uses `has_secure_password` (Rails built-in), not Devise. Verify:
  - `authenticate_by(email:, password:)` is used (timing-safe), not manual `find_by + authenticate`.
  - Session tokens are regenerated on login (`reset_session` before setting session values).
  - Password reset tokens have expiration and are single-use.
  - Failed login does not reveal whether the email exists ("Invalid email or password" for both cases).

### Authorization

- Every controller action must be authorized via Pundit (`authorize @record` or `policy_scope`).
- Verify `after_action :verify_authorized` or `after_action :verify_policy_scoped` is present.
- Check that Pundit policies scope queries to `Current.empresa`.
- Test authorization boundaries: can a nivel-1 user access nivel-4 actions?

### Secrets & Credentials

- No secrets in source code. Check for hardcoded API keys, passwords, tokens in any file.
- `.env` files must be in `.gitignore`. Use `Rails.application.credentials` or environment variables.
- Filter sensitive params in logs: verify `config.filter_parameters` includes `:password`, `:token`, `:secret`, `:_key`.

### Content Security Policy

- Verify CSP is configured in `config/initializers/content_security_policy.rb`.
- Flowbite CDN JS must be explicitly allowed in `script_src`. No `unsafe-inline` or `unsafe-eval` unless absolutely necessary and documented.
- Report-only mode for new CSP rules before enforcing.

### Rate Limiting

- Kreoz uses `rack-attack`. Verify throttles exist for: login attempts, password resets, API endpoints.
- Check that throttle keys include IP and/or email to prevent brute force.

### Regex Safety

- Ruby regex: use `\A` and `\z` for start/end anchors, never `^` and `$`. Ruby treats strings as multi-line by default, so `^`/`$` match line boundaries, not string boundaries.

### Headers

- `force_ssl = true` in production.
- Verify `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection` headers are set (Rails defaults handle most).
- HSTS should be enabled with a long max-age.

---

## Lens 2: Multi-Tenancy (ActsAsTenant)

This is Kreoz's most critical architectural concern. A tenant leak is a data breach.

### Model Declaration

- Every model with an `empresa_id` column MUST have `acts_as_tenant :empresa`. No exceptions.
- When adding a new model: if it belongs to an Empresa, add `acts_as_tenant` before writing any other code.
- Models WITHOUT tenant scoping: `User` (global lookup for auth), `Empresa` (is the tenant itself), `Session` (has empresa_id but scoped differently).

### Tenant Setting

- Verify `set_current_tenant` runs on every request via `SetTenantContext` concern in ApplicationController.
- Background jobs (Solid Queue): tenant must be set explicitly at the start of `perform`. It is NOT inherited from the enqueuing request.
- Console and rake tasks: wrap in `ActsAsTenant.with_tenant(empresa) { ... }`.

### Dangerous Bypasses

- Flag every occurrence of `.unscoped`, `unscope(:where)`, `ActsAsTenant.without_tenant`. Each needs a comment explaining why and a security review.
- Raw SQL (`find_by_sql`, `connection.execute`) bypasses ActsAsTenant entirely. Every raw query must include `WHERE empresa_id = ?` manually.

### Unique Indexes

- Any unique index on a tenant-scoped model MUST include `empresa_id`. Example: `add_index :roles, [:empresa_id, :nombre], unique: true`, not `add_index :roles, :nombre, unique: true`.
- Uniqueness validations: `validates :nombre, uniqueness: { scope: :empresa_id }`.

### Cross-Tenant Testing

- Every tenant-scoped model should have a test that creates records in two different empresas and verifies they cannot see each other's data.
- Use `with_tenant(empresas(:otra))` to switch context in tests.

---

## Lens 3: Database & Data Integrity

### Migrations

- All tables use `id: :uuid`. Verify `pgcrypto` extension is enabled.
- Every migration must be reversible (`change` method or explicit `up`/`down`). Test rollback in development.
- Large table migrations: use `disable_ddl_transaction!` and `algorithm: :concurrently` for index creation on PostgreSQL.
- Never rename or remove a column in a single deploy. Phase it: add new column → backfill → deploy code using new column → remove old column.

### Indexes

- Every foreign key column must have an index. Check: `empresa_id`, `usuario_id`, `rol_id`, `sucursal_id`, etc.
- Columns used in `WHERE`, `ORDER BY`, or `GROUP BY` clauses need indexes.
- Composite indexes: column order matters. The leftmost column should be the most selective or most frequently queried alone.
- JSONB columns (`direccion` on Sucursal): use GIN indexes if querying inside the JSON.
- Periodically audit unused indexes with `pg_stat_user_indexes` (idx_scan = 0).

### Constraints

- Kreoz convention: string + CHECK for enums. Verify every enum column has both:
  - DB-level: `CHECK (column IN ('value1', 'value2'))` in migration.
  - Model-level: `validates :column, inclusion: { in: CONSTANT }`.
- NOT NULL on required columns. Don't rely solely on `validates :presence`.
- Foreign keys with `on_delete:` strategy (`:cascade`, `:nullify`, or `:restrict`).
- Money columns: `CHECK (monto > 0)` at DB level, not just model validation.

### Data Types

- Money: always INTEGER centavos. Never float, never decimal. `$150.50` → `15050`.
- UUIDs: `t.references :parent, type: :uuid`.
- Timestamps: always include `null: false` on `created_at`/`updated_at`.
- JSONB: use for truly schemaless data (like `direccion`). Don't use JSONB to avoid proper schema design.

### Transactions

- Multi-step operations that must succeed or fail together: wrap in `ActiveRecord::Base.transaction`.
- Don't put side effects (email sending, external API calls) inside transactions — they can't be rolled back.
- Use `after_commit` callbacks for side effects that depend on successful persistence.

---

## Lens 4: Performance

### N+1 Queries

- Every `has_many` / `belongs_to` association accessed in a loop or view partial is a potential N+1.
- Use `includes(:association)` in the controller query. Prefer `preload` (separate queries) for large datasets, `eager_load` (JOIN) when filtering on the association.
- Enable `strict_loading` on critical models or in development to catch N+1s early:
  ```ruby
  Empresa.strict_loading.find(id)
  ```
- Use Bullet gem in development to auto-detect N+1s.

### Query Optimization

- Select only needed columns: `User.select(:id, :nombre, :email)` instead of `User.all` when you don't need every column.
- Use `find_each` / `find_in_batches` for processing large datasets. Never `Model.all.each`.
- Use `size` instead of `count` when the collection is already loaded. Use `exists?` instead of `count > 0`.
- Check `EXPLAIN ANALYZE` output for sequential scans on large tables.

### Caching

- Kreoz uses Solid Cache. Use `Rails.cache.fetch` with explicit TTL for expensive computations.
- Fragment caching in views: `<% cache @record do %>`. Use Russian Doll caching for nested partials.
- Cache keys must include tenant: `"empresa_#{Current.empresa.id}_metrics_#{date}"`.
- Never cache user-specific data in a shared cache key without the user identifier.

### Pagination

- Every `index` action returning a collection must be paginated. Kreoz uses cursor-based pagination for AuditLogs — prefer cursor pagination for large, append-only tables.
- Never load unbounded collections: `Model.all` without `.limit()` in a controller is a red flag.

### Background Jobs

- Any operation taking >100ms that isn't needed for the immediate response should be a background job (Solid Queue).
- Email sending, report generation, data aggregation, external API calls → always background jobs.
- Jobs must be idempotent — safe to retry on failure.

### Memory

- Avoid loading large ActiveRecord collections into memory. Use `find_each`, `pluck`, or raw SQL for bulk operations.
- Watch for string allocations in loops. Use `freeze` on string constants.
- ViewComponent: avoid storing large datasets in instance variables. Pass only what the template needs.

---

## Lens 5: Code Quality & Ruby Style

### Kreoz Conventions

- Spanish domain, English infrastructure. Model names, table names, routes, views, domain variables in Spanish. Infrastructure variables (`is_loading`, `current_user`) in English.
- RuboCop config: method ≤25 lines, class ≤200 lines, ABC complexity ≤30, line length ≤140.
- Frozen string literals: not enforced (disabled in RuboCop config).
- Endless methods allowed: `def entrada? = tipo == "entrada"`.

### SOLID Principles

- **Single Responsibility**: A model >200 lines or a controller action >15 lines is a smell. Extract to concerns (if genuinely shared), service objects, form objects, or query objects.
- **Open/Closed**: Use strategy pattern or polymorphism over long `case`/`if-elsif` chains.
- **Liskov Substitution**: Subclasses must honor parent contracts. Relevant for STI if introduced later.
- **Interface Segregation**: Don't force models to implement methods they don't use via overly broad concerns.
- **Dependency Inversion**: Inject dependencies (especially in services) rather than hardcoding class references.

### Naming

- Predicate methods end with `?`: `def activo?`, `def entrada?`.
- Dangerous methods end with `!`: `def destroy!`, `def reset!`.
- Constants: `SCREAMING_SNAKE_CASE`. `TIPOS = %w[entrada salida].freeze`.
- Scopes: descriptive, chainable. `scope :activos, -> { where(activo: true) }`.

### Code Smells to Flag

- **God Object**: Model with >10 associations or >15 public methods.
- **Feature Envy**: Method that accesses another object's data more than its own.
- **Shotgun Surgery**: A single change requires edits in 5+ files.
- **Long Parameter List**: Method with >3 parameters — use keyword arguments or a parameter object.
- **Mystery Guest**: Test that depends on data not visible in the test body.
- **Primitive Obsession**: Passing raw strings/integers where a value object would be clearer.

---

## Lens 6: Rails Anti-Patterns

### Fat Controllers

- Controller actions should: authenticate, authorize, build/find the record, call save or a service, respond.
- Business logic (calculations, validations beyond simple presence, multi-step workflows) belongs in models or services.
- If a controller action has more than one `if/else` branch, extract the logic.

### Callback Hell

- Callbacks (`before_save`, `after_create`, etc.) should only manipulate the model's own internal state.
- Never in callbacks: send emails, update other models, enqueue jobs, make API calls.
- Use service objects or `after_commit` for side effects.
- If a model has >3 callbacks, it's a smell. Consider extracting to a service.

### Concern Abuse

- A concern used by only one model is hidden complexity, not reuse. Inline it.
- Rule of three: extract to a concern only when three or more models share the behavior.
- Concerns must not depend on each other or on specific model attributes not declared in the concern.
- Kreoz approved concerns: `MoneyFormatting`, `Authentication` (controller), `SetTenantContext`, `SetupGuard`.

### Scope Creep in Scopes

- Scopes should be simple, composable WHERE clauses. Complex logic with joins, subqueries, or conditionals should be query objects in `app/queries/`.
- Default scopes (`default_scope`) are banned. They cause subtle bugs with `unscoped` and make debugging hard.

### Service Object Discipline

- Services live in `app/services/`. Initialize with dependencies, call with `#call`.
- Return value: use `Data.define` structs, not raw hashes or arrays.
- Services should not inherit from each other. Compose, don't inherit.
- One public method (`#call`). Private methods for internal steps.

---

## Lens 7: Testing

### Coverage & Quality

- Every PR must include tests for new behavior. No code without a test (TDD: red → green → refactor).
- Test behavior, not implementation. "Creating a movimiento with valid params succeeds" not "save calls the database".
- One assertion per test when possible. Descriptive test names: `test "rejects negative monto"`.

### Fixture Hygiene

- Kreoz uses fixtures, not factories. Fixtures live in `test/fixtures/` with Spanish plural names.
- Fixtures must be minimal — only the fields needed. Don't set optional fields unless the test requires them.
- Reference fixtures by name: `users(:jorge)`, `empresas(:tienda)`.
- Every tenant-scoped test must wrap in `with_tenant(empresas(:name))`.

### Test Independence

- Tests must not depend on execution order. Each test sets up its own state via `setup` block.
- No shared mutable state between tests. `Current.reset` between tests (handled by Rails automatically).
- Database is rolled back after each test (Rails default with transactions).

### What to Test

| Layer | Test Type | What to Verify |
|-------|-----------|----------------|
| Model | Unit | Validations, scopes, instance methods, associations |
| Service | Unit | Return values, edge cases, error handling |
| Controller | Integration | Auth required, correct response codes, redirects, flash messages |
| System | E2E | Critical user journeys only (login, setup wizard, CRUD flows) |
| Property | Invariant | Money formatting, metric calculations, validation boundaries |
| ViewComponent | Unit | Rendered HTML structure, variant switching, slot rendering |

### Anti-Patterns

- Don't disable authentication in tests. Sign in properly.
- Don't mock ActiveRecord — test against the database.
- Don't test Rails itself (e.g., testing that `validates :presence` works).
- Don't use `sleep` in tests — use Capybara's async matchers (`assert_selector`, `assert_text`).

---

## Lens 8: Hotwire (Turbo + Stimulus)

### Progressive Enhancement

- Every feature must work as a full page load first. Turbo Drive is the free upgrade.
- Escalation path: HTML → CSS → Turbo Frames → Turbo Streams → Stimulus → Custom JS.
- If you're reaching for Stimulus, ask: can Turbo Frames solve this?

### Turbo Frames

- Frame IDs must be unique on the page. Use `dom_id(@record)` for record-specific frames.
- Every frame must have a fallback — if JS fails, the link should still work (`data-turbo-frame="_top"` for breakout).
- Lazy-loaded frames (`loading: :lazy`) must have a loading indicator.
- Don't nest frames more than 2 levels deep — it becomes hard to debug.

### Turbo Streams

- Verify stream actions target correct DOM IDs. A typo in the target silently fails.
- `respond_to` must handle both `format.html` (redirect) and `format.turbo_stream`.
- Validation failures must return `status: :unprocessable_entity` — Turbo requires this.
- WebSocket broadcasts (`broadcasts_to`): verify the channel is authenticated and tenant-scoped.

### Stimulus Controllers

- One controller per behavior. Keep controllers <50 lines.
- Use `static targets` for DOM references, `static values` for state. Never query the DOM manually.
- `connect()` for setup, `disconnect()` for cleanup (remove event listeners, cancel timers).
- Controller names: kebab-case in HTML (`data-controller="numeric-keyboard"`), snake_case files (`numeric_keyboard_controller.js`).
- No business logic in Stimulus. It's for UI behavior only.

### Common Pitfalls

- Turbo Drive caches pages — Stimulus controllers must handle `connect`/`disconnect` properly for cached page restoration.
- `data-turbo-permanent` elements persist across navigations — verify they don't hold stale state.
- Forms inside Turbo Frames: the response must contain a matching frame, or use `data-turbo-frame="_top"`.

---

## Lens 9: ViewComponent

### Structure

- All components under `Kreoz::` namespace in `app/components/kreoz/`.
- Use keyword arguments for all params. No positional arguments.
- Use `VARIANTS` / `STATES` hashes for variant-driven styling.
- Use `renders_one` / `renders_many` for slot-based components.

### Security

- Pass user content through slots, not constructor string arguments. Slots get Rails' HTML sanitization automatically.
- Never use `raw` or `html_safe` on user-provided content inside a component template.
- If a component accepts a URL parameter, validate it server-side (no `javascript:` protocol).

### Design Tokens

- Use Flowbite semantic tokens: `bg-brand`, `text-heading`, `rounded-base`, `border-default`.
- Never use raw Tailwind colors (`bg-blue-500`) — always use the semantic token that maps to the theme.
- Check `/galeria` to verify the component renders correctly with the Kreoz theme.

### Testing

- Every component must have a unit test using `render_inline`.
- Test all variants: `render_inline(Kreoz::BadgeComponent.new(variant: :success))`.
- Test slot rendering: verify slots produce expected HTML structure.
- Preview classes (`Kreoz::ButtonComponentPreview`) for visual testing in `/galeria`.

### Performance

- Components should not make database queries. Pass data in from the controller.
- Avoid storing large collections in component instance variables.
- Use `#render?` to conditionally skip rendering instead of wrapping the entire template in a conditional.

---

## Lens 10: Error Handling & Logging

### Controller Error Handling

- `rescue_from` in ApplicationController for common errors:
  - `ActiveRecord::RecordNotFound` → 404
  - `Pundit::NotAuthorizedError` → 403 or redirect with flash
  - `ActsAsTenant::Errors::NoTenantSet` → redirect to login
- Never rescue `Exception` — always rescue `StandardError` or more specific classes.
- Never swallow errors silently (`rescue => e; end`). At minimum, log the error.

### Logging

- Use tagged logging: `Rails.logger.tagged("Empresa:#{Current.empresa&.id}") { ... }`.
- Log at appropriate levels: `debug` for development tracing, `info` for business events, `warn` for recoverable issues, `error` for failures.
- Never log sensitive data: passwords, tokens, full credit card numbers, personal identification numbers.
- Verify `config.filter_parameters` covers all sensitive fields.

### User-Facing Errors

- Flash messages in Spanish. Use I18n keys, not hardcoded strings.
- Validation errors render inline on the form (re-render with `status: :unprocessable_entity`).
- 404 and 500 pages must be styled and helpful, not the Rails default.

### Background Job Errors

- Jobs must handle their own errors gracefully. Use `retry_on` with backoff for transient failures.
- Use `discard_on` for permanent failures (e.g., record deleted between enqueue and execution).
- Log job failures with context: job class, arguments, attempt number, error message.

---

## Lens 11: Internationalization (I18n)

### Kreoz Convention: Spanish Domain

- All user-facing text must be in Spanish. Headings, flash messages, labels, button text, error messages — all Spanish.
- Use I18n locale files (`config/locales/es.yml`) for all user-facing strings. Never hardcode Spanish strings in views or controllers.
- Use lazy lookup in views: `t('.title')` resolves to `es.sucursales.index.title`.
- Model error messages: configure in `es.activerecord.errors.models`.

### I18n Safety

- Keys ending in `_html` are marked HTML-safe by Rails — use only for trusted content, never for user input.
- Never concatenate translated strings: `t('greeting', name: @user.nombre)` not `t('hello') + " " + @user.nombre`.
- Use `I18n.l` for date/time/currency formatting, not manual `strftime`.
- Set locale per-request in a `before_action`, never globally.

### Missing Translations

- Verify `config.i18n.raise_on_missing_translations = true` in development/test.
- Every new view or flash message must have a corresponding locale key.
- Run `i18n-tasks missing` (if available) to detect untranslated keys.

---

## Lens 12: Accessibility (WCAG 2.2 AA)

### Forms

- Every `<input>`, `<select>`, and `<textarea>` must have an associated `<label>` with a matching `for` attribute, or use `aria-label`.
- Required fields: use `aria-required="true"` and the `required` HTML attribute.
- Validation errors: use `aria-invalid="true"` on the field and `aria-describedby` pointing to the error message element.
- Group related inputs with `<fieldset>` and `<legend>` (e.g., radio buttons, address fields).
- On validation failure, move focus to the first error field.

### Semantic HTML

- Use landmark elements: `<nav>`, `<main>`, `<header>`, `<footer>`, `<aside>`, `<section>`.
- Heading levels must increase by one — no skipping from `<h1>` to `<h3>`.
- Every page must have exactly one `<h1>`.
- All images must have `alt` text. Decorative images: `alt=""` and `aria-hidden="true"`.
- Links and buttons must have accessible names — no empty `<a>` or `<button>` tags. Icon-only buttons need `aria-label`.

### Keyboard Navigation

- All interactive elements must be keyboard-accessible (focusable, activatable with Enter/Space).
- Tab order must follow visual reading order. Don't use `tabindex` > 0.
- Visible focus indicators on all interactive elements — never `outline: none` without a replacement.
- No keyboard traps — the user must be able to Tab away from any element.
- Modals and drawers: trap focus inside when open, restore focus to trigger on close.

### Color & Contrast

- Text contrast ratio: ≥4.5:1 for normal text, ≥3:1 for large text (18px+ or 14px+ bold).
- Never convey information by color alone — use icons, text, or patterns as secondary indicators.
- Verify the UI is usable in Windows High Contrast Mode.
- Test with Flowbite's dark mode if applicable.

### Dynamic Content (Hotwire)

- Turbo Stream updates: announce changes to screen readers with `aria-live="polite"` regions.
- Turbo Frame navigation: verify focus management after frame replacement.
- Stimulus-driven visibility toggles: use `aria-expanded`, `aria-hidden`, `aria-controls` appropriately.
- Toast notifications: use `role="alert"` or `aria-live="assertive"` for time-sensitive messages.

### Tooling

- Run `axe-core` in system tests for automated accessibility checks.
- Run Lighthouse accessibility audits on key pages.
- Manual testing: navigate the entire flow using only keyboard. Test with VoiceOver (macOS) or NVDA (Windows).

---

## Lens 13: Concurrency & Thread Safety

### Puma Threading Model

- Kreoz runs on Puma, which uses threads. All application code must be thread-safe.
- Never use mutable class variables (`@@var`) or global state (`$var`) for request-scoped data.
- Use `ActiveSupport::CurrentAttributes` (`Current.empresa`, `Current.session`) for per-request state — it is automatically reset between requests.

### Shared Mutable State

- Constants must be frozen: `TIPOS = %w[entrada salida].freeze`. Unfrozen constants can be mutated across threads.
- Class-level instance variables (`@cache` on a class) are shared across threads — protect with `Mutex` or use `Concurrent::Map`.
- Avoid lazy initialization patterns in class methods without synchronization:
  ```ruby
  # BAD — race condition
  def self.instance
    @instance ||= new
  end

  # OK — use Mutex
  MUTEX = Mutex.new
  def self.instance
    MUTEX.synchronize { @instance ||= new }
  end
  ```

### Database Connections

- Connection pool size (`pool` in `database.yml`) must be ≥ Puma's `max_threads`.
- Solid Queue workers need their own connection pool — verify `config/queue.yml` settings.
- Never hold a database connection across a long-running operation (external API call, file I/O).

### Background Jobs

- Solid Queue jobs run in separate threads/processes. They do NOT share request context.
- Every job must set its own tenant: `ActsAsTenant.with_tenant(Empresa.find(empresa_id)) { ... }`.
- Jobs must be idempotent — safe to run multiple times with the same arguments.
- Use `ActiveJob::Uniqueness` or application-level locking if duplicate execution is dangerous.

### ActionCable / Solid Cable

- WebSocket connections are long-lived — verify they don't leak memory or hold stale references.
- Channel subscriptions must verify tenant authorization.
- Broadcasts are async — don't assume ordering.

---

## Lens 14: Dependency Management & Supply Chain

### Gem Policy

- Kreoz approved gems (beyond Rails defaults): `devise` (if migrated to), `acts_as_tenant`, `view_component`, `pundit`, `rack-attack`, `propcheck`.
- Any new gem requires explicit justification. Prefer Rails built-in solutions first.
- Pin gem versions with pessimistic constraint: `gem "pundit", "~> 2.4"`. Never use open-ended `>=`.

### Vulnerability Scanning

- Run `bundle audit check --update` before every deploy and in CI.
- Run `bin/brakeman -q --no-pager` for static security analysis.
- Review Dependabot/Snyk alerts promptly — security patches within 48 hours.

### Typosquatting & Supply Chain

- Verify gem names match official packages. Watch for: `rack-attck` vs `rack-attack`, `pundt` vs `pundit`.
- Only use `https://rubygems.org` as a gem source. No custom gem servers without security review.
- Review new gem's GitHub repo: check stars, recent commits, maintainer reputation, open issues.

### JavaScript Dependencies

- Kreoz uses Importmap — no npm/yarn for application JS. Flowbite JS loads from CDN.
- Verify CDN URLs use exact version pins (not `@latest`): `flowbite@4.0.1`, not `flowbite@latest`.
- Flowbite CSS is installed via npm for Tailwind plugin — pin exact version in `package.json`.
- Subresource Integrity (SRI) hashes on CDN scripts when possible.

### Maintenance

- Run `bundle outdated` monthly. Update gems incrementally, not all at once.
- Use `bundle update --conservative gem_name` to update one gem without cascading changes.
- Remove unused gems. A gem in the Gemfile that nothing requires is attack surface for free.

---

## Lens 15: Asset Pipeline & Frontend

### Propshaft

- Kreoz uses Propshaft (not Sprockets). Assets are served from `app/assets/` with content-based fingerprinting.
- Use Rails asset helpers (`asset_path`, `image_tag`, `stylesheet_link_tag`) — never hardcode asset paths.
- Verify `assets:precompile` succeeds in CI. A broken asset pipeline breaks production.

### Importmap

- All JS dependencies pinned in `config/importmap.rb`. No Node.js bundler.
- Verify pins use exact versions, not ranges.
- Stimulus controllers auto-register from `app/javascript/controllers/` — verify new controllers are picked up.
- No inline `<script>` tags in views — use Stimulus controllers or importmap pins.

### Tailwind CSS v4 + Flowbite v4

- CSS is compiled by `tailwindcss-rails` gem from `app/assets/tailwind/application.css`.
- Flowbite theme and plugin are imported in the CSS file. Brand colors override Flowbite defaults.
- After adding new Tailwind classes, rebuild CSS: `bin/rails tailwindcss:build`. Stale CSS is a common source of "classes not working."
- Dynamic class construction in ERB (`"bg-primary-#{shade}"`) is invisible to Tailwind's scanner — use safelist or write full class names.

### Image & Media Assets

- Optimize images before committing. No uncompressed PNGs >100KB.
- Use `image_tag` with explicit `width`/`height` to prevent layout shift (CLS).
- Lazy-load below-the-fold images: `loading: "lazy"`.

---

## Lens 16: Deployment & Infrastructure

### Pre-Deploy Checklist

- All tests pass: `bin/rails test && bin/rails test:system`.
- Static analysis clean: `bin/rubocop -a && bin/brakeman -q --no-pager`.
- Assets precompile: `bin/rails assets:precompile`.
- Migrations tested: run `bin/rails db:migrate` and `bin/rails db:rollback` in staging.

### Kamal 2

- Kreoz deploys with Kamal 2. Verify `config/deploy.yml` is correct.
- Zero-downtime deploys: migrations must be backward-compatible with the previous code version.
- Health check endpoint must respond before Kamal routes traffic to the new container.
- Rollback plan: `kamal rollback` must work. Test it periodically.

### Environment Configuration

- `force_ssl = true` in production. No exceptions.
- `config.log_level = :info` in production (not `:debug` — too verbose, may leak data).
- `config.filter_parameters` must include all sensitive fields.
- Database connection pool sized for Puma threads + Solid Queue workers.

### Zero-Downtime Migration Rules

- Adding a column: safe (nullable or with default).
- Removing a column: two-step. First deploy ignores the column (`self.ignored_columns += ["old_col"]`), second deploy removes it.
- Renaming a column: never in one step. Add new → backfill → deploy using new → remove old.
- Adding an index: use `algorithm: :concurrently` with `disable_ddl_transaction!`.
- Adding a NOT NULL constraint: add as nullable first, backfill, then add constraint.

### Monitoring

- Application Performance Monitoring (APM): track response times, throughput, error rates.
- Database monitoring: slow query log, connection pool usage, table bloat.
- Background job monitoring: queue depth, failure rate, processing time.
- Uptime monitoring: external health check hitting the app every minute.

---

## Lens 17: Scalability

### Database Scalability

- Identify tables that will grow unbounded (audit_logs, movimientos). Plan for partitioning or archival.
- Use cursor-based pagination for large tables (Kreoz already does this for AuditLogs). Never OFFSET-based pagination on tables >100K rows.
- JSONB columns: use GIN indexes for queries, but don't over-index — GIN indexes are expensive to maintain.
- Connection pooling: PgBouncer in front of PostgreSQL if connection count becomes a bottleneck.

### Application Scalability

- Horizontal scaling: Kreoz runs on Puma behind Kamal. Verify the app is stateless — no in-memory session storage, no local file uploads.
- Solid Cache: monitor cache hit ratio. Low hit ratio means the cache isn't helping.
- Solid Queue: monitor queue depth. If jobs back up, add workers or optimize job performance.
- ActionCable / Solid Cable: WebSocket connections are memory-intensive. Monitor connection count per server.

### Read-Heavy Optimization

- Dashboard and reporting queries: cache aggressively with tenant-scoped keys.
- Consider read replicas for reporting if the primary database becomes a bottleneck.
- Materialized views for complex aggregations that don't need real-time accuracy.

### Write-Heavy Optimization

- Batch inserts for bulk operations: `insert_all` instead of individual `create` calls.
- Defer non-critical writes to background jobs.
- Use database advisory locks for operations that must be serialized.

---

## Lens 18: API Design (Internal & Future External)

Kreoz currently serves HTML only, but internal patterns matter for Turbo Stream responses and future API needs.

### Response Conventions

- HTML responses: always set correct status codes. `200` for success, `422` for validation failure, `404` for not found, `403` for unauthorized.
- Turbo Stream responses: `respond_to` must handle both `format.html` and `format.turbo_stream`.
- Redirects after successful mutations. Re-render with errors after failures.

### URL Design

- RESTful resources with Spanish paths. Follow Rails conventions.
- Nested resources only one level deep: `/empresas/:id/sucursales`, not `/empresas/:id/sucursales/:id/usuarios`.
- Collection actions use descriptive names: `exportar`, `restablecer`.

### Future API Readiness

- Keep business logic in models and services, not controllers. This makes it easy to add API controllers later.
- Use Pundit policies consistently — they work for both HTML and API authorization.
- If adding an API: version it (`/api/v1/`), use token auth (not session), paginate all collections, return structured error responses.

---

## Lens 19: Soft Deletes & Data Lifecycle

### Kreoz Soft Delete Pattern

- Models with `deleted_at` and `deleted_by` columns use soft deletes.
- Verify `scope :kept` is defined and used as the default query scope in controllers.
- Hard deletes (`destroy`) should only happen in background cleanup jobs, never in controller actions.
- Soft-deleted records must still respect tenant scoping.

### Data Retention

- Audit logs are append-only and immutable after creation. Verify no `update` or `destroy` actions exist.
- Define retention policies for large tables. Old audit logs may need archival.
- GDPR/privacy: if user deletion is requested, soft delete is not enough — PII must be anonymized or purged.

### Cascading Deletes

- Verify `dependent:` is set on all `has_many` associations. Choose carefully:
  - `:destroy` — runs callbacks on each child (slow but safe).
  - `:delete_all` — skips callbacks (fast but may leave orphans).
  - `:nullify` — sets FK to NULL (preserves child records).
  - `:restrict_with_error` — prevents deletion if children exist.
- Soft-deleted parents: verify children are still accessible for reporting but hidden from active queries.

---

## Lens 20: Configuration & Environment Hygiene

### Rails Configuration

- Verify `config/environments/production.rb` has:
  - `config.force_ssl = true`
  - `config.log_level = :info`
  - `config.active_record.dump_schema_after_migration = false`
  - `config.action_mailer.raise_delivery_errors = true` (if sending email)
- Verify `config/environments/development.rb` has:
  - `config.i18n.raise_on_missing_translations = true`
  - Bullet gem enabled (if installed)

### Initializers

- Review every file in `config/initializers/`. Each should have a clear purpose.
- No business logic in initializers — only configuration.
- Initializers must not make network calls or database queries at boot time.

### Environment Variables

- All secrets via `Rails.application.credentials` or ENV vars. Never in source code.
- Document required ENV vars in a `.env.example` file (without actual values).
- Verify `.env` is in `.gitignore`.

---

## Lens 21: Git & PR Hygiene

### Commit Quality

- Each commit should be a single logical change. No "fix everything" commits.
- Commit messages: imperative mood, <72 chars first line. Body explains why, not what.
- No committed secrets, `.env` files, editor configs, or OS files (`.DS_Store`).

### PR Structure

- PR title: concise, <70 chars. Reference ticket/issue number.
- PR description: what changed, why, what was tested, any deployment notes.
- Keep PRs small (<400 lines changed). Large PRs get split.
- No unrelated changes in a PR. Refactoring goes in a separate PR from feature work.

### Branch Strategy

- Feature branches off `main`. Never commit directly to `main`.
- Branch names: `feature/setup-wizard`, `fix/tenant-leak-audit-logs`, `chore/update-flowbite`.
- Delete branches after merge.

---

## Review Severity Guide

| Severity | Action | Examples |
|----------|--------|---------|
| **Blocker** | Must fix before merge | Security vulnerability, tenant leak, data loss risk, broken auth |
| **Critical** | Must fix before merge | Missing test for new behavior, N+1 in a list view, missing authorization |
| **Major** | Fix before merge preferred | Fat controller, missing index on FK, hardcoded Spanish string |
| **Minor** | Fix or track as tech debt | Naming inconsistency, missing `freeze` on constant, verbose code |
| **Nit** | Optional, author's discretion | Style preference, alternative approach suggestion |

---

## Automated Checks (CI Pipeline)

These must pass before a PR can be reviewed:

```bash
bin/rails test                    # Unit + integration tests
bin/rails test:system             # System tests (if applicable)
bin/rubocop                       # Style + security linting
bin/brakeman -q --no-pager        # Static security analysis
bundle audit check --update       # Gem vulnerability scan
bin/rails assets:precompile       # Asset pipeline integrity
bin/rails runner "puts 'Boot OK'" # Application boots cleanly
```

A failure in any of these blocks the PR. No exceptions.
