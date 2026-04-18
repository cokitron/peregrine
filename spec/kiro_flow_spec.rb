require "minitest/autorun"
require "tmpdir"
require "json"
require "net/http"
require_relative "../lib/kiro_flow"

class ContextTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @ctx = KiroFlow::Context.new(run_dir: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_store_and_retrieve
    @ctx[:step1] = "hello"
    assert_equal "hello", @ctx[:step1]
  end

  def test_symbol_and_string_keys_normalize
    @ctx[:foo] = "bar"
    assert_equal "bar", @ctx["foo"]
  end

  def test_interpolate_values
    @ctx[:name] = "world"
    assert_equal "hello world", @ctx.interpolate("hello {{name}}")
  end

  def test_interpolate_file_paths
    expected = File.join(@dir, "step1.txt")
    assert_equal "read #{expected}", @ctx.interpolate("read {{step1_file}}")
  end

  def test_interpolate_mixed
    @ctx[:a] = "val"
    result = @ctx.interpolate("{{a}} at {{a_file}}")
    assert_equal "val at #{File.join(@dir, 'a.txt')}", result
  end

  def test_run_id
    assert_equal File.basename(@dir), @ctx.run_id
  end

  def test_keys_and_to_h
    @ctx[:x] = 1
    @ctx[:y] = 2
    assert_equal [:x, :y], @ctx.keys.sort
    assert_equal({x: 1, y: 2}, @ctx.to_h)
  end

  def test_thread_safety
    threads = 100.times.map { |i| Thread.new { @ctx[:"t#{i}"] = i } }
    threads.each(&:join)
    assert_equal 100, @ctx.keys.size
  end
end

class ChainTest < Minitest::Test
  def test_symbol_chain
    chain = :a >> :b >> :c
    assert_instance_of KiroFlow::Chain, chain
    assert_equal [[:a, :b], [:b, :c]], chain.pairs
  end

  def test_two_symbol_chain
    chain = :x >> :y
    assert_equal [[:x, :y]], chain.pairs
  end
end

class NodeTest < Minitest::Test
  def test_factory_shell
    node = KiroFlow::Node.build(:s, type: :shell, command: "echo hi")
    assert_instance_of KiroFlow::ShellNode, node
  end

  def test_factory_ruby
    node = KiroFlow::Node.build(:r, type: :ruby, callable: -> { "ok" })
    assert_instance_of KiroFlow::RubyNode, node
  end

  def test_factory_conditional
    node = KiroFlow::Node.build(:c, type: :conditional, condition: ->(_) { true })
    assert_instance_of KiroFlow::ConditionalNode, node
  end

  def test_factory_kiro
    node = KiroFlow::Node.build(:k, type: :kiro, prompt: "hi")
    assert_instance_of KiroFlow::KiroNode, node
  end

  def test_factory_unknown_raises
    assert_raises(ArgumentError) { KiroFlow::Node.build(:x, type: :nope) }
  end

  def test_guards
    node = KiroFlow::Node.build(:g, type: :ruby, callable: -> { "" }, only_if: :check, unless_node: :skip)
    assert_equal :check, node.only_if
    assert_equal :skip, node.unless_node
  end
end

class WorkflowTest < Minitest::Test
  def setup
    @wf = KiroFlow::Workflow.define("test") do
      node :a, type: :shell, command: "echo a"
      node :b, type: :shell, command: "echo b"
      node :c, type: :shell, command: "echo c"
      connect :a >> :b >> :c
    end
  end

  def test_nodes_registered
    assert_equal [:a, :b, :c], @wf.nodes.keys
  end

  def test_edges
    assert_equal [:b], @wf.edges[:a]
    assert_equal [:c], @wf.edges[:b]
  end

  def test_roots
    assert_equal [:a], @wf.roots
  end

  def test_upstream_downstream
    assert_equal [:b], @wf.downstream(:a)
    assert_equal [:a], @wf.upstream(:b)
    assert_equal [], @wf.upstream(:a)
  end

  def test_parallel_roots
    wf = KiroFlow::Workflow.define("par") do
      node :x, type: :shell, command: "echo x"
      node :y, type: :shell, command: "echo y"
      node :z, type: :shell, command: "echo z"
      connect :x >> :z
      connect :y >> :z
    end
    assert_equal [:x, :y].sort, wf.roots.sort
  end

  def test_no_duplicate_edges
    wf = KiroFlow::Workflow.define("dup") do
      node :a, type: :shell, command: "echo a"
      node :b, type: :shell, command: "echo b"
      connect :a >> :b
      connect :a >> :b
    end
    assert_equal [:b], wf.edges[:a]
  end
end

class ShellNodeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @ctx = KiroFlow::Context.new(run_dir: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_execute
    node = KiroFlow::ShellNode.new(:echo, command: "echo hello")
    assert_equal "hello", node.execute(@ctx)
  end

  def test_interpolation
    @ctx[:msg] = "world"
    node = KiroFlow::ShellNode.new(:echo, command: "echo {{msg}}")
    assert_equal "world", node.execute(@ctx)
  end

  def test_failure_raises
    node = KiroFlow::ShellNode.new(:fail, command: "exit 1")
    assert_raises(RuntimeError) { node.execute(@ctx) }
  end
end

class RubyNodeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @ctx = KiroFlow::Context.new(run_dir: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_execute
    node = KiroFlow::RubyNode.new(:calc, callable: ->(ctx) { 2 + 2 })
    assert_equal "4", node.execute(@ctx)
  end

  def test_context_access
    @ctx[:val] = "42"
    node = KiroFlow::RubyNode.new(:read, callable: ->(ctx) { "got #{ctx[:val]}" })
    assert_equal "got 42", node.execute(@ctx)
  end
end

class ConditionalNodeTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @ctx = KiroFlow::Context.new(run_dir: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_true
    node = KiroFlow::ConditionalNode.new(:check, condition: ->(_) { true })
    assert_equal "true", node.execute(@ctx)
  end

  def test_false
    node = KiroFlow::ConditionalNode.new(:check, condition: ->(_) { false })
    assert_equal "false", node.execute(@ctx)
  end

  def test_context_based
    @ctx[:result] = "0 failures"
    node = KiroFlow::ConditionalNode.new(:check, condition: ->(ctx) { ctx[:result].include?("0 failures") })
    assert_equal "true", node.execute(@ctx)
  end
end

class KiroNodeTest < Minitest::Test
  def test_build_command_all_trust
    node = KiroFlow::KiroNode.new(:k, prompt: "hello")
    cmd = node.send(:build_command, "hello")
    assert_includes cmd, "--no-interactive"
    assert_includes cmd, "--trust-all-tools"
    assert_includes cmd, "--wrap never"
    assert_includes cmd, "hello"
  end

  def test_build_command_with_agent
    node = KiroFlow::KiroNode.new(:k, prompt: "hi", agent: "reviewer")
    cmd = node.send(:build_command, "hi")
    assert_includes cmd, "--agent reviewer"
  end

  def test_build_command_specific_trust
    node = KiroFlow::KiroNode.new(:k, prompt: "hi", trust: ["fs_read", "fs_write"])
    cmd = node.send(:build_command, "hi")
    assert_includes cmd, "--trust-tools fs_read,fs_write"
    refute_includes cmd, "--trust-all-tools"
  end

  def test_build_command_with_model
    node = KiroFlow::KiroNode.new(:k, prompt: "hi", model: "claude")
    cmd = node.send(:build_command, "hi")
    assert_includes cmd, "--model claude"
  end
end

class PersistenceTest < Minitest::Test
  def setup
    @base = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@base)
  end

  def test_generate_run_dir
    dir = KiroFlow::Persistence.generate_run_dir(@base)
    assert File.directory?(dir)
    assert_match(/\d{8}_\d{6}_\w+/, File.basename(dir))
  end

  def test_write_and_read_node_output
    dir = KiroFlow::Persistence.generate_run_dir(@base)
    KiroFlow::Persistence.write_node_output(dir, :step1, "result data", duration: 1.5)
    content = KiroFlow::Persistence.read_node_output(dir, :step1)
    assert_equal "result data", content
  end

  def test_read_missing_returns_nil
    dir = KiroFlow::Persistence.generate_run_dir(@base)
    assert_nil KiroFlow::Persistence.read_node_output(dir, :nope)
  end

  def test_kiro_format_structure
    dir = KiroFlow::Persistence.generate_run_dir(@base)
    KiroFlow::Persistence.write_node_output(dir, :x, "payload", status: "completed", upstream: [:a, :b])
    raw = File.read(File.join(dir, "x.txt"))
    assert_includes raw, "--- NODE OUTPUT: x ---"
    assert_includes raw, "Status: completed"
    assert_includes raw, "Upstream: a, b"
    assert_includes raw, "--- CONTENT BEGIN ---"
    assert_includes raw, "payload"
    assert_includes raw, "--- CONTENT END ---"
  end

  def test_write_manifest
    dir = KiroFlow::Persistence.generate_run_dir(@base)
    wf = KiroFlow::Workflow.define("mf") do
      node :a, type: :shell, command: "echo a"
      node :b, type: :shell, command: "echo b"
      connect :a >> :b
    end
    KiroFlow::Persistence.write_manifest(dir, wf, {a: :completed, b: :completed}, {a: 1.0, b: 2.0})
    manifest = File.read(File.join(dir, "_manifest.txt"))
    assert_includes manifest, "Workflow: mf"
    assert_includes manifest, "a: completed (1.0s)"
    assert_includes manifest, "a -> b"
  end
end

class RunnerTest < Minitest::Test
  def teardown
    FileUtils.rm_rf(File.join(Dir.home, ".kiro_flow", "runs"))
  end

  def test_sequential_execution
    wf = KiroFlow::Workflow.define("seq") do
      node :a, type: :shell, command: "echo alpha"
      node :b, type: :shell, command: "echo bravo"
      connect :a >> :b
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert_equal "alpha", ctx[:a]
    assert_equal "bravo", ctx[:b]
    assert runner.success?
  end

  def test_parallel_execution
    wf = KiroFlow::Workflow.define("par") do
      node :x, type: :shell, command: "echo x"
      node :y, type: :shell, command: "echo y"
      node :z, type: :ruby, callable: ->(ctx) { "#{ctx[:x]}+#{ctx[:y]}" }
      connect :x >> :z
      connect :y >> :z
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert_equal "x+y", ctx[:z]
    assert runner.success?
  end

  def test_input_passed
    wf = KiroFlow::Workflow.define("inp") do
      node :echo, type: :shell, command: "echo {{input}}"
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run(input: "hello")
    assert_equal "hello", ctx[:echo]
  end

  def test_conditional_only_if
    wf = KiroFlow::Workflow.define("cond") do
      node :check, type: :conditional, condition: ->(_) { true }
      node :yes, type: :ruby, callable: ->(_) { "ran" }, only_if: :check
      node :no, type: :ruby, callable: ->(_) { "ran" }, unless_node: :check
      connect :check >> :yes
      connect :check >> :no
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert_equal "ran", ctx[:yes]
    assert_equal :skipped, runner.state[:no]
  end

  def test_conditional_false_branch
    wf = KiroFlow::Workflow.define("cond2") do
      node :check, type: :conditional, condition: ->(_) { false }
      node :yes, type: :ruby, callable: ->(_) { "ran" }, only_if: :check
      node :no, type: :ruby, callable: ->(_) { "ran" }, unless_node: :check
      connect :check >> :yes
      connect :check >> :no
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert_equal :skipped, runner.state[:yes]
    assert_equal "ran", ctx[:no]
  end

  def test_failed_node_skips_downstream
    wf = KiroFlow::Workflow.define("fail") do
      node :bad, type: :shell, command: "exit 1"
      node :after, type: :ruby, callable: ->(_) { "should not run" }
      connect :bad >> :after
    end
    runner = KiroFlow::Runner.new(wf)
    runner.run
    assert_equal :failed, runner.state[:bad]
    assert_equal :skipped, runner.state[:after]
    refute runner.success?
  end

  def test_manifest_created
    wf = KiroFlow::Workflow.define("mf") do
      node :a, type: :shell, command: "echo done"
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert File.exist?(File.join(ctx.run_dir, "_manifest.txt"))
  end

  def test_node_output_files_created
    wf = KiroFlow::Workflow.define("files") do
      node :step1, type: :shell, command: "echo output"
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert File.exist?(ctx.file_for(:step1))
    content = KiroFlow::Persistence.read_node_output(ctx.run_dir, :step1)
    assert_equal "output", content
  end

  def test_max_concurrency_respected
    # 4 independent nodes, max 3 concurrent
    wf = KiroFlow::Workflow.define("conc") do
      node :a, type: :shell, command: "sleep 0.1 && echo a"
      node :b, type: :shell, command: "sleep 0.1 && echo b"
      node :c, type: :shell, command: "sleep 0.1 && echo c"
      node :d, type: :shell, command: "sleep 0.1 && echo d"
    end
    runner = KiroFlow::Runner.new(wf)
    ctx = runner.run
    assert runner.success?
    assert_equal %w[a b c d].sort, [:a, :b, :c, :d].map { ctx[it] }.sort
  end

  def test_status_after_success
    wf = KiroFlow::Workflow.define("st") do
      node :a, type: :shell, command: "echo ok"
    end
    runner = KiroFlow::Runner.new(wf)
    runner.run
    status = runner.status
    assert status[:success]
    assert_equal :completed, status[:nodes][:a]
    assert_empty status[:errors]
  end

  def test_status_after_failure
    wf = KiroFlow::Workflow.define("st") do
      node :bad, type: :shell, command: "exit 1"
    end
    runner = KiroFlow::Runner.new(wf)
    runner.run
    status = runner.status
    refute status[:success]
    assert_equal :failed, status[:nodes][:bad]
    refute_empty status[:errors]
  end
end

class AgentBuilderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_build_creates_json
    path = KiroFlow::AgentBuilder.new("test-agent")
      .description("Test agent")
      .tools(["fs_read", "execute_bash"])
      .allow_tools(["fs_read"])
      .build!(@dir)

    assert File.exist?(path)
    config = JSON.parse(File.read(path))
    assert_equal "Test agent", config["description"]
    assert_equal ["fs_read", "execute_bash"], config["tools"]
    assert_equal ["fs_read"], config["allowedTools"]
  end

  def test_mcp_server
    builder = KiroFlow::AgentBuilder.new("mcp-agent")
      .mcp_server("git", command: "mcp-server-git", args: ["--repo", "."])
    config = builder.to_h
    assert_equal "mcp-server-git", config["mcpServers"]["git"]["command"]
    assert_equal ["--repo", "."], config["mcpServers"]["git"]["args"]
  end

  def test_hooks
    builder = KiroFlow::AgentBuilder.new("hook-agent")
      .hook(:postToolUse, command: "ruby", args: ["log.rb"], matcher: "*")
    config = builder.to_h
    hook = config["hooks"]["postToolUse"].first
    assert_equal "ruby", hook["command"]
    assert_equal "*", hook["matcher"]
  end

  def test_resources
    builder = KiroFlow::AgentBuilder.new("res-agent")
      .resource("file://README.md")
      .resource("file://docs/**/*.md")
    config = builder.to_h
    assert_equal ["file://README.md", "file://docs/**/*.md"], config["resources"]
  end

  def test_tool_settings
    builder = KiroFlow::AgentBuilder.new("ts-agent")
      .tool_settings("execute_bash", {"autoAllowReadonly" => true})
    config = builder.to_h
    assert_equal true, config["toolsSettings"]["execute_bash"]["autoAllowReadonly"]
  end
end

class ChainBuilderTest < Minitest::Test
  def teardown
    FileUtils.rm_rf(File.join(Dir.home, ".kiro_flow", "runs"))
  end

  def test_linear_chain
    wf = KiroFlow.chain("linear") do
      sh   :greet,  "echo hello"
      step :upper,  ->(ctx) { ctx[:greet].upcase }
    end
    assert_equal [:greet, :upper], wf.nodes.keys
    assert_equal [:upper], wf.downstream(:greet)
  end

  def test_chain_runs
    wf = KiroFlow.chain("run") do
      sh   :a, "echo one"
      sh   :b, "echo two"
      step :c, ->(ctx) { "#{ctx[:a]}+#{ctx[:b]}" }
    end
    ctx = wf.run
    assert_equal "one+two", ctx[:c]
  end

  def test_gate_applies_only_if
    wf = KiroFlow.chain("gated") do
      step :val,   ->(_) { "good" }
      gate :check, ->(ctx) { ctx[:val] == "good" }
      step :after, ->(_) { "ran" }
    end
    ctx = wf.run
    assert_equal "ran", ctx[:after]
  end

  def test_gate_skips_when_false
    wf = KiroFlow.chain("gated_skip") do
      step :val,   ->(_) { "bad" }
      gate :check, ->(ctx) { ctx[:val] == "good" }
      step :after, ->(_) { "ran" }
    end
    runner = KiroFlow::Runner.new(wf)
    runner.run
    assert_equal :skipped, runner.state[:after]
  end

  def test_parallel_group
    wf = KiroFlow.chain("par") do
      sh :start, "echo go"
      parallel do
        sh :a, "echo alpha"
        sh :b, "echo bravo"
      end
      step :done, ->(ctx) { "#{ctx[:a]}+#{ctx[:b]}" }
    end
    ctx = wf.run
    assert_equal "alpha+bravo", ctx[:done]
  end

  def test_input_passthrough
    wf = KiroFlow.chain("inp") do
      sh :echo, "echo {{input}}"
    end
    ctx = wf.run(input: "hello")
    assert_equal "hello", ctx[:echo]
  end
end
