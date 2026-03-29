class Plan < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true

  def has_content?
    content.present?
  end

  def has_suggestion?
    daily_suggestion.present?
  end
end
