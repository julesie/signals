class HealthMetric < ApplicationRecord
  belongs_to :user

  validates :metric_name, presence: true
  validates :recorded_at, presence: true
  validates :value, presence: true
  validates :units, presence: true
  validates :metric_name, uniqueness: {scope: [:user_id, :recorded_at]}
end
