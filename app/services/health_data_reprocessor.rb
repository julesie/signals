class HealthDataReprocessor
  def self.call
    new.call
  end

  def call
    results = {}

    HealthPayload.select(:user_id).distinct.pluck(:user_id).each do |user_id|
      user = User.find(user_id)
      results[user_id] = reprocess_for_user(user)
    end

    HealthPayload.update_all(status: "processed", error_message: nil)

    results
  end

  private

  def reprocess_for_user(user)
    metrics_by_name = {}
    workouts_by_id = {}

    user.health_payloads.order(:created_at).find_each do |payload|
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

    # Clear this user's data and reprocess from merged payloads
    ActiveRecord::Base.transaction do
      user.health_metrics.delete_all
      user.workouts.delete_all

      metrics_result = MetricsParser.call(merged_metrics, user: user)
      workouts_result = WorkoutParser.call(workouts_by_id.values, user: user)

      {metrics: metrics_result, workouts: workouts_result}
    end
  end
end
