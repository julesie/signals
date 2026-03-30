class HealthMetric < ApplicationRecord
  METRIC_TYPES = %w[weight body_fat_percentage vo2_max resting_heart_rate heart_rate_variability step_count active_energy dietary_energy sleep_analysis].freeze

  belongs_to :user

  validates :metric_name, presence: true
  validates :recorded_at, presence: true
  validates :value, presence: true
  validates :units, presence: true
  validates :metric_name, uniqueness: {scope: [:user_id, :recorded_at]}

  scope :by_name, ->(name) { where(metric_name: name) }
  scope :in_date_range, ->(from, to) { where(recorded_at: from..to) }
end
