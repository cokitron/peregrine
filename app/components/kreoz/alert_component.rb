class Kreoz::AlertComponent < ViewComponent::Base
  VARIANTS = {
    positive: {
      bg: "bg-kreoz-green-light", text: "text-kreoz-green-dark",
      border: "border-kreoz-green", icon_color: "text-kreoz-green"
    },
    alert: {
      bg: "bg-kreoz-amber-light", text: "text-kreoz-amber-dark",
      border: "border-kreoz-amber", icon_color: "text-kreoz-amber"
    },
    negative: {
      bg: "bg-kreoz-red-light", text: "text-kreoz-red-dark",
      border: "border-kreoz-red", icon_color: "text-kreoz-red"
    },
    info: {
      bg: "bg-blue-50", text: "text-blue-800",
      border: "border-blue-300", icon_color: "text-blue-500"
    }
  }.freeze

  def initialize(message:, variant: :info, dismissible: false)
    @message     = message
    @styles      = VARIANTS.fetch(variant.to_sym)
    @dismissible = dismissible
    @dom_id      = "alert-#{SecureRandom.hex(4)}"
  end

  def dismissible? = @dismissible
end
