class Kreoz::SelectComponent < ViewComponent::Base
  def initialize(name:, label:, options:, selected: nil, **html_options)
    @name         = name
    @label        = label
    @options      = options
    @selected     = selected
    @html_options = html_options
    @dom_id       = "select-#{name}"
  end
end
