class HealthDataProcessor
  Result = Struct.new(:success, :metrics_created, :metrics_updated, :metrics_skipped, :workouts_created, :workouts_skipped, keyword_init: true)

  def self.call(health_payload, user:)
    new(health_payload, user: user).call
  end

  def initialize(health_payload, user:)
    @health_payload = health_payload
    @user = user
  end

  def call
    data = @health_payload.raw_json["data"]
    metrics_result = nil
    workouts_result = nil

    ActiveRecord::Base.transaction do
      metrics_data = data["metrics"] || []
      workouts_data = data["workouts"] || []

      metrics_result = MetricsParser.call(metrics_data, user: @user)
      workouts_result = WorkoutParser.call(workouts_data, user: @user)
      @health_payload.update!(status: "processed")
    end

    Result.new(
      success: true,
      metrics_created: metrics_result.created,
      metrics_updated: metrics_result.updated,
      metrics_skipped: metrics_result.skipped,
      workouts_created: workouts_result.created,
      workouts_skipped: workouts_result.skipped
    )
  rescue => e
    @health_payload.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
    Result.new(
      success: false,
      metrics_created: 0,
      metrics_updated: 0,
      metrics_skipped: 0,
      workouts_created: 0,
      workouts_skipped: 0
    )
  end
end
