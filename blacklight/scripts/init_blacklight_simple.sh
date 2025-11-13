#!/usr/bin/env bash
set -e

echo "Initializing Blacklight application..."

if [ ! -f /app/.initialized ]; then
  echo "Creating fresh Rails app..."
  cd /app
  
  cat > Gemfile << 'GEMFILE'
source "https://rubygems.org"
gem "rails", "~> 7.2.3"
gem "puma", "~> 7.0"
gem "blacklight", "~> 8.0"
gem "rsolr", "~> 2.0"
gem "sqlite3", "~> 1.4"
GEMFILE

  bundle install --jobs=4 2>&1 | tail -2
  mkdir -p app/controllers app/views/catalog app/views/layouts config/initializers tmp/pids log

  cat > Rakefile << 'EOF'
require_relative "config/application"
Rails.application.load_tasks
EOF

  cat > config.ru << 'EOF'
require_relative "config/environment"
run Rails.application
EOF

  cat > config/application.rb << 'EOF'
require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)
module BdsaBl
  class Application < Rails::Application
    config.load_defaults 7.2
    config.autoload_lib(ignore: %w(tasks generators))
  end
end
EOF

  cat > config/boot.rb << 'EOF'
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
require "bundler/setup"
EOF

  cat > config/environment.rb << 'EOF'
require_relative "application"
Rails.application.initialize!
EOF

  mkdir -p bin
  cat > bin/rails << 'EOF'
#!/usr/bin/env ruby
APP_PATH = File.expand_path("../config/application", __dir__)
require_relative "../config/boot"
require "rails/commands"
EOF
  chmod +x bin/rails

  cat > config/database.yml << 'EOF'
default: &default
  adapter: sqlite3
  pool: 5
  timeout: 5000
development:
  <<: *default
  database: db/development.sqlite3
test:
  <<: *default
  database: db/test.sqlite3
EOF

  cat > app/controllers/application_controller.rb << 'EOF'
class ApplicationController < ActionController::Base
  include Blacklight::Controller
end
EOF

  cat > app/controllers/catalog_controller.rb << 'EOF'
class CatalogController < ApplicationController
  include Blacklight::Catalog

  configure_blacklight do |config|
    config.default_solr_params = {
      rows: 12,
      q: "*:*",
      facet: true,
      "facet.field" => ["np_regionName", "np_stainID", "np_caseID", "np_blockID"],
      "facet.mincount" => 1,
      "facet.limit" => 20
    }
    config.index.thumbnail_field = "thumbnail_url"
    config.show.thumbnail_field = "thumbnail_url"
    config.index.title_field = "name"
    config.show.title_field = "name"
    config.add_facet_field "np_regionName", label: "Region Name", limit: 20, collapse: false
    config.add_facet_field "np_stainID", label: "Stain", limit: 20, collapse: false
    config.add_facet_field "np_caseID", label: "Case ID", limit: 20, collapse: false
    config.add_facet_field "np_blockID", label: "Block ID", limit: 20, collapse: false
    %w[name np_regionName np_stainID np_caseID np_blockID metadata updated].each do |f|
      config.add_index_field f, label: f.titleize
    end
    %w[name np_regionName np_stainID np_caseID np_blockID metadata created updated].each do |f|
      config.add_show_field f, label: f.titleize
    end
  end
end
EOF

  cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do
  get "up" => "rails/health#show"
  root "catalog#index"
  concern :searchable, Blacklight::Routes::Searchable.new
  resource :catalog, only: [:index], path: '/catalog', controller: 'catalog' do
    concerns :searchable
  end
  concern :exportable, Blacklight::Routes::Exportable.new
  resources :solr_documents, only: [:show], path: '/catalog', controller: 'catalog' do
    concerns :exportable
  end
end
EOF

  cat > app/views/layouts/application.html.erb << 'EOF'
<!DOCTYPE html>
<html>
  <head><title>Gallery</title><meta charset="utf-8" /></head>
  <body><%= yield %></body>
</html>
EOF

  cat > config/initializers/allowed_hosts.rb << 'EOF'
Rails.application.config.hosts.clear
EOF

  cat > config/initializers/blacklight_config.rb << 'EOF'
Rails.configuration.solr_path = 'select'
Rails.configuration.solr = { url: ENV['SOLR_URL'] || 'http://solr:8983/solr/bdsa' }
EOF

  bundle exec rails db:prepare
  touch /app/.initialized
  echo "Rails app initialized!"
fi

cd /app
exec bundle exec rails server -b 0.0.0.0 -p 3000
