# KiroFlow — Ruby & Rails Steering Document
# For a 20-year Rails veteran. No hand-holding. Just the delta.

## Target Stack
- Ruby 3.4.x (Prism parser, YJIT default-on in production)
- Rails 8.0+ (Solid trifecta, Propshaft, Kamal 2)
- This project: pure Ruby scripts (no Rails app), but Rails conventions inform design

---

## Ruby 3.4 — What Actually Changed

### Language

**`it` is the new `_1`.**
Anonymous block parameter. Unlike `_1`, it nests correctly and reads like English.
```ruby
users.select { it.active? }.map { it.name }
# Nests properly:
[[1,2],[3,4]].each { it.each { p it } } # inner `it` = inner block arg
```
Caveat: `it` as a local variable in the same scope takes precedence. If you have a method named `it` (looking at you, RSpec), the anonymous parameter wins inside blocks.

**Frozen string literals: deprecation warnings are live.**
Mutating a string literal now warns under `-W:deprecated`. Strings are "chilled" — not frozen, but warning. Likely frozen-for-real in a future version (though 4.0 backed off).
```ruby
buf = ""
buf << "x"  # warning: literal string will be frozen in the future
buf = +""   # unary plus = mutable string, no warning
```
`Symbol#to_s` also returns chilled strings now. If you do `:foo.to_s << "_bar"`, you get a warning.

**`**nil` unpacks to empty kwargs.**
```ruby
handle(**nil)                          # same as handle(**{})
handle(**(extra_opts if condition?))   # clean conditional kwargs
```

**`#[]=` no longer accepts keyword args or blocks.** `a[0, kw: 1] = 2` and `a[0, &b] = 1` are now SyntaxError.

**`::Ruby` is reserved.** Defining `Ruby = ...` at top level warns. The module will be populated in a future version.

**Unused block warnings** (opt-in via `Warning[:strict_unused_block] = true`). Passing a block to a method that never yields/accepts it now warns.

### Core Classes

| What | Detail |
|------|--------|
| `Array#fetch_values` | Like `Hash#fetch_values`. Raises on missing index, accepts default block. |
| `Hash.new(capacity: n)` | Pre-allocate. **Breaking**: `Hash.new(key: val)` no longer works as positional default — wrap in `{}`. |
| `Hash#inspect` | Now uses modern syntax: `{x: 1, "foo" => 2}` with spaces around `=>`. May break snapshot tests. |
| `String#append_as_bytes` | Binary buffer building without encoding validation. |
| `MatchData#bytebegin/#byteend` | Byte-offset counterparts to `#begin/#end`. |
| `Time#xmlschema/#iso8601` | Moved to core from `time` stdlib. No `require` needed. |
| `Range#step` | Now uses `+` for all types, not just numerics. `(time_a..time_b).step(6.hours)` works. |
| `Range#size` | Raises `TypeError` for non-iterable ranges (Float, Time). Was silently returning nil/wrong values. |
| `Integer#**` / `Rational#**` | Returns Integer/Rational instead of `Float::INFINITY` for large results. Raises if extremely large. |
| `Warning.categories` | Returns `[:deprecated, :experimental, :performance, :strict_unused_block]`. |
| `GC.config` | Get/set GC config. `rgengc_allow_full_mark: false` disables major GC. |

### Ractor (finally getting usable)

- `require` works in non-main Ractors (delegates to main Ractor)
- `Ractor.main?` — check if you're on the main Ractor
- `Ractor[]` / `Ractor[]=` — Ractor-local storage (like `Thread[]` but scoped)
- `Ractor.store_if_absent(key) { init }` — thread-safe lazy init

### Implementation

