class FoodEstimationService
  Result = Struct.new(:success, :macros, :error, keyword_init: true)

  DEFAULT_MODEL = "gpt-5-nano"

  SYSTEM_PROMPT = <<~PROMPT
    You are a nutrition estimation engine. The user will describe a food or meal they ate.
    Estimate the macronutrient content and return ONLY valid JSON with these exact keys:

    {"kcal": number, "protein": number, "carbs": number, "fat": number, "fibre": number, "alcohol": number}

    All values in grams except kcal (which is kilocalories).
    If the user does not specify a portion size, assume a typical single serving.
    Never ask clarifying questions. Always return your best estimate.
    Return ONLY the JSON object, no other text.
  PROMPT

  def self.call(description)
    new(description).call
  end

  def initialize(description)
    @description = description
  end

  def call
    response = RubyLLM.chat(model: llm_model)
      .with_instructions(SYSTEM_PROMPT)
      .ask(@description)

    macros = parse_response(response.content)

    Result.new(success: true, macros: macros)
  rescue => e
    Rails.logger.error("FoodEstimationService failed: #{e.class}: #{e.message}")
    Result.new(success: false, error: e.message)
  end

  private

  def llm_model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  def parse_response(content)
    json = content.strip
    json = json.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")
    parsed = JSON.parse(json)

    required_keys = %w[kcal protein carbs fat fibre alcohol]
    missing = required_keys - parsed.keys
    raise "Missing keys in LLM response: #{missing.join(", ")}" if missing.any?

    parsed.slice(*required_keys).transform_values(&:to_f)
  end
end
