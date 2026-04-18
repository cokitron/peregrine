class Kreoz::TextareaComponent < ViewComponent::Base
  def initialize(name:, label:, rows: 4, maxlength: nil, placeholder: nil, **html_options)
    @name         = name
    @label        = label
    @rows         = rows
    @maxlength    = maxlength
    @placeholder  = placeholder
    @html_options = html_options
    @dom_id       = "textarea-#{name}"
  end
end
