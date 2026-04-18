class Kreoz::FabComponent < ViewComponent::Base
  def initialize(label:, path:)
    @label = label
    @path  = path
  end
end
