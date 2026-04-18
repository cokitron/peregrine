# Ticket 6: File-Based Persistence (.txt Kiro-Optimized Format)

## Goal
All node inputs and outputs are persisted as .txt files in a run directory,
formatted for optimal Kiro CLI context intake.

## File
- `lib/kiro_flow/persistence.rb`

## Run Directory Structure

```
kiro_flow_runs/
└── 20260417_234500_a1b2c3/
    ├── _manifest.txt          # Run metadata + node summary
    ├── _input.txt             # Initial input to the workflow
    ├── analyze.txt            # Output of :analyze node
    ├── test_results.txt       # Output of :test_results node
    ├── deploy.txt             # Output of :deploy node
    └── _summary.txt           # Final run summary
```

## Kiro-Optimized .txt Format

Each node output file follows this structure:

```
--- NODE OUTPUT: analyze ---
Status: completed
Duration: 3.2s
Upstream: input
Timestamp: 2026-04-17T23:45:00-06:00

--- CONTENT BEGIN ---
<actual node output here>
--- CONTENT END ---
```

### Why this format
- `--- SECTION ---` delimiters are clear for LLM parsing
- Metadata header gives Kiro context about what produced this output
- `CONTENT BEGIN/END` markers let Kiro extract just the payload
- Plain .txt avoids any markdown rendering issues

## Manifest File (_manifest.txt)

```
--- KIROFLOW RUN MANIFEST ---
Run ID: 20260417_234500_a1b2c3
Workflow: deploy_review
Started: 2026-04-17T23:45:00-06:00
Status: completed

--- NODE STATES ---
analyze: completed (3.2s)
test_results: completed (12.1s)
check_tests: completed (0.1s)
deploy: skipped (guard: check_tests=false)
report: completed (2.8s)

--- EDGES ---
analyze -> test_results -> check_tests -> deploy
                                       -> report
```

## Persistence Module

```ruby
module KiroFlow::Persistence
  def self.write_node_output(run_dir, node_name, output, metadata = {})
    # Writes <run_dir>/<node_name>.txt in Kiro format
  end

  def self.read_node_output(run_dir, node_name)
    # Reads and returns just the CONTENT section
  end

  def self.write_manifest(run_dir, workflow, states, timings)
    # Writes _manifest.txt
  end

  def self.generate_run_dir(base_dir = "./kiro_flow_runs")
    # Creates timestamped directory, returns path
  end
end
```

## Context Integration
- `context.file_for(:node_name)` returns the absolute path to that node's .txt file
- KiroNode prompts can use `{{node_name_file}}` to get the file path instead of inline content
- This is important for large outputs that would exceed prompt limits

## Acceptance Criteria
- [ ] Run directory created with timestamp + random suffix
- [ ] Each node output written in Kiro-optimized .txt format
- [ ] Manifest file summarizes entire run
- [ ] `read_node_output` extracts only CONTENT section
- [ ] `context.file_for(:name)` returns correct path
- [ ] `{{name_file}}` interpolation works in prompts
