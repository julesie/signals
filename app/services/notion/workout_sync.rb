module Notion
  class WorkoutSync
    Result = Struct.new(:success, :newly_synced_workout_ids, :day_type, :error, keyword_init: true)

    RUN_NOTION_TYPES = %w[Easy Quality Long Race].freeze
    # No "Cross" entry: the Daily Logs Day Type select has no Cross option,
    # and writing an unknown select name would silently add it to the schema.
    DAY_TYPE_FOR_NOTION_TYPE = {
      "Long" => "Long Run", "Quality" => "Hard Run", "Race" => "Hard Run",
      "Easy" => "Easy Run", "Strength" => "Strength", "Golf" => "Golf"
    }.freeze
    MI_TO_KM = 1.609344

    def self.call(user, date:, client: Client.new)
      new(user, date: date, client: client).call
    end

    def initialize(user, date:, client:)
      @user = user
      @date = date
      @client = client
      @newly_synced = []
      @day_types = []
    end

    def call
      workouts = @user.workouts.where(started_at: TrainingWeek.day_range(@date)).order(:started_at)
      workouts.each { |workout| sync_workout(workout) }
      Result.new(success: true, newly_synced_workout_ids: @newly_synced, day_type: top_day_type)
    rescue => e
      Rails.logger.error("Notion::WorkoutSync failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, newly_synced_workout_ids: @newly_synced, day_type: top_day_type, error: e.message)
    end

    private

    def ds_id = ENV.fetch("NOTION_WORKOUTS_DS_ID")

    def sync_workout(workout)
      if workout.notion_page_id.present?
        @client.update_page(workout.notion_page_id, properties: actuals(workout))
        record_day_type(linked_notion_type(workout) || fallback_day_type(workout))
        return
      end

      # 1. Claim a Planned/Modified row of compatible type
      candidate = claim_candidate(workout)
      if candidate
        @client.update_page(candidate["id"],
          properties: actuals(workout).merge("Status" => Properties.select("Done")))
        workout.update!(notion_page_id: candidate["id"])
        record_day_type(DAY_TYPE_FOR_NOTION_TYPE[Properties.read_select(candidate["properties"]["Type"])])
        @newly_synced << workout.id
        return
      end

      # 2. Adopt an already-Done row of compatible type (no Status write, no newly_synced)
      done_candidate = claim_done_candidate(workout)
      if done_candidate
        @client.update_page(done_candidate["id"], properties: actuals(workout))
        workout.update!(notion_page_id: done_candidate["id"])
        record_day_type(DAY_TYPE_FOR_NOTION_TYPE[Properties.read_select(done_candidate["properties"]["Type"])])
        return
      end

      # 3. Create an unplanned row — only if the workout type is mapped
      notion_type = fallback_notion_type(workout)
      return unless notion_type

      response = @client.create_page(data_source_id: ds_id, properties: unplanned_properties(workout))
      workout.update!(notion_page_id: response["id"])
      record_day_type(fallback_day_type(workout))
      @newly_synced << workout.id
    end

    def all_candidates
      @all_candidates ||= @client.query_data_source(ds_id,
        filter: {"property" => "Date", "date" => {"equals" => @date.iso8601}})
    end

    def candidates
      @candidates ||= all_candidates
        .select { |row| %w[Planned Modified].include?(Properties.read_select(row["properties"]["Status"])) }
    end

    def claim_candidate(workout)
      types = compatible_notion_types(workout.workout_type)
      match = candidates.find { |row| types.include?(Properties.read_select(row["properties"]["Type"])) }
      candidates.delete(match) if match
      all_candidates.delete(match) if match
      match
    end

    def claim_done_candidate(workout)
      types = compatible_notion_types(workout.workout_type)
      match = all_candidates.find do |row|
        Properties.read_select(row["properties"]["Status"]) == "Done" &&
          types.include?(Properties.read_select(row["properties"]["Type"]))
      end
      all_candidates.delete(match) if match
      match
    end

    def compatible_notion_types(workout_type)
      case workout_type
      when /\brun\b|running/i then RUN_NOTION_TYPES
      when /strength/i then ["Strength"]
      when /golf/i then ["Golf"]
      when /cycling|swim|elliptical|rowing|rower/i then ["Cross"]
      else []
      end
    end

    def actuals(workout)
      props = {}
      km = distance_km(workout)
      props["Actual Distance (km)"] = Properties.number(km.round(2)) if km
      props["Actual Duration (min)"] = Properties.number((workout.duration / 60.0).round(1))
      avg_hr = workout.metadata&.dig("heartRate", "avg")
      props["Actual Avg HR"] = Properties.number(avg_hr.round) if avg_hr
      props["Actual Avg Pace"] = Properties.rich_text(pace(workout, km)) if km&.positive?
      props["kCal Burned"] = Properties.number(workout.energy_burned.round) if workout.energy_burned
      props
    end

    def distance_km(workout)
      return nil unless workout.distance
      case workout.distance_units
      when "mi" then workout.distance.to_f * MI_TO_KM
      when "m" then workout.distance.to_f / 1000
      else workout.distance.to_f
      end
    end

    def pace(workout, km)
      total_seconds = (workout.duration / km).round
      format("%d:%02d/km", total_seconds / 60, total_seconds % 60)
    end

    def unplanned_properties(workout)
      week = TrainingWeek.new(@date)
      type = fallback_notion_type(workout)
      props = actuals(workout)
      props["Session"] = Properties.title("W#{week.week_number} #{@date.strftime("%a")} - #{workout.workout_type} (unplanned)")
      props["Date"] = Properties.date(@date)
      props["Status"] = Properties.select("Done")
      props["Week"] = Properties.number(week.week_number)
      props["Type"] = Properties.select(type) if type
      props
    end

    def fallback_notion_type(workout)
      case workout.workout_type
      when /\brun\b|running/i then "Easy"
      when /strength/i then "Strength"
      when /golf/i then "Golf"
      when /cycling|swim|elliptical|rowing|rower/i then "Cross"
      end
    end

    def fallback_day_type(workout)
      DAY_TYPE_FOR_NOTION_TYPE[fallback_notion_type(workout)]
    end

    def linked_notion_type(_workout) = nil # linked pages aren't re-fetched; day type falls back

    def record_day_type(day_type)
      @day_types << day_type if day_type
    end

    def top_day_type
      @day_types.max_by { |t| DailyLogSync::DAY_TYPE_RANK.index(t) || -1 }
    end
  end
end
