class FoodLogsController < ApplicationController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    @food_logs = current_user.food_logs
      .on_date(@date)
      .includes(:food)
      .chronological
    @nutrition_profile = current_user.nutrition_profile || current_user.create_nutrition_profile
    @grouped_logs = @food_logs.group_by(&:mealtime)
  end

  def new
    @mealtime = params[:mealtime].presence_in(FoodLog::MEALTIMES) || FoodLog.default_mealtime
    @prefill = params[:prefill]
    @recent = recent_foods(@mealtime)
    @frequent = frequent_foods(@mealtime)
  end

  def quick_add_lists
    @mealtime = params[:mealtime].presence_in(FoodLog::MEALTIMES) || FoodLog.default_mealtime
    @recent = recent_foods(@mealtime)
    @frequent = frequent_foods(@mealtime)
    render partial: "food_logs/quick_add_lists"
  end

  def create
    food = current_user.foods.create!(
      description: params[:description],
      kcal: 0, protein: 0, carbs: 0, fat: 0, fibre: 0, alcohol: 0
    )

    log = current_user.food_logs.create!(
      food: food,
      consumed_at: build_consumed_at,
      mealtime: params[:mealtime],
      estimated: false,
      kcal: 0, protein: 0, carbs: 0, fat: 0, fibre: 0, alcohol: 0
    )

    FoodEstimationJob.perform_later(log.id)

    redirect_to food_logs_path(date: log.consumed_at.to_date), notice: "#{food.description} logged — estimating macros..."
  end

  def quick_add
    food = current_user.foods.find(params[:food_id])

    log = current_user.food_logs.new(
      food: food,
      consumed_at: Time.current,
      mealtime: FoodLog.default_mealtime
    )
    log.stamp_macros_from_food!
    log.save!

    redirect_to food_logs_path(date: log.consumed_at.to_date), notice: "#{food.description} logged."
  end

  def edit
    @food_log = current_user.food_logs.find(params[:id])
  end

  def update
    @food_log = current_user.food_logs.find(params[:id])
    food = @food_log.food

    log_attrs = food_log_params
    macro_attrs = log_attrs.extract!(:kcal, :protein, :carbs, :fat, :fibre, :alcohol)

    if log_attrs.key?(:consumed_at_hour)
      hour = log_attrs.delete(:consumed_at_hour).to_i
      log_attrs[:consumed_at] = @food_log.consumed_at.change(hour: hour)
    end

    if @food_log.update(log_attrs.merge(macro_attrs)) && food.update(macro_attrs)
      redirect_to food_logs_path(date: @food_log.consumed_at.to_date), notice: "Entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    food_log = current_user.food_logs.find(params[:id])
    date = food_log.consumed_at.to_date
    food_log.destroy
    redirect_to food_logs_path(date: date), notice: "Entry deleted."
  end

  private

  def build_consumed_at
    hour = (params[:consumed_at_hour] || Time.current.hour).to_i
    Time.current.change(hour: hour)
  end

  def food_log_params
    params.require(:food_log).permit(:mealtime, :consumed_at_hour, :kcal, :protein, :carbs, :fat, :fibre, :alcohol)
  end

  def recent_foods(mealtime)
    current_user.food_logs
      .by_mealtime(mealtime)
      .includes(:food)
      .order(consumed_at: :desc)
      .limit(5)
      .map(&:food)
      .uniq(&:id)
  end

  def frequent_foods(mealtime)
    food_ids = current_user.food_logs
      .by_mealtime(mealtime)
      .group(:food_id)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(5)
      .pluck(:food_id)

    current_user.foods.where(id: food_ids).index_by(&:id).values_at(*food_ids).compact
  end
end
