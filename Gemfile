source "https://rubygems.org"

gem "rails", "~> 7.2.3"
gem "dotenv-rails", "~> 3.0"
gem "sqlite3", ">= 1.4"        # local / Docker dev
gem "pg", "~> 1.1"             # Heroku production (DATABASE_URL)
gem "puma", ">= 5.0"
gem "rack-cors"
gem "redis", ">= 4.0.1"       # ActionCable (production) + Sidekiq
gem "sidekiq", "~> 7.0"       # background jobs (production)
gem "playwright-ruby-client", "~> 1.49"  # Playwright Ruby binding

gem "tzinfo-data", platforms: %i[ mswin mswin64 mingw x64_mingw jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri mswin mswin64 mingw x64_mingw ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end
