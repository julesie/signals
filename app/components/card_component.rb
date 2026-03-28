# frozen_string_literal: true

class CardComponent < ViewComponent::Base
  def initialize(flush: false)
    @flush = flush
  end

  def padding_classes
    @flush ? "" : "p-6"
  end
end
