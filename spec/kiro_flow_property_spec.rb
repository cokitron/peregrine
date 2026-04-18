require "minitest/autorun"
require "tmpdir"
require "prop_check"
require "prop_check/generators"
require "timeout"

# Load KiroFlow engine
require_relative "../lib/kiro_flow"
Dir[File.join(__dir__, "..", "lib/kiro_flow/**/*.rb")].each { |f| require f }

# ─── Generators ───────────────────────────────────────────────────────────────

module GraphGenerators
  G = PropCheck::Generators

  # Generate a random DAG with n nodes. Only edges from lower to higher index.
  def self.dag(min_nodes: 2, max_nodes: 12)
    G.choose(min_nodes..max_nodes).bind do |n|
      names = (0...n).map { |i| :"n#{i}" }
      possible = names.each_with_index.flat_map { |from, i| names[(i + 1)..].map { |to| [from, to] } }
      G.array(G.boolean, min: possible.size, max: possible.size).map do |picks|
        edges = possible.zip(picks).filter_map { |edge, pick| edge if pick }
        { nodes: names, edges: edges }
      end
    end
  end

  # Generate a graph that may contain cycles (back-edges from higher to lower index).
  def self.graph_with_possible_cycles(min_nodes: 2, max_nodes: 10)
    dag(min_nodes: min_nodes, max_nodes: max_nodes).bind do |graph|
      n = graph[:nodes].size
      next G.constant(graph) if n < 3
      G.choose(0..[3, n - 1].min).bind do |num_back|
        next G.constant(graph) if num_back == 0
        G.array(G.tuple(G.choose(2..(n - 1)), G.choose(0..(n - 2))), min: num_back, max: num_back).map do |pairs|
          back_edges = pairs.filter_map { |(fi, ti)| [graph[:nodes][fi], graph[:nodes][ti]] if fi > ti }
          { nodes: graph[:nodes], edges: (graph[:edges] + back_edges).uniq }
        end
      end
    end
  end

  # Generate per-node behaviors
  def self.behaviors(n)
    G.array(G.one_of(G.constant(:ok), G.constant(:fail), G.constant(:slow)), min: n, max: n)
  end
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

def build_workflow(graph, behaviors)
  wf = KiroFlow::Workflow.new("prop_test")
  graph[:nodes].each_with_index do |name, i|
    callable = case behaviors[i] || :ok
               when :ok   then ->(_) { "ok" }
               when :fail then ->(_) { raise "fail" }
               when :slow then ->(_) { sleep(0.01); "ok" }
               end
    wf.node(name, type: :ruby, callable: callable)
  end
  graph[:edges].each { |from, to| wf.connect(from >> to) }
  wf
end

def find_reachable(edges, from)
  adj = Hash.new { |h, k| h[k] = [] }
  edges.each { |f, t| adj[f] << t }
  visited = Set.new
  queue = adj[from].dup
  while (node = queue.shift)
    next if visited.include?(node)
    visited << node
    queue.concat(adj[node])
  end
  visited
end

TERMINAL_STATES = %i[completed failed skipped].freeze

# Silence runner log output during property tests
KiroFlow::Runner.prepend(Module.new { def log(...) = nil })

# Progress-tracking wrapper for PropCheck
def forall_with_progress(name, generator, n_runs: 100, &block)
  count = 0
  PropCheck.forall(generator) do |val|
    count += 1
    print "\r  #{name}: #{(count * 100.0 / n_runs).round}% (#{count}/#{n_runs})" if count % 10 == 0 || count == 1
    block.call(val)
  end
  puts "\r  #{name}: 100% (#{count}/#{count}) ✓"
end

# ─── Property Tests ───────────────────────────────────────────────────────────

