module Notion
  class DailyLogCommentaryGenerator
    Result = Struct.new(:success, :narrative, :flags, :error, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT
      You are a concise daily training coach reviewing one athlete's full day of data.
      Given the day's health metrics, nutrition, workouts, training plan, and yesterday's
      comparison, write one paragraph of narrative commentary: how the day went overall,
      notable signals (sleep, HRV, RHR, nutrition, training load), and what to watch for
      tomorrow. No headers, no bullet points. Be direct and data-specific.
    PROMPT

    def self.call(user, date:, client: Client.new)
      new(user, date: date, client: client).call
    end

    def initialize(user, date:, client:)
      @user = user
      @date = date
      @client = client
    end

    def call
      page = find_or_create_page
      return Result.new(success: false, error: "could not find or create daily log page") unless page

      page_id = page["id"]
      existing_flags = Properties.read_multi_select(page.dig("properties", "Red Flags"))

      narrative = generate_narrative
      return Result.new(success: false, error: narrative[:error]) if narrative[:error]

      computed_flags = RedFlagDetector.call(@user, date: @date)
      merged_flags = (existing_flags | computed_flags).sort

      properties = {"Notes" => Properties.rich_text(narrative[:text])}
      properties["Red Flags"] = Properties.multi_select(merged_flags) if merged_flags != existing_flags.sort

      @client.update_page(page_id, properties: properties)
      Result.new(success: true, narrative: narrative[:text], flags: merged_flags)
    rescue => e
      Rails.logger.error("Notion::DailyLogCommentaryGenerator failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def ds_id = ENV.fetch("NOTION_DAILY_LOGS_DS_ID")

    def find_or_create_page
      page = query_page
      return page if page

      result = DailyLogSync.call(@user, date: @date, client: @client)
      Rails.logger.error("Notion::DailyLogCommentaryGenerator: DailyLogSync failed creating page for #{@date}: #{result.error}") unless result.success
      query_page
    end

    def query_page
      @client.query_data_source(ds_id,
        filter: {"property" => "Date", "date" => {"equals" => @date.iso8601}}).first
    end

    def generate_narrative
      response = RubyLLM.chat(model: ENV.fetch("LLM_MODEL", "gpt-5-nano"))
        .with_params(reasoning_effort: "medium")
        .with_instructions(SYSTEM_PROMPT)
        .ask(build_context)
      {text: response.content}
    rescue => e
      Rails.logger.error("Notion::DailyLogCommentaryGenerator LLM failed for #{@date}: #{e.class}: #{e.message}")
      {error: e.message}
    end

    def build_context
      day_range = TrainingWeek.day_range(@date)
      yesterday_range = TrainingWeek.day_range(@date - 1)
      plan = @user.plan

      metrics = %w[resting_heart_rate heart_rate_variability sleep_analysis weight active_energy basal_energy_burned].each_with_object({}) do |name, h|
        val = @user.health_metrics.where(metric_name: name, recorded_at: day_range)
          .order(recorded_at: :desc).first&.value&.to_f
        h[name] = val if val
      end

      yesterday_metrics = %w[resting_heart_rate heart_rate_variability sleep_analysis weight].each_with_object({}) do |name, h|
        val = @user.health_metrics.where(metric_name: name, recorded_at: yesterday_range)
          .order(recorded_at: :desc).first&.value&.to_f
        h[name] = val if val
      end

      food = @user.food_logs.where(consumed_at: day_range)
      nutrition_profile = @user.nutrition_profile
      workouts = @user.workouts.where(started_at: day_range).order(:started_at)

      <<~CONTEXT
        ## Date
        #{@date.strftime("%A, %B %-d, %Y")}

        ## Today's Metrics
        #{format_metrics(metrics)}

        ## Yesterday's Metrics (for comparison)
        #{format_metrics(yesterday_metrics)}

        ## Nutrition
        #{format_nutrition(food, nutrition_profile)}

        ## Today's Workouts
        #{format_workouts(workouts)}

        ## Training Plan
        #{plan&.content || "No plan on file."}
      CONTEXT
    end

    def format_metrics(metrics)
      return "No data." if metrics.empty?
      lines = []
      lines << "RHR: #{metrics["resting_heart_rate"].round} bpm" if metrics["resting_heart_rate"]
      lines << "HRV: #{metrics["heart_rate_variability"].round} ms" if metrics["heart_rate_variability"]
      lines << "Sleep: #{metrics["sleep_analysis"].round(1)} h" if metrics["sleep_analysis"]
      lines << "Weight: #{metrics["weight"]} kg" if metrics["weight"]
      lines << "Active energy: #{metrics["active_energy"].round} kcal" if metrics["active_energy"]
      lines << "Basal energy: #{metrics["basal_energy_burned"].round} kcal" if metrics["basal_energy_burned"]
      lines.join(", ")
    end

    def format_nutrition(food, nutrition_profile)
      return "No food logged." unless food.exists?
      parts = ["Calories: #{food.sum(:kcal).round} kcal"]
      parts << "target: #{nutrition_profile.calorie_target.round} kcal" if nutrition_profile&.calorie_target
      parts << "Protein: #{food.sum(:protein).round}g"
      parts << "Fat: #{food.sum(:fat).round}g"
      parts << "Carbs: #{food.sum(:carbs).round}g"
      alcohol = food.sum(:alcohol).to_f
      parts << "Alcohol: #{(alcohol / 14.0).round(1)} drinks" if alcohol.positive?
      parts.join(", ")
    end

    def format_workouts(workouts)
      return "No workouts." if workouts.empty?
      workouts.map do |w|
        parts = ["#{w.workout_type} #{(w.duration / 60.0).round} min"]
        parts << "#{w.distance} #{w.distance_units}" if w.distance.present?
        avg_hr = w.metadata&.dig("heartRate", "avg")
        parts << "avg HR #{avg_hr.round}" if avg_hr
        parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
        parts.join(", ")
      end.join("\n")
    end
  end
end
