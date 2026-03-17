ARG RUBY_VERSION=3.1.2
FROM ruby:$RUBY_VERSION-slim

WORKDIR /rails

# System packages (Ruby build + PostgreSQL + SQLite + Chromium deps)
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    libsqlite3-dev \
    libyaml-dev \
    pkg-config \
    curl \
    git \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libdbus-1-3 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 libpangocairo-1.0-0 \
    libx11-xcb1 libxcb-dri3-0 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 (required by playwright-ruby-client)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install --no-install-recommends -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Ruby gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Playwright npm package (playwright-ruby-client needs it as a server)
COPY package.json ./
RUN npm install

# Install Chromium browser via Playwright
RUN npx playwright install chromium --with-deps 2>/dev/null || true

# Application code
COPY . .

# Heroku: PORT env var を使う（heroku container では $PORT が動的に割り当てられる）
# DB migrate は起動時に行う（heroku release phase または手動 heroku run rails db:migrate）
EXPOSE 3000
CMD bundle exec rails db:migrate RAILS_ENV=production 2>/dev/null; \
    bundle exec rails server -b 0.0.0.0 -p ${PORT:-3000}