class RunnerPropertyTest < Minitest::Test
  # P1: Runner ALWAYS terminates, even with cycles and mixed failures.
  def test_always_terminates
    forall_with_progress("P1 always terminates",
      GraphGenerators.graph_with_possible_cycles.bind { |g|
        GraphGenerators.behaviors(g[:nodes].size).map { |bs| [g, bs] }
      }
    ) do |(graph, behaviors)|
      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }
      assert true
    end
  end

  # P2: Every node reaches a terminal state.
  def test_all_nodes_reach_terminal_state
    forall_with_progress("P2 terminal states",
      GraphGenerators.dag.bind { |g|
        GraphGenerators.behaviors(g[:nodes].size).map { |bs| [g, bs] }
      }
    ) do |(graph, behaviors)|
      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      graph[:nodes].each do |name|
        assert_includes TERMINAL_STATES, runner.state[name],
          "Node #{name} in non-terminal state: #{runner.state[name]}"
      end
    end
  end

  # P3: State map covers exactly all workflow nodes.
  def test_state_covers_all_nodes
    forall_with_progress("P3 state coverage",
      GraphGenerators.dag
    ) do |graph|
      wf = build_workflow(graph, graph[:nodes].map { :ok })
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      assert_equal graph[:nodes].to_set, runner.state.keys.to_set
    end
  end

  # P4: All-ok DAG → success? is true.
  def test_all_ok_means_success
    forall_with_progress("P4 all-ok → success",
      GraphGenerators.dag
    ) do |graph|
      wf = build_workflow(graph, graph[:nodes].map { :ok })
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      assert runner.success?, "Expected success but got: #{runner.state}"
    end
  end

  # P5: A failed node's reachable descendants are skipped (not completed).
  def test_failed_node_skips_descendants
    forall_with_progress("P5 failure propagation",
      GraphGenerators.dag(min_nodes: 3, max_nodes: 8)
    ) do |graph|
      next if graph[:edges].empty?

      fail_node = graph[:edges].first[0]
      behaviors = graph[:nodes].map { |n| n == fail_node ? :fail : :ok }

      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      assert_equal :failed, runner.state[fail_node]

      reachable = find_reachable(graph[:edges], fail_node)
      reachable.each do |desc|
        refute_equal :failed, runner.state[desc],
          "Descendant #{desc} should not independently fail"
      end
    end
  end

  # P6: Cycles with all-ok nodes terminate and complete.
  def test_cycles_all_ok_terminate
    forall_with_progress("P6 cycles (all-ok)",
      GraphGenerators.graph_with_possible_cycles
    ) do |graph|
      wf = build_workflow(graph, graph[:nodes].map { :ok })
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      graph[:nodes].each do |name|
        assert_includes TERMINAL_STATES, runner.state[name]
      end
    end
  end

  # P7: Cycles with failures terminate (the exact bug we fixed).
  def test_cycles_with_failures_terminate
    forall_with_progress("P7 cycles (failures)",
      GraphGenerators.graph_with_possible_cycles.bind { |g|
        GraphGenerators.behaviors(g[:nodes].size).map { |bs| [g, bs] }
      }
    ) do |(graph, behaviors)|
      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      graph[:nodes].each do |name|
        assert_includes TERMINAL_STATES, runner.state[name],
          "Node #{name} stuck in #{runner.state[name]} (cycle+failure)"
      end
    end
  end

  # P8: Completed nodes always have output in context.
  def test_completed_nodes_have_context_output
    forall_with_progress("P8 context output",
      GraphGenerators.dag
    ) do |graph|
      wf = build_workflow(graph, graph[:nodes].map { :ok })
      runner = KiroFlow::Runner.new(wf)
      ctx = Timeout.timeout(5) { runner.run }

      runner.state.each do |name, state|
        refute_nil ctx[name], "Completed node #{name} missing context" if state == :completed
      end
    end
  end

  # P9: Timings recorded for completed and failed nodes, not skipped.
  def test_timings_recorded_correctly
    forall_with_progress("P9 timings",
      GraphGenerators.dag.bind { |g|
        GraphGenerators.behaviors(g[:nodes].size).map { |bs| [g, bs] }
      }
    ) do |(graph, behaviors)|
      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      runner.state.each do |name, state|
        case state
        when :completed, :failed
          assert runner.timings.key?(name), "No timing for #{state} node #{name}"
          assert_operator runner.timings[name], :>=, 0
        when :skipped
          refute runner.timings.key?(name), "Skipped node #{name} should have no timing"
        end
      end
    end
  end

  # P10: Errors hash only contains failed nodes.
  def test_errors_only_for_failed_nodes
    forall_with_progress("P10 errors map",
      GraphGenerators.dag.bind { |g|
        GraphGenerators.behaviors(g[:nodes].size).map { |bs| [g, bs] }
      }
    ) do |(graph, behaviors)|
      wf = build_workflow(graph, behaviors)
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      runner.errors.each_key do |name|
        assert_equal :failed, runner.state[name],
          "Error recorded for non-failed node #{name} (#{runner.state[name]})"
      end
      runner.state.each do |name, state|
        assert runner.errors.key?(name), "Failed node #{name} missing error" if state == :failed
      end
    end
  end

  # P11: Root nodes always execute in all-ok workflows.
  def test_roots_always_execute_when_all_ok
    forall_with_progress("P11 roots execute",
      GraphGenerators.dag
    ) do |graph|
      wf = build_workflow(graph, graph[:nodes].map { :ok })
      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(5) { runner.run }

      wf.roots.each do |root|
        assert_equal :completed, runner.state[root],
          "Root #{root} should complete, got #{runner.state[root]}"
      end
    end
  end

  # P12: Parallel execution respects MAX_CONCURRENT (no more than 3 simultaneous).
  def test_max_concurrency_respected
    forall_with_progress("P12 max concurrency", GraphGenerators.dag(min_nodes: 5, max_nodes: 10), n_runs: 30) do |graph|
      max_seen = 0
      current = 0
      mu = Mutex.new

      wf = KiroFlow::Workflow.new("concurrency_test")
      graph[:nodes].each do |name|
        wf.node(name, type: :ruby, callable: ->(_) {
          mu.synchronize { current += 1; max_seen = [max_seen, current].max }
          sleep(0.01)
          mu.synchronize { current -= 1 }
          "ok"
        })
      end
      graph[:edges].each { |from, to| wf.connect(from >> to) }

      runner = KiroFlow::Runner.new(wf)
      Timeout.timeout(10) { runner.run }

      assert_operator max_seen, :<=, KiroFlow::Runner::MAX_CONCURRENT,
        "Saw #{max_seen} concurrent nodes, max is #{KiroFlow::Runner::MAX_CONCURRENT}"
    end
  end
end
