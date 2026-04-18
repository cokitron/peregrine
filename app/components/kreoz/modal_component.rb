class Kreoz::ModalComponent < ViewComponent::Base
  renders_one :header
  renders_one :body
  renders_one :footer

  def initialize(id:, title:)
    @id    = id
    @title = title
  end
end
