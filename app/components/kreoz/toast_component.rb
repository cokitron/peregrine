class Kreoz::ToastComponent < ViewComponent::Base
  VARIANTS = {
    success: { icon_class: "text-fg-success bg-success-soft", icon_path: "M5 11.917 9.724 16.5 19 7.5" },
    danger:  { icon_class: "text-fg-danger bg-danger-soft",   icon_path: "M6 18 17.94 6M18 18 6.06 6" },
    warning: { icon_class: "text-fg-warning bg-warning-soft", icon_path: "M6 18 17.94 6M18 18 6.06 6" }
  }.freeze

  def initialize(message:, variant: :success)
    @message = message
    @styles  = VARIANTS.fetch(variant.to_sym)
    @dom_id  = "toast-#{variant}-#{SecureRandom.hex(4)}"
  end
end
