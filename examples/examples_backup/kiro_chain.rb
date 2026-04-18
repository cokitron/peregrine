#!/usr/bin/env ruby
# Run: ruby examples/kiro_chain.rb "Add a health check endpoint to our API"

require_relative "../lib/kiro_flow"

topic = ARGV[0] || "Add input validation to the user registration form"

flow = KiroFlow.chain("feature_build") do
  ask  :analyze,   "You are a senior architect. Analyze this feature request concisely — files to change, risks, estimate.\n\nFeature: #{topic}"
  ask  :plan,      "Write a concise step-by-step implementation plan with code snippets.\n\nAnalysis:\n{{analyze}}"
  gate :ready,     ->(ctx) { ctx[:plan].to_s.length > 50 }
  ask  :implement, "Implement the following plan. Output only code.\n\nPlan:\n{{plan}}"
  step :summary,   ->(ctx) {
    "Done!\n" \
    "  Analyze:   #{ctx[:analyze].to_s.lines.count} lines\n" \
    "  Plan:      #{ctx[:plan].to_s.lines.count} lines\n" \
    "  Code:      #{ctx[:implement].to_s.lines.count} lines\n" \
    "  Output:    #{ctx.run_dir}"
  }
end

puts "🚀 KiroFlow: #{topic}\n\n"
result = flow.run
puts "\n#{result[:summary] || 'Flow did not complete.'}"
