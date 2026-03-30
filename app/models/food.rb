class Food < ApplicationRecord
  belongs_to :user
  has_many :food_logs, dependent: :destroy

  validates :description, presence: true
  validates :kcal, presence: true
  validates :protein, presence: true
  validates :carbs, presence: true
  validates :fat, presence: true
  validates :fibre, presence: true

  def net_carbs
    (carbs || 0) - (fibre || 0)
  end
end
