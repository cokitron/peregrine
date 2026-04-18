class Kreoz::EmptyStateComponent < ViewComponent::Base
  def initialize(message:, action_label: nil, action_path: nil)
    @message      = message
    @action_label = action_label
    @action_path  = action_path
  end

  def action?
    @action_label.present? && @action_path.present?
  end
end
