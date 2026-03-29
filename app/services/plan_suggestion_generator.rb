class PlanSuggestionGenerator
  Result = Struct.new(:success, :suggestion, :error, keyword_init: true)

  DEFAULT_MODEL = "gpt-5-nano"

  SYSTEM_PROMPT = <<~PROMPT
    You are a concise fitness coach. Given the user's training plan, their activity over the last 7 days, and any workouts already completed today, tell them what to do for the rest of TODAY. Nothing else — no planning ahead.

    If they've already worked out today, acknowledge it and suggest complementary activity or rest — don't suggest an additional full workout.

    One short paragraph: what to do today and a brief reason why. That's it.
  PROMPT

  def self.call(plan)
    new(plan).call
  end

  def initialize(plan)
    @plan = plan
  end

  def call
    context = build_context
    response = RubyLLM.chat(model: llm_model)
      .with_params(reasoning_effort: "low")
      .with_instructions(SYSTEM_PROMPT)
      .ask(context)

    @plan.update!(
      daily_suggestion: response.content,
      suggestion_generated_at: Time.current
    )

    Result.new(success: true, suggestion: response.content)
  rescue => e
    Rails.logger.error("PlanSuggestionGenerator failed: #{e.class}: #{e.message}")
    Result.new(success: false, error: e.message)
  end

  private

  def llm_model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  def build_context
    <<~CONTEXT
      ## Your Plan
      #{@plan.content}

      ## Last 7 Days — Workouts
      #{format_workouts}

      ## Last 7 Days — Health Metrics
      #{format_metrics}

      ## Today's Completed Workouts
      #{format_todays_workouts}

      ## Today
      #{Date.current.strftime("%A, %B %-d, %Y")}
    CONTEXT
  end

  def format_workouts
    workouts = Workout.where(started_at: 7.days.ago..).order(started_at: :asc)
    return "No workouts recorded." if workouts.empty?

    workouts.map { |w|
      parts = [w.started_at.strftime("%a %b %-d")]
      parts << w.workout_type
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.distance} #{w.distance_units}" if w.distance.present?
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      line = "- #{parts.join(", ")}"
      line << " — \"#{w.notes}\"" if w.notes.present?
      line
    }.join("\n")
  end

  def format_todays_workouts
    workouts = Workout.where(started_at: Date.current.all_day).order(started_at: :asc)
    return "No workouts completed yet today." if workouts.empty?

    workouts.map { |w|
      parts = [w.workout_type]
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      line = "- #{parts.join(", ")}"
      line << " — \"#{w.notes}\"" if w.notes.present?
      line
    }.join("\n")
  end

  def format_metrics
    metrics = HealthMetric.where(recorded_at: 7.days.ago..)
    return "No metrics recorded." if metrics.empty?

    summary = []

    steps = metrics.where(metric_name: "steps").order(recorded_at: :desc)
    if steps.any?
      avg = steps.average(:value).round
      summary << "- Steps: avg #{avg.to_fs(:delimited)}/day"
    end

    active_energy = metrics.where(metric_name: "active_energy").order(recorded_at: :desc)
    if active_energy.any?
      avg = active_energy.average(:value).round
      summary << "- Active energy: avg #{avg} kcal/day"
    end

    sleep = metrics.where(metric_name: "sleep_analysis").order(recorded_at: :desc)
    if sleep.any?
      avg = sleep.average(:value).round(1)
      summary << "- Sleep: avg #{avg} hrs/night"
    end

    rhr = metrics.where(metric_name: "resting_heart_rate").order(recorded_at: :desc).first
    summary << "- Resting HR: #{rhr.value.round} bpm" if rhr

    hrv = metrics.where(metric_name: "heart_rate_variability").order(recorded_at: :desc).first
    summary << "- HRV: #{hrv.value.round} ms" if hrv

    summary.empty? ? "No relevant metrics." : summary.join("\n")
  end
end
