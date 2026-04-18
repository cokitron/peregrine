module WorkflowsHelper
  NODE_STYLES = {
    "kiro"     => { icon: "⚡", bg: "bg-kreoz-green",  text: "text-white" },
    "shell"    => { icon: "▶",  bg: "bg-kreoz-amber",  text: "text-kreoz-amber-dark" },
    "ruby"     => { icon: "◆",  bg: "bg-kreoz-purple", text: "text-white" },
    "gate"     => { icon: "◇",  bg: "bg-kreoz-red",    text: "text-white" },
    "workflow" => { icon: "🔗", bg: "bg-blue-600",     text: "text-white" }
  }.freeze

  def node_style(type)
    NODE_STYLES[type] || NODE_STYLES["kiro"]
  end

  def run_status_dot(status)
    case status.to_s
    when "completed" then "bg-kreoz-green"
    when "running"   then "bg-blue-500 animate-pulse"
    when "failed"    then "bg-kreoz-red"
    else "bg-gray-400"
    end
  end

  def run_status_badge(status)
    case status.to_s
    when "completed" then "bg-kreoz-green-light text-kreoz-green"
    when "running"   then "bg-blue-50 text-blue-600"
    when "failed"    then "bg-kreoz-red-light text-kreoz-red"
    else "bg-gray-100 text-gris"
    end
  end
end
