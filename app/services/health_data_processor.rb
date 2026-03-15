class HealthDataProcessor
  Result = Struct.new(:success, :metrics_created, :metrics_skipped, :workouts_created, :workouts_skipped, keyword_init: true)

  def self.call(health_payload)
    new(health_payload).call
  end

  def initialize(health_payload)
    @health_payload = health_payload
  end

  def call
    data = @health_payload.raw_json["data"]
    metrics_result = nil
    workouts_result = nil

    ActiveRecord::Base.transaction do
      metrics_data = data["metrics"] || []
      workouts_data = data["workouts"] || []

      metrics_result = MetricsParser.call(metrics_data)
      workouts_result = WorkoutParser.call(workouts_data)
    end

    @health_payload.update!(status: "processed")

    Result.new(
      success: true,
      metrics_created: metrics_result.created,
      metrics_skipped: metrics_result.skipped,
      workouts_created: workouts_result.created,
      workouts_skipped: workouts_result.skipped
    )
  rescue => e
    @health_payload.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
    Result.new(
      success: false,
      metrics_created: 0,
      metrics_skipped: 0,
      workouts_created: 0,
      workouts_skipped: 0
    )
  end
end
