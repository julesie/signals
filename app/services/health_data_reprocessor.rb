class HealthDataReprocessor
  def self.call
    new.call
  end

  def call
    metrics_by_name = {}
    workouts_by_id = {}

    HealthPayload.order(:created_at).find_each do |payload|
      data = payload.raw_json["data"]
      next unless data

      # Merge metrics: deduplicate data points by (name, date) timestamp
      (data["metrics"] || []).each do |metric_entry|
        name = metric_entry["name"]
        units = metric_entry["units"]
        metrics_by_name[name] ||= {"name" => name, "units" => units, "data_by_ts" => {}}

        metric_entry["data"]&.each do |dp|
          ts = dp["date"]
          # Later payloads overwrite earlier ones for same timestamp
          metrics_by_name[name]["data_by_ts"][ts] = dp
        end
      end

      # Merge workouts: latest payload wins for same ID
      (data["workouts"] || []).each do |workout|
        workouts_by_id[workout["id"]] = workout
      end
    end

    # Build deduplicated metrics array
    merged_metrics = metrics_by_name.map do |name, entry|
      {"name" => name, "units" => entry["units"], "data" => entry["data_by_ts"].values}
    end

    # Clear and reprocess as single merged dataset
    ActiveRecord::Base.transaction do
      HealthMetric.delete_all
      Workout.delete_all

      metrics_result = MetricsParser.call(merged_metrics)
      workouts_result = WorkoutParser.call(workouts_by_id.values)

      HealthPayload.update_all(status: "processed", error_message: nil)

      {metrics: metrics_result, workouts: workouts_result}
    end
  end
end
