class Kreoz::BadgeComponent < ViewComponent::Base
  VARIANTS = {
    entrada:    { bg: "bg-kreoz-green-light", text: "text-kreoz-green-dark" },
    salida:     { bg: "bg-kreoz-red-light",   text: "text-kreoz-red-dark" },
    personal:   { bg: "bg-kreoz-purple-light", text: "text-kreoz-purple" },
    cotizacion: { bg: "bg-kreoz-amber-light",  text: "text-kreoz-amber-dark" },
    neutral:    { bg: "bg-gray-100",           text: "text-gray-600" }
  }.freeze

  def initialize(label:, variant: :neutral)
    @label   = label
    @variant = VARIANTS.fetch(variant.to_sym)
  end

  def badge_classes
    "#{@variant[:bg]} #{@variant[:text]} text-xs font-medium px-2 py-0.5 rounded-full"
  end
end
