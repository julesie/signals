class PlansController < ApplicationController
  before_action :set_plan

  def show
  end

  def edit
  end

  def update
    if @plan.update(plan_params)
      redirect_to plan_path, notice: "Plan updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def generate_suggestion
    result = PlanSuggestionGenerator.call(@plan)

    if result.success
      redirect_back fallback_location: plan_path, notice: "Suggestion updated."
    else
      redirect_back fallback_location: plan_path, alert: "Couldn't generate a suggestion — try again later."
    end
  end

  def chat
    message = params[:message]

    if message.blank?
      redirect_to plan_path, alert: "Please enter a message."
      return
    end

    result = PlanChatService.call(@plan, message)

    if result.success
      redirect_to plan_path, notice: result.response
    else
      redirect_to plan_path, alert: "Couldn't process your request — try again later."
    end
  end

  private

  def set_plan
    @plan = current_user.plan || current_user.create_plan
  end

  def plan_params
    params.require(:plan).permit(:content)
  end
end
