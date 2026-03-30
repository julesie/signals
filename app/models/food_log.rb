class FoodLog < ApplicationRecord
  MEALTIMES = %w[breakfast lunch dinner snack].freeze

  belongs_to :user
  belongs_to :food

  validates :consumed_at, presence: true
  validates :mealtime, inclusion: {in: MEALTIMES}, allow_nil: true

  scope :on_date, ->(date) { where(consumed_at: date.all_day) }
  scope :by_mealtime, ->(mealtime) { where(mealtime: mealtime) }
  scope :chronological, -> { order(consumed_at: :asc) }

  def net_carbs
    (carbs || 0) - (fibre || 0)
  end

  def stamp_macros_from_food!
    self.kcal = food.kcal
    self.protein = food.protein
    self.carbs = food.carbs
    self.fat = food.fat
    self.fibre = food.fibre
    self.alcohol = food.alcohol
  end

  def self.default_mealtime
    hour = Time.current.hour
    min = Time.current.min
    time_in_minutes = hour * 60 + min

    if time_in_minutes < 690      # before 11:30
      "breakfast"
    elsif time_in_minutes < 990   # before 16:30
      "lunch"
    else
      "dinner"
    end
  end
end
