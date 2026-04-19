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

      head_before = capture_head

      Timeout.timeout(opts.fetch(:timeout, 600)) do
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
      snapshot_artifacts(context.run_dir, head_before)
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

    def capture_head
      Open3.capture2("git", "rev-parse", "HEAD").first.strip rescue nil
    end

    def snapshot_artifacts(run_dir, head_before)
      head_after = capture_head
      return if head_before.nil? || head_after.nil? || head_before == head_after

      changed, = Open3.capture2("git", "diff", "--name-only", head_before, head_after)
      files = changed.strip.split("\n").reject(&:empty?)
      return if files.empty?

      artifact_dir = File.join(run_dir, "#{name}_artifacts")
      FileUtils.mkdir_p(artifact_dir)

      files.each do |rel_path|
        next unless File.exist?(rel_path)
        dest = File.join(artifact_dir, rel_path)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(rel_path, dest)
      end
    rescue
      nil # never fail on artifact capture
    end
  end
end
