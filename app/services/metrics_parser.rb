class MetricsParser
  Result = Struct.new(:created, :skipped, keyword_init: true)

  SLEEP_VALUE_KEY = "totalSleep"
  HR_VALUE_KEY = "Avg"
  SIMPLE_VALUE_KEY = "qty"

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
      units = metric_entry["units"]

      metric_entry["data"].each do |data_point|
        recorded_at = parse_timestamp(data_point["date"])
        value = extract_value(name, data_point)
        metadata = extract_metadata(name, data_point)

        existing = HealthMetric.find_by(metric_name: name, recorded_at: recorded_at)
        if existing
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
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def extract_value(name, data_point)
    case name
    when "sleep_analysis"
      data_point[SLEEP_VALUE_KEY]
    when "heart_rate"
      data_point[HR_VALUE_KEY]
    else
      data_point[SIMPLE_VALUE_KEY]
    end
  end

  def extract_metadata(name, data_point)
    case name
    when "sleep_analysis"
      data_point.except("date", SLEEP_VALUE_KEY)
    when "heart_rate"
      {"min" => data_point["Min"], "avg" => data_point["Avg"], "max" => data_point["Max"]}
    else
      extra = data_point.except("date", SIMPLE_VALUE_KEY)
      extra.presence
    end
  end

  def parse_timestamp(date_string)
    Time.parse(date_string)
  end
end
