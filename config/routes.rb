Rails.application.routes.draw do
  devise_for :users

  namespace :api do
    namespace :v1 do
      resource :health_data, only: [:create], controller: "health_data"
    end
  end

  get "up" => "rails/health#show", :as => :rails_health_check
  root "dashboard#index"
end
