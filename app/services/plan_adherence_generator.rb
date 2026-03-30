class PlanAdherenceGenerator
  Result = Struct.new(:success, :summary, :error, keyword_init: true)

  DEFAULT_MODEL = "gpt-5-nano"

  SYSTEM_PROMPT = <<~PROMPT
    You are a concise fitness coach. Given the user's training plan and their actual activity, provide a brief adherence assessment.

    Write exactly two short paragraphs:
    1. **Last 7 days:** How they tracked against their plan this week.
    2. **Last 30 days:** The broader trend — are they building consistency or drifting?

    Be specific about what they did and didn't do relative to the plan. Encouraging but honest. No fluff.
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
      adherence_summary: response.content,
      adherence_summary_generated_at: Time.current
    )

    Result.new(success: true, summary: response.content)
  rescue => e
    Rails.logger.error("PlanAdherenceGenerator failed: #{e.class}: #{e.message}")
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
      #{format_workouts(7.days.ago)}

      ## Last 30 Days — Workouts
      #{format_workouts(30.days.ago)}

      ## Last 7 Days — Active Energy
      #{format_active_energy}

      ## Today
      #{Date.current.strftime("%A, %B %-d, %Y")}
    CONTEXT
  end

  def format_workouts(since)
    workouts = @plan.user.workouts.where(started_at: since..).order(started_at: :asc)
    return "No workouts recorded." if workouts.empty?

    workouts.map { |w|
      parts = [w.started_at.strftime("%a %b %-d")]
      parts << w.workout_type
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      line = "- #{parts.join(", ")}"
      line << " — \"#{w.notes}\"" if w.notes.present?
      line
    }.join("\n")
  end

  def format_active_energy
    metrics = @plan.user.health_metrics.where(metric_name: "active_energy", recorded_at: 7.days.ago..)
    return "No active energy data." if metrics.empty?

    daily = metrics.group_by { |m| m.recorded_at.to_date }.transform_values { |ms| ms.sum(&:value) }
    daily.sort.map { |date, total| "- #{date.strftime("%a %b %-d")}: #{total.round} kcal" }.join("\n")
  end
end
