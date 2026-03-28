# frozen_string_literal: true

class PageLayoutComponent < ViewComponent::Base
  def initialize(max_width: "max-w-4xl")
    @max_width = max_width
  end
end
