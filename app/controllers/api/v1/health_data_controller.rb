class Api::V1::HealthDataController < ActionController::API
  before_action :authenticate_token!

  def create
    health_payload = HealthPayload.create!(
      raw_json: params.to_unsafe_h,
      status: "pending"
    )

    result = HealthDataProcessor.call(health_payload)

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
    token = request.headers["Authorization"]&.split("Bearer ")&.last
    head :unauthorized unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, ENV.fetch("WEBHOOK_AUTH_TOKEN"))
  end
end
