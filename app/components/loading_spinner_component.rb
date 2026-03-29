# frozen_string_literal: true

class LoadingSpinnerComponent < ViewComponent::Base
  def initialize(text: "Loading...")
    @text = text
  end
end
