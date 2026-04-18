class Kreoz::TextInputComponent < ViewComponent::Base
  STATES = {
    default: { label: "text-heading",
input: "bg-neutral-secondary-medium border-default-medium text-heading focus:ring-brand focus:border-brand placeholder:text-body" },
    success: { label: "text-kreoz-green",
input: "bg-green-50 border-kreoz-green text-kreoz-green focus:ring-kreoz-green focus:border-kreoz-green placeholder:text-green-400" },
    error:   { label: "text-kreoz-red",
input: "bg-red-50 border-kreoz-red text-kreoz-red focus:ring-kreoz-red focus:border-kreoz-red placeholder:text-red-400" }
  }.freeze

  def initialize(name:, label:, type: "text", state: :default, message: nil, prefix: nil, disabled: false, value: nil, placeholder: nil,
**html_options)
    @name         = name
    @label        = label
    @type         = type
    @styles       = STATES.fetch(state.to_sym)
    @message      = message
    @prefix       = prefix
    @disabled     = disabled
    @value        = value
    @placeholder  = placeholder
    @html_options = html_options
    @dom_id       = "input-#{name}"
  end
end
