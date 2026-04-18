class Kreoz::CheckboxComponent < ViewComponent::Base
  def initialize(name:, label:, checked: false, disabled: false, **html_options)
    @name         = name
    @label        = label
    @checked      = checked
    @disabled     = disabled
    @html_options = html_options
    @dom_id       = "checkbox-#{name}"
  end
end
