allowed_origins = [
  'http://localhost:5173',
  'http://localhost:3001',
  /\Ahttps?:\/\/.*\.vercel\.app\z/,
]
allowed_origins << ENV['FRONTEND_URL'] if ENV['FRONTEND_URL'].present?

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      expose: ['Content-Type']
  end
end
