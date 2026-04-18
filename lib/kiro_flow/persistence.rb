require "fileutils"
require "time"

module KiroFlow
  module Persistence
    def self.generate_run_dir(base_dir = nil)
      base_dir ||= File.join(Dir.home, ".kiro_flow", "runs")
      id = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{rand(36**6).to_s(36)}"
      dir = File.expand_path(File.join(base_dir, id))
      FileUtils.mkdir_p(dir)
      dir
    end

    def self.write_node_output(run_dir, node_name, output, status: "completed", duration: nil, upstream: [])
      FileUtils.mkdir_p(run_dir)
      path = File.join(run_dir, "#{node_name}.txt")
      content = +"--- NODE OUTPUT: #{node_name} ---\n"
      content << "Status: #{status}\n"
      content << "Duration: #{duration}s\n" if duration
      content << "Upstream: #{upstream.join(', ')}\n" unless upstream.empty?
      content << "Timestamp: #{Time.now.iso8601}\n"
      content << "\n--- CONTENT BEGIN ---\n"
      content << output.to_s
      content << "\n--- CONTENT END ---\n"
      File.write(path, content)
    end

    def self.read_node_output(run_dir, node_name)
      path = File.join(run_dir, "#{node_name}.txt")
      return nil unless File.exist?(path)
      text = File.read(path)
      match = text.match(/--- CONTENT BEGIN ---\n(.*)\n--- CONTENT END ---/m)
      match ? match[1] : text
    end

    def self.write_manifest(run_dir, workflow, states, timings)
      FileUtils.mkdir_p(run_dir)
      path = File.join(run_dir, "_manifest.txt")
      content = +"--- KIROFLOW RUN MANIFEST ---\n"
      content << "Run ID: #{File.basename(run_dir)}\n"
      content << "Workflow: #{workflow.name}\n"
      content << "Timestamp: #{Time.now.iso8601}\n"
      content << "\n--- NODE STATES ---\n"
      states.each { |name, state| content << "#{name}: #{state}#{timings[name] ? " (#{timings[name].round(2)}s)" : ""}\n" }
      content << "\n--- EDGES ---\n"
      workflow.edges.each { |from, tos| content << "#{from} -> #{tos.join(', ')}\n" }
      File.write(path, content)
    end
  end
end
