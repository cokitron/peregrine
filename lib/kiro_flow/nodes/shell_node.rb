require "open3"
require "timeout"
require "shellwords"

module KiroFlow
  class ShellNode < Node
    def execute(context)
      cmd = safe_interpolate(context, opts.fetch(:command))
      stdout, stderr, status = Timeout.timeout(opts.fetch(:timeout, 60)) { Open3.capture3("/bin/sh", "-c", cmd) }
      raise "ShellNode #{name} failed (exit #{status.exitstatus}): #{stderr}" unless status.success?
      stdout.strip
    end

    private

    # Interpolates {{var}} placeholders with shell-escaped values to prevent injection.
    def safe_interpolate(context, template)
      template.gsub(/\{\{(\w+?)_file\}\}/) { Shellwords.shellescape(context.file_for(Regexp.last_match(1).to_sym)) }
              .gsub(/\{\{(\w+?)\}\}/) { Shellwords.shellescape(context[Regexp.last_match(1).to_sym].to_s) }
    end
  end
end
