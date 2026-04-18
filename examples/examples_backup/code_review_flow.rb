#!/usr/bin/env ruby
require_relative "../lib/kiro_flow"

# Example: Code Review Pipeline
# Runs without kiro-cli by using shell/ruby nodes as a demo.
# Replace :shell/:ruby nodes with :kiro nodes for real AI-powered workflows.

flow = KiroFlow::Workflow.define("code_review") do
  # Gather diff and run tests in parallel
  node :diff, type: :shell,
    command: "git diff HEAD~1 2>/dev/null || echo 'no git diff available'"

  node :tests, type: :shell,
    command: "echo '{\"summary_line\":\"2 examples, 0 failures\"}'"

  # Analyze diff (would be :kiro in production)
  node :analyze, type: :ruby,
    callable: ->(ctx) { "Analysis of #{ctx[:diff].to_s.length} chars of diff: looks good" }

  # Check test results
  node :check, type: :conditional,
    condition: ->(ctx) { ctx[:tests].include?("0 failures") }

  # Summary only if tests pass
  node :summary, type: :ruby, only_if: :check,
    callable: ->(ctx) {
      "PR Review Summary\n" \
      "=================\n" \
      "Diff size: #{ctx[:diff].to_s.length} chars\n" \
      "Tests: #{ctx[:tests]}\n" \
      "Analysis: #{ctx[:analyze]}\n" \
      "Verdict: SHIP IT"
    }

  # Alert only if tests fail
  node :alert, type: :ruby, unless_node: :check,
    callable: ->(ctx) { "BLOCKED: Tests failed — #{ctx[:tests]}" }

  # diff and tests run in parallel, then analyze, then check branches
  connect :diff >> :analyze >> :summary
  connect :tests >> :check >> :summary
  connect :check >> :alert
end

result = flow.run
puts "\n=== Run completed: #{result.run_dir} ==="
puts "\nSummary:\n#{result[:summary] || result[:alert]}"
