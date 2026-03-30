class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
    :rememberable, :validatable

  has_one :plan, dependent: :destroy
  has_many :workouts, dependent: :delete_all
  has_many :health_metrics, dependent: :delete_all
  has_many :health_payloads, dependent: :delete_all
end
