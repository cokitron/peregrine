module WorkflowsHelper
  NODE_STYLES = {
    "kiro"     => { icon: "⚡", bg: "bg-kreoz-green",  text: "text-white" },
    "shell"    => { icon: "▶",  bg: "bg-kreoz-amber",  text: "text-kreoz-amber-dark" },
    "ruby"     => { icon: "◆",  bg: "bg-kreoz-purple", text: "text-white" },
    "gate"     => { icon: "◇",  bg: "bg-kreoz-red",    text: "text-white" },
    "workflow" => { icon: "🔗", bg: "bg-blue-600",     text: "text-white" }
  }.transform_values(&:freeze).freeze

  def node_style(type)
    NODE_STYLES[type] || NODE_STYLES["kiro"]
  end

  def run_status_dot(status)
    case status.to_s
    when "completed" then "bg-kreoz-green"
    when "running"   then "bg-blue-500 animate-pulse"
    when "failed"    then "bg-kreoz-red"
    when "cancelled" then "bg-gray-400"
    else "bg-gray-400"
    end
  end

  def run_status_badge(status)
    case status.to_s
    when "completed" then "bg-kreoz-green-light text-kreoz-green"
    when "running"   then "bg-blue-50 text-blue-600"
    when "failed"    then "bg-kreoz-red-light text-kreoz-red"
    when "cancelled" then "bg-gray-100 text-gris"
    else "bg-gray-100 text-gris"
    end
  end

  def render_node_output(text)
    html = ERB::Util.html_escape(text)
    html = html.gsub(/^### (.+)$/, '<h3 class="text-sm font-bold text-grafito mt-3 mb-1">\1</h3>')
    html = html.gsub(/^## (.+)$/, '<h2 class="text-base font-bold text-grafito mt-4 mb-1">\1</h2>')
    html = html.gsub(/^# (.+)$/, '<h1 class="text-lg font-bold text-grafito mt-4 mb-2">\1</h1>')
    html = html.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    html = html.gsub(/\*(.+?)\*/, '<em>\1</em>')
    html = html.gsub(/`(.+?)`/, '<code class="px-1 py-0.5 bg-fondo-card rounded text-kreoz-green text-xs">\1</code>')
    html = html.gsub(/^\| (.+)$/, '<div class="font-mono text-xs text-gris">\0</div>')
    html = html.gsub(/^- (.+)$/, '<li class="ml-4 text-sm">• \1</li>')
    html = html.gsub(/\n/, "<br>\n")
    html.html_safe # rubocop:disable Rails/OutputSafety
  end
end
