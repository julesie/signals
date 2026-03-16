class MetricsParser
  Result = Struct.new(:created, :skipped, keyword_init: true)

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
    skipped = 0

    @metrics_data.each do |metric_entry|
      name = metric_entry["name"]
      next if IGNORED_METRICS.include?(name)

      c, s = if name == "heart_rate"
        process_heart_rate(metric_entry)
      elsif SUM_METRICS.include?(name) || AVG_METRICS.include?(name)
        process_aggregated(metric_entry)
      else
        process_individual(metric_entry)
      end

      created += c
      skipped += s
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def process_heart_rate(metric_entry)
    units = metric_entry["units"]
    by_date = metric_entry["data"].group_by { |dp| parse_timestamp(dp["date"]).to_date }
    created = 0
    skipped = 0

    by_date.each do |date, points|
      recorded_at = date.beginning_of_day
      mins = points.filter_map { |dp| dp["Min"] }
      maxes = points.filter_map { |dp| dp["Max"] }
      avgs = points.filter_map { |dp| dp["Avg"] || dp["qty"] }
      next if avgs.empty?

      if HealthMetric.exists?(metric_name: "heart_rate", recorded_at: recorded_at)
        skipped += 1
      else
        avg = (avgs.sum.to_f / avgs.size).round(1)
        HealthMetric.create!(
          metric_name: "heart_rate",
          recorded_at: recorded_at,
          value: avg,
          units: units,
          metadata: {
            "min" => mins.any? ? mins.min : avgs.min,
            "max" => maxes.any? ? maxes.max : avgs.max,
            "avg" => avg,
            "count" => points.size
          }
        )
        created += 1
      end
    end

    [created, skipped]
  end

  def process_aggregated(metric_entry)
    name = metric_entry["name"]
    units = metric_entry["units"]
    by_date = metric_entry["data"].group_by { |dp| parse_timestamp(dp["date"]).to_date }
    created = 0
    skipped = 0

    by_date.each do |date, points|
      recorded_at = date.beginning_of_day
      values = points.filter_map { |dp| dp["qty"] }
      next if values.empty?

      convert = KJ_TO_KCAL_METRICS.include?(name) && units == "kJ"

      if HealthMetric.exists?(metric_name: name, recorded_at: recorded_at)
        skipped += 1
      else
        value = if SUM_METRICS.include?(name)
          values.sum.round(2)
        else
          (values.sum.to_f / values.size).round(2)
        end

        avg = (values.sum.to_f / values.size).round(2)

        if convert
          value = (value / KJ_TO_KCAL).round(1)
          avg = (avg / KJ_TO_KCAL).round(1)
        end

        stored_units = convert ? "kcal" : units

        HealthMetric.create!(
          metric_name: name,
          recorded_at: recorded_at,
          value: value,
          units: stored_units,
          metadata: {"min" => values.min, "max" => values.max, "avg" => avg, "count" => values.size}
        )
        created += 1
      end
    end

    [created, skipped]
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

    [created, skipped]
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
