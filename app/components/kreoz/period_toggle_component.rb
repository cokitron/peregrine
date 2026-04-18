class Kreoz::PeriodToggleComponent < ViewComponent::Base
  PERIODS = %w[hoy semana mes].freeze

  def initialize(current:, base_path:, turbo_frame: nil)
    @current     = current.to_s
    @base_path   = base_path
    @turbo_frame = turbo_frame
  end

  def periods = PERIODS

  def active?(period) = period == @current

  def tab_class(period)
    active?(period) ? "tab-active" : "tab-inactive"
  end

  def period_path(period)
    "#{@base_path}?periodo=#{period}"
  end
end
