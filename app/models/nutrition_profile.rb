class NutritionProfile < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
  validates :calorie_target, presence: true, numericality: {greater_than: 0}
  validates :protein_target, presence: true, numericality: {greater_than: 0}
end
