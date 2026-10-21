Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]

  resources :quizzes do
    get :template, on: :collection
    get :export, on: :member
  end
  resources :departments, except: :show
  resources :vacancies
  resources :employees, except: :show do
    collection do
      get :template
      get :export
      post :import
    end
  end
  resources :exam_batches, path: "batches", only: %i[index new create show edit update destroy] do
    get :template, on: :collection
    member do
      get :monitor
      get :links
    end
  end
  get "monitor" => "monitor#index", as: :live_monitor
  resources :results, only: :index do
    get :export, on: :collection
  end
  resources :invitations, only: %i[index new create show edit update destroy] do
    get :export, on: :collection
    member do
      get :report
      get :export, action: :export_one
      post :decide
    end
    resources :interview_rounds, path: "rounds", only: %i[create update destroy] do
      member do
        get :room
        post :open
        post :complete
        post :feedback
      end
    end
  end
  get "pipeline" => "pipeline#index", as: :pipeline
  get "schedule" => "schedule#index", as: :schedule
  get "guide" => "pages#guide", as: :guide
  get "candidate-guide" => "pages#candidate_guide", as: :candidate_guide
  get "team" => "team#index", as: :team
  post "team" => "team#create"
  delete "team/:id" => "team#destroy", as: :team_member

  # Read-only live view for interview panelists (no login, secret link)
  get "watch/batch/:watch_token" => "watch#batch", as: :watch_batch
  get "watch/:watch_token" => "watch#show", as: :watch
  get "watch/:watch_token/rounds/:round_id" => "watch#round", as: :watch_round
  post "watch/:watch_token/rounds/:round_id/feedback" => "watch#feedback", as: :watch_feedback

  # Public candidate flow, addressed by the shared link token
  scope "exam/:token", controller: :exams, as: :exam do
    get "/", action: :show
    post :request_otp
    post :verify_otp
    get :instructions
    post :start
    get :take
    patch :answer
    post :events
    post :recordings
    post :submit
    get :finished
    get :interview
  end

  get "up" => "rails/health#show", as: :rails_health_check
  root "dashboard#index"
end
