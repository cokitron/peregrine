class WorkflowExecutionService
  def initialize(run)
    @run = run
  end

  def call
    @run.update!(status: "running", started_at: Time.current)
    broadcast(type: "status", status: "running")

    wf = DrawflowConverter.call(@run.workflow_definition.drawflow_data, default_agent_id: @run.workflow_definition.default_agent_id)
    runner = KiroFlow::Runner.new(wf)
    run_dir = KiroFlow::Persistence.generate_run_dir

    ctx = nil
    worker = Thread.new { ctx = runner.run(input: @run.input_text, run_dir: run_dir) }

    while worker.alive?
      sleep 1
      if @run.reload.status == "cancelled"
        runner.cancel!
        worker.join(5) || worker.kill
        break
      end
      @run.update!(node_states: build_node_states(runner, run_dir))
    end
    worker.join

    final_status = if @run.reload.status == "cancelled"
      "cancelled"
    elsif runner.success?
      "completed"
    else
      "failed"
    end

    @run.update!(
      status: final_status,
      node_states: build_node_states(runner, run_dir),
      run_dir: run_dir,
      completed_at: Time.current,
      error_message: runner.errors.values.join("\n").presence # rubocop:disable Rails/DeprecatedActiveModelErrorsMethods
    )

    broadcast(type: "completed", status: @run.status, node_states: @run.node_states)
  end

  private

  def build_node_states(runner, run_dir)
    runner.state.each_with_object({}) do |(name, status), h|
      live_file = File.join(run_dir, "#{name}.live")
      raw = if File.exist?(live_file)
        File.read(live_file).byteslice(-4000..)
      else
        KiroFlow::Persistence.read_node_output(run_dir, name)&.byteslice(-4000..)
      end
      output = raw.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                    .gsub(/\e(?:\[[0-9;?]*[a-zA-Z]|\([A-B]|\].*?(?:\a|\e\\)|\[[0-9;]*m)/, "")
      h[name.to_s] = { "status" => status.to_s, "output" => output }
    end
  end

  def broadcast(data)
    ActionCable.server.broadcast("workflow_run_#{@run.id}", data)
  end
end
