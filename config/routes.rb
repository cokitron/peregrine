Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :workflows, only: %i[index new create show update destroy] do
    post :execute, on: :member
    resources :runs, controller: "workflow_runs", only: %i[index show] do
      post :stop, on: :member
    end
  end

  resources :agents, only: %i[index create show update destroy]

  root to: redirect("/workflows")
end
