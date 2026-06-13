module Notion
  class DailyLogSync
    Result = Struct.new(:success, :page_id, :created, :error, keyword_init: true)

    GRAMS_PER_DRINK = 14.0
    DAY_TYPE_RANK = ["Rest", "Golf", "Strength", "Easy Run", "Hard Run", "Long Run"].freeze

    def self.call(user, date:, day_type: nil, client: Client.new)
      new(user, date: date, day_type: day_type, client: client).call
    end

    def initialize(user, date:, day_type:, client:)
      @user = user
      @date = date
      @day_type = day_type || "Rest"
      @client = client
    end

    def call
      page = find_page
      properties = data_properties
      if page
        if upgrade_day_type?(Properties.read_select(page["properties"]["Day Type"]))
          properties["Day Type"] = Properties.select(@day_type)
        end
        @client.update_page(page["id"], properties: properties)
        Result.new(success: true, page_id: page["id"], created: false)
      else
        properties["Day"] = Properties.title(training_week.daily_title(@day_type))
        properties["Date"] = Properties.date(@date)
        properties["Day Type"] = Properties.select(@day_type)
        response = @client.create_page(data_source_id: ds_id, properties: properties)
        Result.new(success: true, page_id: response["id"], created: true)
      end
    rescue => e
      Rails.logger.error("Notion::DailyLogSync failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def ds_id = ENV.fetch("NOTION_DAILY_LOGS_DS_ID")

    def training_week = TrainingWeek.new(@date)

    def find_page
      @client.query_data_source(ds_id,
        filter: {"property" => "Date", "date" => {"equals" => @date.iso8601}}).first
    end

    def upgrade_day_type?(current)
      return false if @day_type == "Rest"
      current_rank = DAY_TYPE_RANK.index(current)
      new_rank = DAY_TYPE_RANK.index(@day_type)
      return false if new_rank.nil?
      current.blank? || (current_rank && new_rank > current_rank)
    end

    def data_properties
      props = {}
      {
        "Weight (kg)" => latest_metric("weight"),
        "Sleep Hours" => latest_metric("sleep_analysis"),
        "HRV" => latest_metric("heart_rate_variability"),
        "RHR" => latest_metric("resting_heart_rate")
      }.each { |key, value| props[key] = Properties.number(value.round(2)) if value }

      burned = sum_metric("active_energy") + sum_metric("basal_energy_burned")
      props["Calories Burned"] = Properties.number(burned.round) if burned.positive?

      food = @user.food_logs.where(consumed_at: day_range)
      if food.exists?
        actual = food.sum(:kcal).to_f
        props["Calories Actual"] = Properties.number(actual.round)
        props["Protein (g)"] = Properties.number(food.sum(:protein).round)
        props["Fat (g)"] = Properties.number(food.sum(:fat).round)
        props["Carbs (g)"] = Properties.number(food.sum(:carbs).round)
        props["Deficit"] = Properties.number((actual - burned).round) if burned.positive?

        alcohol_grams = food.sum(:alcohol).to_f
        if alcohol_grams.positive?
          props["Alcohol (drinks)"] = Properties.number(((alcohol_grams / GRAMS_PER_DRINK) * 2).round / 2.0)
        end
      end

      target = @user.nutrition_profile&.calorie_target
      props["Calories Target"] = Properties.number(target) if target
      props
    end

    def day_range = TrainingWeek.day_range(@date)

    def latest_metric(name)
      @latest ||= {}
      return @latest[name] if @latest.key?(name)
      @latest[name] = @user.health_metrics
        .where(metric_name: name, recorded_at: day_range)
        .order(recorded_at: :desc).first&.value&.to_f
    end

    def sum_metric(name)
      @user.health_metrics.where(metric_name: name, recorded_at: day_range).sum(:value).to_f
    end
  end
end
