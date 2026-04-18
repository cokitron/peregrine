require "open3"
require "timeout"
require "fileutils"

module KiroFlow
  class KiroNode < Node
    ANSI_RE = /\e(?:\[[0-9;?]*[a-zA-Z]|\([A-B]|\].*?(?:\a|\e\\)|\[[0-9;]*m)/

    def execute(context)
      prompt = context.interpolate(opts.fetch(:prompt))
      cmd = build_command(prompt)
      live_file = File.join(context.run_dir, "#{name}.live")
      output = +""

      Timeout.timeout(opts.fetch(:timeout, 300)) do
        IO.popen(cmd, err: [:child, :out]) do |io|
          io.each_line do |line|
            clean = line.force_encoding("UTF-8").scrub("").gsub(ANSI_RE, "")
            output << clean
            File.write(live_file, output)
          end
        end
      end

      raise "KiroNode #{name} failed (exit #{$?.exitstatus})" unless $?.success?
      FileUtils.rm_f(live_file)
      output.strip
    end

    private

    def build_command(prompt)
      parts = ["kiro-cli", "chat", "--no-interactive", "--wrap", "never"]
      trust = opts.fetch(:trust, :all)
      if trust == :all
        parts << "--trust-all-tools"
      elsif trust.is_a?(Array)
        parts.push("--trust-tools", trust.join(","))
      end
      parts.push("--agent", opts[:agent].to_s) if opts[:agent]
      parts.push("--model", opts[:model].to_s) if opts[:model]
      parts << prompt
      parts
    end
  end
end
