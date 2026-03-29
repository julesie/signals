class Workout < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :workout_type, presence: true
  validates :started_at, presence: true
  validates :ended_at, presence: true
  validates :duration, presence: true
  validates :notes, length: {maximum: 280}, allow_blank: true
end
