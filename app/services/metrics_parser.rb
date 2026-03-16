class MetricsParser
  Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

  IGNORED_METRICS = %w[
    time_in_daylight walking_step_length walking_double_support_percentage
    walking_asymmetry_percentage stair_speed_up stair_speed_down
    environmental_audio_exposure headphone_audio_exposure
  ].freeze

  SUM_METRICS = %w[
    step_count active_energy basal_energy_burned walking_running_distance
    flights_climbed apple_exercise_time apple_stand_time apple_stand_hour
    swimming_distance swimming_stroke_count physical_effort
  ].freeze

  AVG_METRICS = %w[
    respiratory_rate heart_rate_variability walking_speed
  ].freeze

  KJ_TO_KCAL_METRICS = %w[active_energy basal_energy_burned].freeze
  KJ_TO_KCAL = 4.184

  def self.call(metrics_data)
    new(metrics_data).call
  end

  def initialize(metrics_data)
    @metrics_data = metrics_data
  end

  def call
    created = 0
    updated = 0
    skipped = 0

    @metrics_data.each do |metric_entry|
      name = metric_entry["name"]
      next if IGNORED_METRICS.include?(name)

      c, u, s = if name == "heart_rate"
        process_heart_rate(metric_entry)
      elsif SUM_METRICS.include?(name) || AVG_METRICS.include?(name)
        process_aggregated(metric_entry)
      else
        process_individual(metric_entry)
      end

      created += c
      updated += u
      skipped += s
    end

    Result.new(created: created, updated: updated, skipped: skipped)
  end

  private

  def process_heart_rate(metric_entry)
    units = metric_entry["units"]
    by_date = metric_entry["data"].group_by { |dp| parse_timestamp(dp["date"]).to_date }
    created = 0
    updated = 0

    by_date.each do |date, points|
      recorded_at = date.beginning_of_day
      new_mins = points.filter_map { |dp| dp["Min"] }
      new_maxes = points.filter_map { |dp| dp["Max"] }
      new_avgs = points.filter_map { |dp| dp["Avg"] || dp["qty"] }
      next if new_avgs.empty?

      existing = HealthMetric.find_by(metric_name: "heart_rate", recorded_at: recorded_at)

      if existing
        old = existing.metadata || {}
        old_count = old["count"] || 0
        old_sum = (old["avg"] || 0) * old_count
        total_count = old_count + new_avgs.size
        combined_avg = ((old_sum + new_avgs.sum) / total_count).round(1)

        existing.update!(
          value: combined_avg,
          metadata: {
            "min" => [old["min"], new_mins.any? ? new_mins.min : new_avgs.min].compact.min,
            "max" => [old["max"], new_maxes.any? ? new_maxes.max : new_avgs.max].compact.max,
            "avg" => combined_avg,
            "count" => total_count
          }
        )
        updated += 1
      else
        avg = (new_avgs.sum.to_f / new_avgs.size).round(1)
        HealthMetric.create!(
          metric_name: "heart_rate",
          recorded_at: recorded_at,
          value: avg,
          units: units,
          metadata: {
            "min" => new_mins.any? ? new_mins.min : new_avgs.min,
            "max" => new_maxes.any? ? new_maxes.max : new_avgs.max,
            "avg" => avg,
            "count" => new_avgs.size
          }
        )
        created += 1
      end
    end

    [created, updated, 0]
  end

  def process_aggregated(metric_entry)
    name = metric_entry["name"]
    units = metric_entry["units"]
    by_date = metric_entry["data"].group_by { |dp| parse_timestamp(dp["date"]).to_date }
    created = 0
    updated = 0

    convert = KJ_TO_KCAL_METRICS.include?(name) && units == "kJ"

    by_date.each do |date, points|
      recorded_at = date.beginning_of_day
      new_values = points.filter_map { |dp| dp["qty"] }
      next if new_values.empty?

      new_values = new_values.map { |v| (v / KJ_TO_KCAL).round(4) } if convert

      existing = HealthMetric.find_by(metric_name: name, recorded_at: recorded_at)

      if existing
        old = existing.metadata || {}
        old_count = old["count"] || 0

        if SUM_METRICS.include?(name)
          new_sum = new_values.sum.round(2)
          combined_value = (existing.value + new_sum).round(2)
          total_count = old_count + new_values.size
          combined_avg = (combined_value.to_f / total_count).round(2)
        else
          old_sum = (old["avg"] || 0) * old_count
          total_count = old_count + new_values.size
          combined_avg = ((old_sum + new_values.sum) / total_count).round(2)
          combined_value = combined_avg
        end

        existing.update!(
          value: combined_value,
          metadata: {
            "min" => [old["min"], new_values.min].compact.min,
            "max" => [old["max"], new_values.max].compact.max,
            "avg" => combined_avg,
            "count" => total_count
          }
        )
        updated += 1
      else
        value = if SUM_METRICS.include?(name)
          new_values.sum.round(2)
        else
          (new_values.sum.to_f / new_values.size).round(2)
        end

        avg = (new_values.sum.to_f / new_values.size).round(2)

        HealthMetric.create!(
          metric_name: name,
          recorded_at: recorded_at,
          value: value,
          units: convert ? "kcal" : units,
          metadata: {"min" => new_values.min, "max" => new_values.max, "avg" => avg, "count" => new_values.size}
        )
        created += 1
      end
    end

    [created, updated, 0]
  end

  def process_individual(metric_entry)
    name = metric_entry["name"]
    units = metric_entry["units"]
    created = 0
    skipped = 0

    metric_entry["data"].each do |data_point|
      recorded_at = parse_timestamp(data_point["date"])
      value = extract_value(name, data_point)
      metadata = extract_metadata(name, data_point)

      if HealthMetric.exists?(metric_name: name, recorded_at: recorded_at)
        skipped += 1
      else
        HealthMetric.create!(
          metric_name: name,
          recorded_at: recorded_at,
          value: value,
          units: units,
          metadata: metadata
        )
        created += 1
      end
    end

    [created, 0, skipped]
  end

  def extract_value(name, data_point)
    case name
    when "sleep_analysis"
      data_point["totalSleep"]
    else
      data_point["qty"]
    end
  end

  def extract_metadata(name, data_point)
    case name
    when "sleep_analysis"
      data_point.except("date", "totalSleep")
    else
      extra = data_point.except("date", "qty")
      extra.presence
    end
  end

  def parse_timestamp(date_string)
    Time.parse(date_string)
  end
end
