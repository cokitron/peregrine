class Kreoz::ToggleComponent < ViewComponent::Base
  def initialize(name:, label:, checked: false, disabled: false, **html_options)
    @name         = name
    @label        = label
    @checked      = checked
    @disabled     = disabled
    @html_options = html_options
  end
end