- **Prism is the default parser.** `--parser=parse.y` for the old one. Prism is faster, more error-tolerant.
- **YJIT improvements**: compressed context metadata, register allocation for locals, inlined trivial methods, `Array#each/select/map` rewritten in Ruby for YJIT optimization. 3x faster than interpreter on benchmarks.
- **Modular GC**: alternative GC implementations loadable at runtime via `RUBY_GC_LIBRARY`. Experimental MMTk (Rust-based) GC available.
- **JSON.parse ~1.5x faster** than json-2.7.x.
- **Backtrace format changed**: single quotes instead of backticks, class name before method name (`'Calculator#divide'` not `` `divide' ``). Will break tests that match error messages.

### Breaking / Watch Out

- `Hash.new(key: val)` is now `ArgumentError` — use `Hash.new({key: val})`
- `URI` default parser switched to RFC 3986 from RFC 2396
- `Refinement#refined_class` removed (use `#target`)
- `Timeout.timeout` rejects negative values
- Several default gems became bundled (csv, bigdecimal, mutex_m, drb, observer, etc.) — add to Gemfile if you use them
- `Regexp.timeout` set to 1s by default in Rails 8 (ReDoS protection)

---

## Rails 8.0 — What Actually Changed

### The Solid Trifecta (Redis/Memcached replacement)

All three are database-backed, enabled by default in new apps. Skip with `--skip-solid`.

**Solid Queue** — Job backend. Replaces Sidekiq/Resque/DelayedJob for most workloads. Uses `FOR UPDATE SKIP LOCKED` (Postgres 9.5+, MySQL 8.0+, SQLite).
```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

**Solid Cache** — Fragment cache store. Replaces Redis/Memcached for HTML caching. Database-backed, uses disk instead of RAM.

**Solid Cable** — WebSocket pubsub. Replaces Redis for Action Cable. Messages retained in DB for 1 day by default.

### Deployment

**Kamal 2** — Zero-downtime deploys from a single `kamal setup`. Includes Kamal Proxy (replaces Traefik). Pre-configured in new apps.

**Thruster** — Sits in front of Puma in the Dockerfile. Provides X-Sendfile acceleration, asset caching, and compression. No nginx needed for simple deployments.

### Asset Pipeline

**Propshaft is the default.** Sprockets is gone from new apps. Propshaft is simpler — no compilation, just fingerprinting and serving. If you need transpilation, use jsbundling-rails/cssbundling-rails alongside it.

### Authentication Generator

```bash
bin/rails generate authentication
```
Generates models, controllers, views, routes, and migrations for session-based auth with password reset. Starting point, not a full solution.

### Notable API Changes

**`params#expect`** — Safer params handling:
```ruby
# Old
params.require(:user).permit(:name, :email)
# New
params.expect(user: [:name, :email])
```

**`db:migrate` on fresh DB** now loads schema first, then runs pending migrations. Previous behavior (run all migrations from scratch) available via `db:migrate:reset`.

**Active Storage**: Azure backend deprecated.

**Active Support**: `Benchmark.ms` deprecated. Addition/`since` between two Time objects deprecated.

**Active Job**: `enqueue_after_transaction_commit` deprecated. SuckerPunch adapter deprecated.

### Removals from 8.0

- `config.active_record.commit_transaction_on_non_local_return`
- `config.active_record.allow_deprecated_singular_associations_name`
- `config.active_record.warn_on_records_fetched_greater_than`
- `config.active_record.sqlite3_deprecated_warning`
- `ActiveRecord::ConnectionAdapters::ConnectionPool#connection`
- Keyword-based `enum` definition (use positional hash)
- `ActiveSupport::ProxyObject`
- `Rails::ConsoleMethods` extension pattern
- `config.read_encrypted_secrets`

---

## Implications for KiroFlow

### Ruby Choices

Use `it` over `_1` in all blocks — it's the idiomatic Ruby 3.4 way:
```ruby
nodes.select { it.ready? }.each { execute(it) }
```

Use `+""` for any mutable string buffer to avoid chilled-string warnings:
```ruby
output = +""
output << stdout.strip
```

Use `Hash.new(capacity:)` for the context store if we know approximate node count:
```ruby
@store = Hash.new(capacity: workflow.nodes.size)
```

Use `**nil` for clean conditional option passing in node builders:
```ruby
def build_command(prompt)
  cmd = ["kiro-cli", "chat", "--no-interactive", "--wrap", "never"]
  cmd.push("--agent", opts[:agent]) if opts[:agent]
  cmd.push(**(trust_flags if opts[:trust]))
  # ...
end
```

Thread-based parallelism is fine for our I/O-bound kiro-cli calls. Ractor is overkill here — our nodes shell out to external processes, so GVL contention is minimal.

### Rails Patterns to Borrow (without Rails)

Even though KiroFlow is pure Ruby, these Rails 8 patterns are worth adopting:

**Solid Queue's `FOR UPDATE SKIP LOCKED` pattern** — If we ever persist workflow state to SQLite, this is the concurrency primitive to use for parallel node claiming.

**Propshaft's simplicity principle** — No compilation step, just serve what's there. Our .txt persistence format follows this: plain text, no serialization framework, just delimiters.

**`params#expect` pattern** — Validate node options at definition time, not execution time:
```ruby
def initialize(name, **opts)
  @prompt = opts.fetch(:prompt) { raise ArgumentError, "KiroNode #{name} requires :prompt" }
end
```

### Gem Dependencies

Since `csv`, `bigdecimal`, `mutex_m`, and `observer` are now bundled gems (not default), add them to Gemfile explicitly if needed. For KiroFlow, we need none of these — we depend only on `open3` and `json` (both still default gems).

### Testing

`Hash#inspect` format changed. Don't assert on hash `.to_s` output in tests. Use structured assertions:
```ruby
assert_equal :completed, runner.state[:step1]  # not: assert_match(/step1.*completed/, output)
```

Backtrace format changed (class names included). Don't match on exact error message strings if they include method names.
