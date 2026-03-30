require "csv"

class CsvImporter
  Result = Struct.new(:metrics_created, :metrics_updated, :workouts_created, :workouts_updated, keyword_init: true)

  METRIC_COLUMNS = {
    "Active Energy (kJ)" => {name: "active_energy", units: "kJ"},
    "Apple Exercise Time (min)" => {name: "apple_exercise_time", units: "min"},
    "Apple Stand Hour (count)" => {name: "apple_stand_hour", units: "count"},
    "Apple Stand Time (min)" => {name: "apple_stand_time", units: "min"},
    "Body Fat Percentage (%)" => {name: "body_fat_percentage", units: "%"},
    "Breathing Disturbances (count)" => {name: "breathing_disturbances", units: "count"},
    "Flights Climbed (count)" => {name: "flights_climbed", units: "count"},
    "Heart Rate Variability (ms)" => {name: "heart_rate_variability", units: "ms"},
    "Physical Effort (kcal/hr·kg)" => {name: "physical_effort", units: "kcal/hr·kg"},
    "Respiratory Rate (count/min)" => {name: "respiratory_rate", units: "count/min"},
    "Resting Energy (kJ)" => {name: "basal_energy_burned", units: "kJ"},
    "Resting Heart Rate (count/min)" => {name: "resting_heart_rate", units: "count/min"},
    "Step Count (count)" => {name: "step_count", units: "count"},
    "Swimming Distance (m)" => {name: "swimming_distance", units: "m"},
    "Swimming Stroke Count (count)" => {name: "swimming_stroke_count", units: "count"},
    "VO2 Max (ml/(kg·min))" => {name: "vo2_max", units: "ml/(kg·min)"},
    "Walking + Running Distance (km)" => {name: "walking_running_distance", units: "km"},
    "Walking Heart Rate Average (count/min)" => {name: "walking_heart_rate_average", units: "count/min"},
    "Walking Speed (km/hr)" => {name: "walking_speed", units: "km/hr"},
    "Weight (kg)" => {name: "weight", units: "kg"}
  }.freeze

  KJ_TO_KCAL = 4.184
  KJ_METRICS = %w[active_energy basal_energy_burned].freeze

  def self.call(metrics_csv_path:, user:, workouts_csv_path: nil)
    new(metrics_csv_path: metrics_csv_path, user: user, workouts_csv_path: workouts_csv_path).call
  end

  def initialize(metrics_csv_path:, user:, workouts_csv_path: nil)
    @metrics_csv_path = metrics_csv_path
    @workouts_csv_path = workouts_csv_path
    @user = user
  end

  def call
    mc, mu = import_metrics
    wc, wu = @workouts_csv_path ? import_workouts : [0, 0]

    Result.new(metrics_created: mc, metrics_updated: mu, workouts_created: wc, workouts_updated: wu)
  end

  private

  def import_metrics
    created = 0
    updated = 0

    CSV.foreach(@metrics_csv_path, headers: true) do |row|
      recorded_at = Time.parse(row["Date/Time"])

      # Heart rate
      hr_avg = row["Heart Rate [Avg] (count/min)"]
      if hr_avg.present?
        c, u = upsert_metric(
          name: "heart_rate", recorded_at: recorded_at,
          value: hr_avg.to_f, units: "count/min",
          metadata: {
            "min" => row["Heart Rate [Min] (count/min)"]&.to_f,
            "max" => row["Heart Rate [Max] (count/min)"]&.to_f,
            "avg" => hr_avg.to_f
          }
        )
        created += c
        updated += u
      end

      # Sleep
      sleep_total = row["Sleep Analysis [Total] (hr)"]
      if sleep_total.present? && sleep_total.to_f > 0
        c, u = upsert_metric(
          name: "sleep_analysis", recorded_at: recorded_at,
          value: sleep_total.to_f, units: "hr",
          metadata: {
            "asleep" => row["Sleep Analysis [Asleep] (hr)"]&.to_f,
            "inBed" => row["Sleep Analysis [In Bed] (hr)"]&.to_f,
            "core" => row["Sleep Analysis [Core] (hr)"]&.to_f,
            "deep" => row["Sleep Analysis [Deep] (hr)"]&.to_f,
            "rem" => row["Sleep Analysis [REM] (hr)"]&.to_f,
            "awake" => row["Sleep Analysis [Awake] (hr)"]&.to_f
          }.compact
        )
        created += c
        updated += u
      end

      # All other mapped metrics
      METRIC_COLUMNS.each do |column, config|
        raw_value = row[column]
        next if raw_value.blank?

        value = raw_value.to_f
        units = config[:units]
        name = config[:name]

        if KJ_METRICS.include?(name) && units == "kJ"
          value = (value / KJ_TO_KCAL).round(1)
          units = "kcal"
        end

        c, u = upsert_metric(name: name, recorded_at: recorded_at, value: value, units: units)
        created += c
        updated += u
      end
    end

    [created, updated]
  end

  def import_workouts
    created = 0
    updated = 0

    CSV.foreach(@workouts_csv_path, headers: true) do |row|
      start_time = Time.parse(row["Start"])
      external_id = "csv-#{row["Workout Type"]}-#{start_time.iso8601}"
      duration = parse_duration(row["Duration"])
      active_energy_kj = row["Active Energy (kJ)"]&.to_f
      distance = row["Distance (km)"]&.to_f

      attrs = {
        workout_type: row["Workout Type"],
        started_at: start_time,
        ended_at: Time.parse(row["End"]),
        duration: duration,
        distance: distance&.positive? ? distance : nil,
        distance_units: distance&.positive? ? "km" : nil,
        energy_burned: active_energy_kj ? (active_energy_kj / KJ_TO_KCAL).round(1) : nil,
        metadata: build_workout_metadata(row)
      }

      existing = @user.workouts.find_by(external_id: external_id)
      if existing
        existing.update!(**attrs)
        updated += 1
      else
        @user.workouts.create!(external_id: external_id, **attrs)
        created += 1
      end
    end

    [created, updated]
  end

  def build_workout_metadata(row)
    {
      "avg_hr" => row["Avg. Heart Rate (count/min)"]&.to_f,
      "max_hr" => row["Max. Heart Rate (count/min)"]&.to_f,
      "elevation_ascended" => row["Elevation Ascended (m)"]&.to_f,
      "step_count" => row["Step Count"]&.to_f,
      "step_cadence" => row["Step Cadence (spm)"]&.to_f,
      "swimming_stroke_count" => row["Swimming Stroke Count"]&.to_i,
      "location" => row["Location"],
      "temperature" => row["Temperature (degC)"]&.to_f,
      "humidity" => row["Humidity (%)"]&.to_f
    }.compact.reject { |_, v| v == 0 || v == 0.0 || v.blank? }
  end

  def upsert_metric(name:, recorded_at:, value:, units:, metadata: nil)
    existing = @user.health_metrics.find_by(metric_name: name, recorded_at: recorded_at)
    if existing
      existing.update!(value: value, units: units, metadata: metadata)
      [0, 1]
    else
      @user.health_metrics.create!(metric_name: name, recorded_at: recorded_at, value: value, units: units, metadata: metadata)
      [1, 0]
    end
  end

  def parse_duration(duration_str)
    return 0 if duration_str.blank?
    parts = duration_str.split(":").map(&:to_i)
    (parts[0] * 3600) + (parts[1] * 60) + parts[2]
  end
end
