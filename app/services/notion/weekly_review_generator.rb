module Notion
  class WeeklyReviewGenerator
    Result = Struct.new(:success, :page_id, :created, :error, keyword_init: true)

    ALLOWED_RED_FLAGS = [
      "RHR up", "HRV down", "Weight loss too fast", "Sleep short",
      "Cold intolerance", "Hair shedding", "Low mood", "Brain fog",
      "Soreness >48h", "Sharp pain", "Bleed change", "Quality pace miss",
      "Multiple red flags"
    ].freeze

    # Maps Daily Logs option names → Weekly Reviews option names
    FLAG_MAP = {
      "Sleep <6.5h" => "Sleep short"
    }.freeze

    VALID_STATUSES = ["On Track", "Cautious", "Concern", "Off Plan"].freeze

    InvalidStatusError = Class.new(StandardError)

    SYSTEM_PROMPT = <<~PROMPT
      You are a running coach writing a weekly training review for an athlete preparing
      for the SF Half Marathon (race day: 2026-07-26). Given the week's aggregated data,
      training plan context, and any red flags, produce a strict JSON object with exactly
      these keys: "status", "what_worked", "what_broke", "adjustment_for_next_week".

      "status" must be exactly one of: "On Track", "Cautious", "Concern", "Off Plan".
      The other three values are strings of plain prose (no bullet points, no markdown).

      Respond with ONLY the JSON object — no preamble, no explanation, no code fences.
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
      week = TrainingWeek.new(@date)
      week_start = week.week_start
      week_end = week_start + 6

      existing_page = find_existing_page(week_start)
      aggregates = compute_aggregates(week, week_start, week_end)
      red_flags = compute_red_flags(week_start, week_end, existing_page)
      llm_result = call_llm(aggregates, red_flags, week)

      properties = build_properties(aggregates, red_flags, llm_result)

      if existing_page
        @client.update_page(existing_page["id"], properties: properties)
        Result.new(success: true, page_id: existing_page["id"], created: false)
      else
        properties.merge!(create_only_properties(week))
        response = @client.create_page(
          data_source_id: ENV.fetch("NOTION_WEEKLY_REVIEWS_DS_ID"),
          properties: properties
        )
        Result.new(success: true, page_id: response["id"], created: true)
      end
    rescue => e
      Rails.logger.error("Notion::WeeklyReviewGenerator failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def find_existing_page(week_start)
      @client.query_data_source(
        ENV.fetch("NOTION_WEEKLY_REVIEWS_DS_ID"),
        filter: {"property" => "Week Start", "date" => {"equals" => week_start.iso8601}}
      ).first
    end

    def compute_aggregates(week, week_start, week_end)
      workout_rows = fetch_workout_rows(week_start, week_end)
      db_aggregates = compute_db_aggregates(week_start, week_end)

      done_rows = workout_rows.select { |r| Properties.read_select(r.dig("properties", "Status")) == "Done" }

      planned_km = workout_rows.sum { |r| r.dig("properties", "Planned Distance (km)", "number").to_f }
      actual_km = done_rows.sum { |r| r.dig("properties", "Actual Distance (km)", "number").to_f }

      long_done = done_rows.select { |r| Properties.read_select(r.dig("properties", "Type")) == "Long" }
      long_run_km = long_done.map { |r| r.dig("properties", "Actual Distance (km)", "number").to_f }.max

      quality_done = done_rows.any? { |r| Properties.read_select(r.dig("properties", "Type")) == "Quality" }
      strength_done = done_rows.any? { |r| Properties.read_select(r.dig("properties", "Type")) == "Strength" }

      {
        planned_km: planned_km.positive? ? planned_km.round(2) : nil,
        actual_km: actual_km.positive? ? actual_km.round(2) : nil,
        long_run_km: long_run_km&.positive? ? long_run_km.round(2) : nil,
        quality_done: quality_done,
        strength_done: strength_done,
        avg_hrv: db_aggregates[:avg_hrv],
        avg_rhr: db_aggregates[:avg_rhr],
        avg_sleep: db_aggregates[:avg_sleep],
        weight_start: db_aggregates[:weight_start],
        weight_end: db_aggregates[:weight_end]
      }
    end

    def fetch_workout_rows(week_start, week_end)
      @client.query_data_source(
        ENV.fetch("NOTION_WORKOUTS_DS_ID"),
        filter: {
          "and" => [
            {"property" => "Date", "date" => {"on_or_after" => week_start.iso8601}},
            {"property" => "Date", "date" => {"on_or_before" => week_end.iso8601}}
          ]
        }
      )
    end

    def compute_db_aggregates(week_start, week_end)
      # Collect daily latest values across the week
      hrv_values = []
      rhr_values = []
      sleep_values = []
      weight_readings = []

      (week_start..week_end).each do |day|
        day_range = TrainingWeek.day_range(day)

        hrv = @user.health_metrics.where(metric_name: "heart_rate_variability", recorded_at: day_range)
          .order(recorded_at: :desc).first&.value&.to_f
        hrv_values << hrv if hrv

        rhr = @user.health_metrics.where(metric_name: "resting_heart_rate", recorded_at: day_range)
          .order(recorded_at: :desc).first&.value&.to_f
        rhr_values << rhr if rhr

        sleep = @user.health_metrics.where(metric_name: "sleep_analysis", recorded_at: day_range)
          .order(recorded_at: :desc).first&.value&.to_f
        sleep_values << sleep if sleep

        weight = @user.health_metrics.where(metric_name: "weight", recorded_at: day_range)
          .order(recorded_at: :desc).first&.value&.to_f
        weight_readings << {day: day, value: weight} if weight
      end

      avg_hrv = hrv_values.empty? ? nil : (hrv_values.sum / hrv_values.size).round(1)
      avg_rhr = rhr_values.empty? ? nil : (rhr_values.sum / rhr_values.size).round(1)
      avg_sleep = sleep_values.empty? ? nil : (sleep_values.sum / sleep_values.size).round(2)

      weight_start = weight_readings.min_by { |r| r[:day] }&.dig(:value)
      weight_end = weight_readings.max_by { |r| r[:day] }&.dig(:value)

      {avg_hrv: avg_hrv, avg_rhr: avg_rhr, avg_sleep: avg_sleep,
       weight_start: weight_start, weight_end: weight_end}
    end

    def compute_red_flags(week_start, week_end, existing_page)
      daily_log_rows = @client.query_data_source(
        ENV.fetch("NOTION_DAILY_LOGS_DS_ID"),
        filter: {
          "and" => [
            {"property" => "Date", "date" => {"on_or_after" => week_start.iso8601}},
            {"property" => "Date", "date" => {"on_or_before" => week_end.iso8601}}
          ]
        }
      )

      # Collect all flags from daily logs, map names, filter to allowed
      raw_flags = daily_log_rows.flat_map do |row|
        Properties.read_multi_select(row.dig("properties", "Red Flags"))
      end.uniq

      mapped = raw_flags.map { |f| FLAG_MAP.fetch(f, f) }.select { |f| ALLOWED_RED_FLAGS.include?(f) }.uniq

      # Merge with existing page flags (merge-only on update), then threshold
      existing_flags = existing_page ? Properties.read_multi_select(existing_page.dig("properties", "Red Flags Triggered")) : []
      merged = (existing_flags | mapped).sort
      if merged.count { |f| f != "Multiple red flags" } >= 3 && !merged.include?("Multiple red flags")
        merged = (merged << "Multiple red flags").sort
      end
      merged
    end

    def call_llm(aggregates, red_flags, week)
      race_date = Date.new(2026, 7, 26)
      days_to_race = (race_date - @date).to_i
      plan = @user.plan

      context = <<~CONTEXT
        ## Week #{week.week_number} Summary (#{week.week_start.strftime("%b %-d")} - #{(week.week_start + 6).strftime("%b %-d")})
        Race day: 2026-07-26 (#{days_to_race} days away)

        ## Training Aggregates
        Planned km: #{aggregates[:planned_km] || "N/A"}
        Actual km: #{aggregates[:actual_km] || "N/A"}
        Long Run Distance (km): #{aggregates[:long_run_km] || "N/A"}
        Quality Session Done: #{aggregates[:quality_done]}
        Strength Done: #{aggregates[:strength_done]}
        Avg HRV: #{aggregates[:avg_hrv] || "N/A"}
        Avg RHR: #{aggregates[:avg_rhr] || "N/A"}
        Avg Sleep Hours: #{aggregates[:avg_sleep] || "N/A"}
        Weight Start (kg): #{aggregates[:weight_start] || "N/A"}
        Weight End (kg): #{aggregates[:weight_end] || "N/A"}

        ## Red Flags
        #{red_flags.empty? ? "None" : red_flags.join(", ")}

        ## Training Plan
        #{plan&.content || "No plan on file."}
      CONTEXT

      # Transport/API errors propagate to the outer rescue in #call — a failed
      # LLM call must fail the run, not masquerade as a Cautious review.
      response = RubyLLM.chat(model: ENV.fetch("LLM_MODEL", "gpt-5-nano"))
        .with_params(reasoning_effort: "medium")
        .with_instructions(SYSTEM_PROMPT)
        .ask(context)

      parse_llm_response(response.content)
    end

    def parse_llm_response(content)
      parsed = JSON.parse(content.to_s[/\{.*\}/m].to_s)
      status = parsed["status"]
      raise InvalidStatusError, "invalid status: #{status.inspect}" unless VALID_STATUSES.include?(status)

      {
        status: status,
        what_worked: parsed["what_worked"].to_s,
        what_broke: parsed["what_broke"].to_s,
        adjustment: parsed["adjustment_for_next_week"].to_s
      }
    rescue JSON::ParserError, InvalidStatusError => e
      Rails.logger.error("Notion::WeeklyReviewGenerator LLM output invalid for #{@date}: #{e.message}")
      {status: "Cautious", what_worked: content.to_s, what_broke: "", adjustment: ""}
    end

    def build_properties(aggregates, red_flags, llm_result)
      props = {}

      props["Planned km"] = Properties.number(aggregates[:planned_km]) if aggregates[:planned_km]
      props["Actual km"] = Properties.number(aggregates[:actual_km]) if aggregates[:actual_km]
      props["Long Run Distance (km)"] = Properties.number(aggregates[:long_run_km]) if aggregates[:long_run_km]
      props["Quality Session Done"] = Properties.checkbox(aggregates[:quality_done])
      props["Strength Done"] = Properties.checkbox(aggregates[:strength_done])
      props["Avg HRV"] = Properties.number(aggregates[:avg_hrv]) if aggregates[:avg_hrv]
      props["Avg RHR"] = Properties.number(aggregates[:avg_rhr]) if aggregates[:avg_rhr]
      props["Avg Sleep Hours"] = Properties.number(aggregates[:avg_sleep]) if aggregates[:avg_sleep]
      props["Weight Start (kg)"] = Properties.number(aggregates[:weight_start]) if aggregates[:weight_start]
      props["Weight End (kg)"] = Properties.number(aggregates[:weight_end]) if aggregates[:weight_end]
      props["Red Flags Triggered"] = Properties.multi_select(red_flags) unless red_flags.empty?
      props["Status"] = Properties.select(llm_result[:status])
      props["What Worked"] = Properties.rich_text(llm_result[:what_worked]) unless llm_result[:what_worked].empty?
      props["What Broke"] = Properties.rich_text(llm_result[:what_broke]) unless llm_result[:what_broke].empty?
      props["Adjustment for Next Week"] = Properties.rich_text(llm_result[:adjustment]) unless llm_result[:adjustment].empty?
      props
    end

    def create_only_properties(week)
      {
        "Week" => Properties.title("W#{week.week_number} (#{week.week_start.strftime("%b %-d")} - #{(week.week_start + 6).strftime("%b %-d")})"),
        "Week Number" => Properties.number(week.week_number),
        "Week Start" => Properties.date(week.week_start)
      }
    end
  end
end
