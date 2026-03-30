class Api::V1::HealthDataController < ActionController::API
  before_action :authenticate_token!

  def create
    user = User.find_by!(email: "jules@julescoleman.com")

    health_payload = user.health_payloads.create!(
      raw_json: JSON.parse(request.raw_post),
      status: "pending"
    )

    result = HealthDataProcessor.call(health_payload, user: user)

    if result.success
      render json: {
        status: "ok",
        metrics_count: result.metrics_created,
        workouts_count: result.workouts_created
      }
    else
      render json: {
        status: "error",
        error: health_payload.reload.error_message
      }, status: :unprocessable_entity
    end
  end

  private

  def authenticate_token!
    expected = ENV["WEBHOOK_AUTH_TOKEN"]
    head(:unauthorized) and return if expected.blank?

    token = request.headers["Authorization"]&.split("Bearer ")&.last
    head :unauthorized unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
  end
end
