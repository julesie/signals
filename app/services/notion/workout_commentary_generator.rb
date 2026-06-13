module Notion
  class WorkoutCommentaryGenerator
    Result = Struct.new(:success, :commentary, :error, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT
      You are a concise running coach reviewing a single completed workout for an athlete
      training for the SF Half Marathon. Given the workout's actual numbers, the training
      plan, and the recent week of training, write 2-4 sentences of commentary: how the
      session went relative to its purpose, anything notable (pace, HR, fatigue signals),
      and what it means for the next few days. No headers, no bullet points.
    PROMPT

    def self.call(workout, client: Client.new)
      new(workout, client: client).call
    end

    def initialize(workout, client:)
      @workout = workout
      @client = client
    end

    def call
      return Result.new(success: false, error: "workout has no notion_page_id") if @workout.notion_page_id.blank?

      response = RubyLLM.chat(model: ENV.fetch("LLM_MODEL", "gpt-5-nano"))
        .with_params(reasoning_effort: "medium")
        .with_instructions(SYSTEM_PROMPT)
        .ask(build_context)

      @client.append_blocks(@workout.notion_page_id,
        children: [Properties.paragraph_block("🤖 Coach: #{response.content}")])
      Result.new(success: true, commentary: response.content)
    rescue => e
      Rails.logger.error("Notion::WorkoutCommentaryGenerator failed for Workout##{@workout.id}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def build_context
      user = @workout.user
      plan = user.plan
      recent = user.workouts.where(started_at: 7.days.ago..).where.not(id: @workout.id).order(:started_at)

      <<~CONTEXT
        ## This Workout
        #{format_workout(@workout)}

        ## Training Plan
        #{plan&.content || "No plan on file."}

        ## Last 7 Days
        #{recent.map { |w| format_workout(w) }.presence&.join("\n") || "No other workouts."}
      CONTEXT
    end

    def format_workout(w)
      parts = ["#{w.started_at.in_time_zone(TrainingWeek::TIME_ZONE).strftime("%a %b %-d")}: #{w.workout_type}"]
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.distance} #{w.distance_units}" if w.distance.present?
      parts << "avg HR #{w.metadata.dig("heartRate", "avg").round}" if w.metadata&.dig("heartRate", "avg")
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      parts.join(", ")
    end
  end
end
