module KiroFlow
  class Context
    attr_reader :run_dir, :run_id

    def initialize(run_dir:)
      @run_dir = run_dir
      @run_id = File.basename(run_dir)
      @store = {}
      @mutex = Mutex.new
    end

    def [](key) = @mutex.synchronize { @store[key.to_sym] }

    def []=(key, value)
      @mutex.synchronize { @store[key.to_sym] = value }
    end

    def file_for(node_name)
      File.join(@run_dir, "#{node_name}.txt")
    end

    def interpolate(template)
      template.gsub(/\{\{(\w+?)_file\}\}/) { file_for(Regexp.last_match(1).to_sym) }
              .gsub(/\{\{(\w+?)\}\}/) { self[Regexp.last_match(1).to_sym].to_s }
    end

    def keys = @mutex.synchronize { @store.keys }
    def to_h = @mutex.synchronize { @store.dup }
  end
end
