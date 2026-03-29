class PlanChatService
  Result = Struct.new(:success, :response, :error, keyword_init: true)

  DEFAULT_MODEL = "gpt-5-nano"

  SYSTEM_PROMPT = <<~PROMPT
    You are a fitness coach helping the user build and refine their training plan. The user will give you their current plan and a request to modify it.

    Respond with EXACTLY two sections separated by "---":

    1. The complete updated plan (plain text or markdown)
    2. A brief explanation of what you changed and why

    If the user's request doesn't make sense or conflicts with good training principles, explain why in the second section and suggest an alternative, but still make the requested change if possible.

    If there is no existing plan, create one from scratch based on the user's request.
  PROMPT

  def self.call(plan, message)
    new(plan, message).call
  end

  def initialize(plan, message)
    @plan = plan
    @message = message
  end

  def call
    prompt = build_prompt
    response = RubyLLM.chat(model: llm_model)
      .with_instructions(SYSTEM_PROMPT)
      .ask(prompt)

    updated_content, explanation = parse_response(response.content)

    @plan.update!(content: updated_content)

    Result.new(success: true, response: explanation)
  rescue => e
    Rails.logger.error("PlanChatService failed: #{e.class}: #{e.message}")
    Result.new(success: false, error: e.message)
  end

  private

  def llm_model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  def build_prompt
    if @plan.has_content?
      <<~PROMPT
        ## Current Plan
        #{@plan.content}

        ## User Request
        #{@message}
      PROMPT
    else
      <<~PROMPT
        ## Current Plan
        (No plan yet — create one from scratch)

        ## User Request
        #{@message}
      PROMPT
    end
  end

  def parse_response(content)
    parts = content.split("---", 2)
    if parts.length == 2
      [parts[0].strip, parts[1].strip]
    else
      [content.strip, "Plan updated."]
    end
  end
end
