class MetricsParser
  Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

  IGNORED_METRICS = %w[
    time_in_daylight walking_step_length walking_double_support_percentage
    walking_asymmetry_percentage stair_speed_up stair_speed_down
    environmental_audio_exposure headphone_audio_exposure
  ].freeze

  # Health Auto Export sends metric names that differ from our canonical names
  NAME_MAP = {
    "weight_body_mass" => "weight"
  }.freeze

  KJ_TO_KCAL_METRICS = %w[active_energy basal_energy_burned].freeze
  KJ_TO_KCAL = 4.184

  def self.call(metrics_data, user:)
    new(metrics_data, user: user).call
  end

  def initialize(metrics_data, user:)
    @metrics_data = metrics_data
    @user = user
  end

  def call
    created = 0
    updated = 0
    skipped = 0

    @metrics_data.each do |metric_entry|
      raw_name = metric_entry["name"]
      name = NAME_MAP.fetch(raw_name, raw_name)
      next if IGNORED_METRICS.include?(name)

      units = metric_entry["units"]

      metric_entry["data"].each do |data_point|
        recorded_at = parse_timestamp(data_point["date"])
        value = extract_value(name, data_point)
        metadata = extract_metadata(name, data_point)

        # Convert kJ to kcal for energy metrics
        convert = KJ_TO_KCAL_METRICS.include?(name) && units == "kJ"
        if convert
          value = (value / KJ_TO_KCAL).round(1)
        end
        stored_units = convert ? "kcal" : units

        existing = @user.health_metrics.find_by(metric_name: name, recorded_at: recorded_at)
        if existing
          existing.update!(value: value, units: stored_units, metadata: metadata)
          updated += 1
        else
          @user.health_metrics.create!(
            metric_name: name,
            recorded_at: recorded_at,
            value: value,
            units: stored_units,
            metadata: metadata
          )
          created += 1
        end
      end
    end

    Result.new(created: created, updated: updated, skipped: skipped)
  end

  private

  def extract_value(name, data_point)
    case name
    when "sleep_analysis"
      data_point["totalSleep"]
    when "heart_rate"
      data_point["Avg"] || data_point["qty"]
    else
      data_point["qty"]
    end
  end

  def extract_metadata(name, data_point)
    case name
    when "sleep_analysis"
      data_point.except("date", "totalSleep")
    when "heart_rate"
      {"min" => data_point["Min"], "max" => data_point["Max"], "avg" => data_point["Avg"]}
    else
      extra = data_point.except("date", "qty")
      extra.presence
    end
  end

  def parse_timestamp(date_string)
    Time.parse(date_string)
  end
end
