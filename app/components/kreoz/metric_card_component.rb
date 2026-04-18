class Kreoz::MetricCardComponent < ViewComponent::Base
  COLORS = {
    green:  "text-kreoz-green",
    red:    "text-kreoz-red",
    amber:  "text-kreoz-amber",
    purple: "text-kreoz-purple"
  }.freeze

  def initialize(label:, amount:, color:, hero: false)
    @label  = label
    @amount = amount
    @color  = COLORS.fetch(color.to_sym)
    @hero   = hero
  end

  private

  def value_class
    @hero ? "metric-hero" : "metric-value"
  end
end
