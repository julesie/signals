class HealthPayload < ApplicationRecord
  belongs_to :user

  validates :raw_json, presence: true
  validates :status, presence: true, inclusion: {in: %w[pending processed failed]}
end
