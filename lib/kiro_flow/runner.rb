module KiroFlow
  class Runner
    MAX_CONCURRENT = 3

    attr_reader :state, :timings, :errors

    def initialize(workflow)
      @workflow = workflow
      @state = {}
      @timings = {}
      @errors = {}
      @mutex = Mutex.new
      @cancelled = false
    end

    def cancel!
      @mutex.synchronize { @cancelled = true }
    end

    def cancelled?
      @mutex.synchronize { @cancelled }
    end

    def run(input: nil, run_dir: nil)
      context = Context.new(run_dir: run_dir || Persistence.generate_run_dir)
      context[:input] = input if input

      @workflow.nodes.each_key { |n| @state[n] = :pending }
      in_degree = compute_in_degree

      ready = Queue.new
      in_degree.each { |node, deg| ready << node if deg <= 0 }

      active_threads = []

      until ready.empty? && active_threads.empty?
        break if cancelled?

        # Reap finished threads
        active_threads.reject! { !it.alive? }

        # Launch up to MAX_CONCURRENT
        while !ready.empty? && active_threads.size < MAX_CONCURRENT
          node_name = ready.pop(true) rescue break
          active_threads << Thread.new(node_name) do |nn|
            run_node(nn, context, in_degree, ready)
          end
        end

        sleep 0.05 unless ready.empty? && active_threads.empty?
        active_threads.reject! { !it.alive? }
      end

      # Wait for any stragglers
      active_threads.each(&:join)

      Persistence.write_manifest(context.run_dir, @workflow, @state, @timings)
      context
    end

    def success?
      @state.values.all? { it == :completed || it == :skipped }
    end

    def status
      {
        success: success?,
        nodes: @state.dup,
        errors: @errors.dup,
        timings: @timings.transform_values { it.round(2) }
      }
    end

    private

    def compute_in_degree
      deg = Hash.new(0)
      @workflow.nodes.each_key { deg[it] = 0 }
      back_edges = detect_back_edges
      @workflow.edges.each do |from, tos|
        tos.each { |to| deg[to] += 1 unless back_edges.include?([from, to]) }
      end
      deg
    end

    def detect_back_edges
      visited = Set.new
      in_stack = Set.new
      back = Set.new
      dfs = ->(node) do
        visited << node; in_stack << node
        (@workflow.edges[node] || []).each do |to|
          if in_stack.include?(to)
            back << [node, to]
          elsif !visited.include?(to)
            dfs.(to)
          end
        end
        in_stack.delete(node)
      end
      @workflow.nodes.each_key { dfs.(it) unless visited.include?(it) }
      back
    end

    def run_node(node_name, context, in_degree, ready)
      node = @workflow.nodes[node_name]

      if should_skip?(node, context)
        @mutex.synchronize { @state[node_name] = :skipped }
        log(:skip, node_name)
        enqueue_downstream(node_name, in_degree, ready)
        return
      end

      @mutex.synchronize { @state[node_name] = :running }
      log(:start, node_name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        output = node.execute(context)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        context[node_name] = output
        Persistence.write_node_output(context.run_dir, node_name, output,
          duration: duration, upstream: @workflow.upstream(node_name))
        @mutex.synchronize do
          @state[node_name] = :completed
          @timings[node_name] = duration
        end
        log(:done, node_name, duration)
      rescue => e
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @mutex.synchronize do
          @state[node_name] = :failed
          @timings[node_name] = duration
          @errors[node_name] = e.message
        end
        log(:fail, node_name, duration, e.message)
      end

      enqueue_downstream(node_name, in_degree, ready)
    end

    def enqueue_downstream(node_name, in_degree, ready)
      @workflow.downstream(node_name).each do |dn|
        should_enqueue = @mutex.synchronize do
          next false unless @state[dn] == :pending
          in_degree[dn] -= 1
          in_degree[dn] <= 0
        end
        ready << dn if should_enqueue
      end
    end

    def should_skip?(node, context)
      # Guard: only_if
      if (guard = node.only_if)
        return true unless context[guard] == "true"
      end
      # Guard: unless_node
      if (guard = node.unless_node)
        return true if context[guard] == "true"
      end
      # Skip if any upstream failed/skipped
      @workflow.upstream(node.name).any? do |up|
        @mutex.synchronize { @state[up] == :failed || @state[up] == :skipped }
      end
    end

    def log(event, node_name, duration = nil, message = nil)
      prefix = "\e[36m[KiroFlow]\e[0m"
      case event
      when :start then puts "#{prefix} \e[33m▶\e[0m #{node_name}"
      when :done  then puts "#{prefix} \e[32m✓\e[0m #{node_name} \e[2m(#{duration&.round(1)}s)\e[0m"
      when :fail  then puts "#{prefix} \e[31m✗\e[0m #{node_name} \e[2m(#{duration&.round(1)}s)\e[0m — #{message}"
      when :skip  then puts "#{prefix} \e[2m⊘ #{node_name} skipped\e[0m"
      end
    rescue
      nil # never fail on logging
    end
  end
end
