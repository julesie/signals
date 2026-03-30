class FoodEstimationJob < ApplicationJob
  def perform(food_log_id)
    food_log = FoodLog.find(food_log_id)
    food = food_log.food

    result = FoodEstimationService.call(food.description)

    if result.success
      macros = result.macros.symbolize_keys
      food.update!(macros)
      food_log.update!(estimated: true, **macros)
    else
      Rails.logger.error("FoodEstimationJob failed for FoodLog##{food_log_id}: #{result.error}")
      food_log.update!(estimated: true)
    end
  end
end
