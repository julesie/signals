class NutritionProfilesController < ApplicationController
  def edit
    @nutrition_profile = current_user.nutrition_profile || current_user.create_nutrition_profile
  end

  def update
    @nutrition_profile = current_user.nutrition_profile || current_user.create_nutrition_profile

    if @nutrition_profile.update(nutrition_profile_params)
      redirect_to food_logs_path, notice: "Nutrition targets updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def nutrition_profile_params
    params.require(:nutrition_profile).permit(:calorie_target, :protein_target)
  end
end
