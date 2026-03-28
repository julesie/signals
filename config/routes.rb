Rails.application.routes.draw do
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?

  devise_for :users

  namespace :api do
    namespace :v1 do
      resource :health_data, only: [:create], controller: "health_data"
    end
  end

  get "up" => "rails/health#show", :as => :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", :as => :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", :as => :pwa_manifest

  root "dashboard#index"
end
