Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  namespace :api do
    # テキスト CRUD
    get    "texts/:type",     to: "texts#index"
    post   "texts/:type",     to: "texts#create"
    put    "texts/:type/:id", to: "texts#update"
    delete "texts/:type/:id", to: "texts#destroy"

    # フォルダ CRUD
    get    "folders/:type", to: "folders#index"
    post   "folders/:type", to: "folders#create"
    put    "folders/:type", to: "folders#update"
    delete "folders/:type", to: "folders#destroy"

    # 投稿（ActionCable + Sidekiq バックグラウンドジョブ）
    post "post", to: "post#create"

    # AI
    post "ai/correct",        to: "ai#correct"
    post "ai/generate",       to: "ai#generate"
    post "ai/align-datetime", to: "ai#align_datetime"
    post "ai/agent",          to: "ai#agent"
  end
end
