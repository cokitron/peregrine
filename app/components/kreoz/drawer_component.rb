class Kreoz::DrawerComponent < ViewComponent::Base
  def initialize(id:, title:)
    @id    = id
    @title = title
  end
end
