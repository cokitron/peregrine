require "json"
require "fileutils"

module KiroFlow
  class AgentBuilder
    attr_reader :name

    def initialize(name)
      @name = name
      @config = { "description" => "" }
    end

    def description(text)    = tap { @config["description"] = text }
    def tools(list)          = tap { @config["tools"] = list }
    def allow_tools(list)    = tap { @config["allowedTools"] = list }

    def tool_settings(tool_name, settings)
      (@config["toolsSettings"] ||= {})[tool_name] = settings
      self
    end

    def mcp_server(name, command:, args: [], timeout: 10000, env: {})
      (@config["mcpServers"] ||= {})[name] = {
        "command" => command, "args" => args, "timeout" => timeout
      }.tap { |h| h["env"] = env unless env.empty? }
      self
    end

    def resource(path)
      (@config["resources"] ||= []) << path
      self
    end

    def hook(event, command:, args: [], matcher: nil, timeout_ms: 30000)
      entry = { "command" => command, "args" => args, "timeout_ms" => timeout_ms }
      entry["matcher"] = matcher if matcher
      ((@config["hooks"] ||= {})[event.to_s] ||= []) << entry
      self
    end

    def build!(base_dir = ".kiro/agents")
      FileUtils.mkdir_p(base_dir)
      path = File.join(base_dir, "#{@name}.json")
      File.write(path, JSON.pretty_generate(@config))
      path
    end

    def to_h = @config.dup
  end
end
