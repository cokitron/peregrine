class Kreoz::ProgressDotsComponent < ViewComponent::Base
  ACTIVE_COLORS = {
    green: "progress-dot-active-green",
    red:   "progress-dot-active-red",
    amber: "progress-dot-active-amber"
  }.freeze

  def initialize(total:, current:, color: :green)
    @total   = total
    @current = current
    @active  = ACTIVE_COLORS.fetch(color.to_sym)
  end

  def dot_class(index)
    index < @current ? @active : ""
  end
end
