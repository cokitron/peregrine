class Kreoz::ButtonComponent < ViewComponent::Base
  VARIANTS = {
    primary:     "btn-primary",
    secondary:   "btn-secondary",
    tertiary:    "btn-tertiary",
    destructive: "btn-destructive"
  }.freeze

  SIZES = {
    sm:   "text-xs px-3 py-1.5",
    base: "text-sm",
    lg:   "text-base px-6 py-3"
  }.freeze

  def initialize(variant: :primary, size: :base, type: "button", disabled: false, **html_options)
    @variant      = VARIANTS.fetch(variant.to_sym)
    @size         = SIZES.fetch(size.to_sym)
    @type         = type
    @disabled     = disabled
    @html_options = html_options
  end

  def button_classes
    classes = [ @variant, @size, "inline-flex items-center justify-center focus:outline-none" ]
    classes << "opacity-50 cursor-not-allowed" if @disabled
    classes.join(" ")
  end
end
