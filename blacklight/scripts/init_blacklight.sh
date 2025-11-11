#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bundle/bin:${PATH}"

APP_DIR=/app/bdsa-bl
INSTALL_MARKER="$APP_DIR/tmp/.blacklight_installed"
DEFAULT_HOSTS="einstein.neurology.emory.edu,einstein.neurology.emory.edu:3001,localhost,localhost:3000,blacklight,blacklight:3000"
: "${RAILS_ADDITIONAL_HOSTS:=${DEFAULT_HOSTS}}"
: "${SOLR_URL:=http://solr:8983/solr/bdsa}"
: "${RAILS_ENV:=development}"
MODE="${BLACKLIGHT_MODE:-run}"

bootstrap_app() {
  echo "Bootstrapping Blacklight source tree..."
  rm -rf "$APP_DIR"
  gem install bundler -v "~>2"
  gem install rails -v "~>7.1"
  rails new "$APP_DIR"
  cd "$APP_DIR"
  mkdir -p tmp

  # Stable gems for predictable builds.
  grep -q "gem 'blacklight'" Gemfile     || echo "gem 'blacklight', '~> 8.12'"    >> Gemfile
  grep -q "gem 'view_component'" Gemfile || echo "gem 'view_component', '~> 3.12'" >> Gemfile
  bundle install

  bundle exec rails g blacklight:install
  bundle exec rails db:prepare
  touch "$INSTALL_MARKER"
}

ensure_hosts() {
  ruby <<'RUBY'
hosts = ENV.fetch('RAILS_ADDITIONAL_HOSTS','').split(',').map(&:strip).reject(&:empty?)
%w[config/environments/development.rb config/environments/production.rb config/environments/test.rb].each do |f|
  next unless File.exist?(f)
  s = File.read(f)
  next unless s.include?("Rails.application.configure do")
  hosts.each do |h|
    line = %(  config.hosts << "#{h}")
    unless s.include?(line)
      s = s.sub("Rails.application.configure do\n","Rails.application.configure do\n#{line}\n")
    end
  end
  File.write(f, s)
end
RUBY
}

render_catalog_overrides() {
  # homepage → catalog#index
  rm -f public/index.html || true
  ruby -i -pe 'sub(/^root .*/, "root to: \"catalog#index\"") unless $_.match?(/^root /)' config/routes.rb
  ruby <<'RUBY'
routes = File.read('config/routes.rb')
unless routes.include?('thumbnails#show')
  routes.sub!("Rails.application.routes.draw do", "Rails.application.routes.draw do\n  get \"thumbnails/:id\", to: \"thumbnails#show\", as: :thumbnail\n")
  File.write('config/routes.rb', routes)
end
RUBY

cat > app/controllers/catalog_controller.rb <<'RUBY'
# frozen_string_literal: true
class CatalogController < ApplicationController
  include Blacklight::Catalog
  before_action :ensure_query, only: :index

  configure_blacklight do |config|
    config.solr_path = 'advanced'
    config.connection_config[:request_handler] = 'advanced'
    config.index.thumbnail_field = 'thumbnail_url'
    config.show.thumbnail_field = 'thumbnail_url'
    config.default_solr_params = { rows: 60, q: "*:*" }
    config.index.title_field = 'name'
    config.show.title_field  = 'name'
    %w[metadata bad_imageno np_blockID np_caseID np_regionName np_stainID].each { |f| config.add_facet_field f, label: f.titleize, limit: true }
    config.add_facet_fields_to_solr_request!
    %w[metadata bad_imageno np_blockID np_caseID np_regionName np_stainID updated created].each do |f|
      config.add_index_field f, label: f.titleize
      config.add_show_field  f, label: f.titleize
    end
    config.add_sort_field 'relevance', sort: 'score desc, updated desc', label: 'Relevance', default: true
    config.add_sort_field 'updated',   sort: 'updated desc',             label: 'Updated'
    config.add_search_field 'all_fields' do |field|
      field.label = 'All Fields'
      field.solr_parameters = { qf: 'name metadata np_regionName np_stainID np_caseID np_blockID text', pf: 'name' }
    end
    config.default_search_field = config.search_fields['all_fields']
  end

  private

  def ensure_query
    params[:q] = '*:*' if params[:q].blank?
  end
end
RUBY

cat > app/controllers/thumbnails_controller.rb <<'RUBY'
# frozen_string_literal: true
require 'net/http'
class ThumbnailsController < ApplicationController
  DSA_BASE = ENV.fetch('DSA_BASE_URL', 'http://bdsa.pathology.emory.edu:8080/api/v1').chomp('/')

  def show
    item_id = params[:id]
    width = params[:width] || '384'
    height = params[:height] || '384'
    uri = URI("#{DSA_BASE}/item/#{item_id}/tiles/thumbnail?width=#{width}&height=#{height}")
    request = Net::HTTP::Get.new(uri)
    token = ENV['BDSA_API_KEY']
    request['Girder-Token'] = token if token.present?
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      resp = http.request(request)
      if resp.is_a?(Net::HTTPSuccess)
        send_data resp.body, type: resp['content-type'] || 'image/jpeg', disposition: 'inline'
      else
        head resp.code.to_i
      end
    end
  rescue StandardError => e
    Rails.logger.error("Thumbnail proxy error: #{e.message}")
    head :bad_gateway
  end
end
RUBY

  mkdir -p app/views/catalog
cat > app/views/catalog/_index_default.html.erb <<'ERB'
<% doc = document %>
<% item_id  = Array(doc['item_id']).first || doc['item_id'] %>
<% name     = Array(doc['name']).first || doc['name'] %>
<% block    = Array(doc['np_blockID']).first || doc['np_blockID'] %>
<% case_id  = Array(doc['np_caseID']).first || doc['np_caseID'] %>
<% region   = Array(doc['np_regionName']).first || doc['np_regionName'] %>
<% stain    = Array(doc['np_stainID']).first || doc['np_stainID'] %>
<% updated  = Array(doc['updated']).first || doc['updated'] %>
<% created  = Array(doc['created']).first || doc['created'] %>
<% thumb_url = thumbnail_path(item_id, width: 384, height: 384) %>

<div class="bl-result-entry" style="display:flex;gap:20px;align-items:flex-start;padding:16px;border:1px solid #e3e3e3;border-radius:10px;margin-bottom:18px;background:#fff;">
  <div style="flex:1 1 auto;">
    <div style="font-size:1.1rem;font-weight:600;margin-bottom:10px;">
      <%= link_to name, catalog_path(doc), style: "text-decoration:none;" %>
    </div>
    <dl style="margin:0;display:grid;grid-template-columns:max-content 1fr;gap:4px 12px;font-size:0.95rem;">
      <% if block %>
        <dt>Np Block:</dt><dd><%= block %></dd>
      <% end %>
      <% if case_id %>
        <dt>Np Case:</dt><dd><%= case_id %></dd>
      <% end %>
      <% if region %>
        <dt>Np Region Name:</dt><dd><%= region %></dd>
      <% end %>
      <% if stain %>
        <dt>Np Stain:</dt><dd><%= stain %></dd>
      <% end %>
      <% if updated %>
        <dt>Updated:</dt><dd><%= updated %></dd>
      <% end %>
      <% if created %>
        <dt>Created:</dt><dd><%= created %></dd>
      <% end %>
    </dl>
  </div>
  <% if thumb_url.present? %>
    <div style="flex:0 0 200px;text-align:center;">
      <img src="<%= thumb_url %>" alt="<%= h(name) %>"
           loading="lazy"
           style="width:180px;height:180px;object-fit:cover;border-radius:10px;border:1px solid #ddd;background:#f8f8f8"/>
    </div>
  <% end %>
</div>
ERB

cat > app/views/catalog/_show_default.html.erb <<'ERB'
<% item_id = Array(@document['item_id']).first || @document['item_id'] %>
<% name    = Array(@document['name']).first || @document['name'] %>
<% thumb   = thumbnail_path(item_id, width: 768, height: 768) %>
<h2><%= name %></h2>
<% if thumb.present? %>
  <p><img src="<%= thumb %>" alt="<%= h(name) %>" style="max-width:100%;height:auto;border-radius:8px"/></p>
<% end %>
<div style="margin-top:1rem">
  <% @document.to_h.slice('metadata','bad_imageno','np_blockID','np_caseID','np_regionName','np_stainID','created','updated').each do |k,v| %>
    <div><strong><%= k.titleize %>:</strong> <%= Array(v).join(', ') %></div>
  <% end %>
</div>
ERB

cat > app/views/catalog/index.html.erb <<'ERB'
<div class="gallery-page container-xl py-4">
  <aside class="gallery-sidebar">
    <%= render partial: 'catalog/gallery_sidebar', locals: { response: @response } %>
  </aside>
  <section class="gallery-main">
    <%= render 'constraints' %>
    <div class="gallery-toolbar d-flex justify-content-between align-items-center mb-3">
      <div><%= render 'sort_and_per_page' %></div>
    </div>
    <%= render partial: 'catalog/gallery_grid', locals: { documents: @response.documents } %>
    <%= render 'results_pagination' %>
  </section>
</div>
ERB

cat > app/views/catalog/_gallery_sidebar.html.erb <<'ERB'
<% response ||= @response %>
<div class="attributes-panel">
  <div class="attributes-header">Attributes</div>
  <% [['np_regionName','Np Region Name'], ['np_stainID','Np Stain']].each do |field,label| %>
    <% config = facet_configuration_for_field(field) %>
    <% facet = response.aggregations[field] || response.aggregations[field.to_s] %>
    <% items = facet&.items || [] %>
    <% next unless config && items.present? %>
    <div class="attribute-group">
      <h5><%= label %></h5>
      <ul class="attributes-list list-unstyled">
        <% items.each do |item| %>
          <% facet_path = search_action_path(search_state.add_facet_params(field, item.value)) %>
          <li>
            <%= link_to facet_path, class: 'attribute-pill' do %>
              <span><%= item.value %></span>
              <small><%= item.hits %></small>
            <% end %>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
ERB

cat > app/views/catalog/_gallery_grid.html.erb <<'ERB'
<% if documents.blank? %>
  <p class="text-muted">No images found.</p>
<% else %>
  <div class="gallery-grid">
    <% documents.each do |doc| %>
      <% item_id = Array(doc['item_id']).first || doc['item_id'] %>
      <% name    = Array(doc['name']).first || doc['name'] %>
      <% case_id = Array(doc['np_caseID']).first || doc['np_caseID'] %>
      <% region  = Array(doc['np_regionName']).first || doc['np_regionName'] %>
      <% stain   = Array(doc['np_stainID']).first || doc['np_stainID'] %>
      <% doc_path = solr_document_path(doc) %>
      <div class="gallery-card">
        <a href="<%= doc_path %>" class="gallery-card-link">
          <img src="<%= thumbnail_path(item_id, width: 384, height: 384) %>" alt="<%= h(name) %>" loading="lazy"/>
        </a>
        <div class="gallery-card-caption">
          <div class="gallery-card-title"><%= link_to name, doc_path %></div>
          <ul class="gallery-card-meta list-unstyled mb-0">
            <% if case_id %><li><span>Case:</span> <%= case_id %></li><% end %>
            <% if region %><li><span>Region:</span> <%= region %></li><% end %>
            <% if stain %><li><span>Stain:</span> <%= stain %></li><% end %>
          </ul>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
ERB

cat > app/views/catalog/_home_text.html.erb <<'ERB'
<div class="gallery-home-blurb">
  <p>Browse the collection of annotated slides using the filters on the left or by typing in the search box.</p>
</div>
ERB

mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/gallery.scss <<'SCSS'
.gallery-page {
  display: flex;
  gap: 1.5rem;
}

@media (max-width: 992px) {
  .gallery-page {
    flex-direction: column;
  }
}

.gallery-sidebar {
  width: 280px;
  min-width: 240px;
  background: #fff;
  border: 1px solid #e3e3e3;
  border-radius: 12px;
  padding: 16px;
  height: fit-content;
}

.attributes-header {
  font-weight: 600;
  margin-bottom: 12px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-size: 0.9rem;
}

.gallery-main {
  flex: 1 1 auto;
}

.gallery-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 20px;
}

@media (max-width: 1400px) {
  .gallery-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 992px) {
  .gallery-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 576px) {
  .gallery-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

.gallery-card {
  background: #fff;
  border-radius: 14px;
  border: 1px solid #e6e6e6;
  overflow: hidden;
  box-shadow: 0 6px 16px rgba(15, 23, 42, 0.08);
  display: flex;
  flex-direction: column;
}

.gallery-card img {
  width: 100%;
  height: 180px;
  object-fit: cover;
  display: block;
}

.gallery-card-caption {
  padding: 12px;
}

.gallery-card-title {
  font-weight: 600;
  margin-bottom: 6px;
  font-size: 0.95rem;
}

.gallery-card-meta span {
  font-weight: 600;
  margin-right: 6px;
}

.gallery-toolbar {
  border-bottom: 1px solid #e9ecef;
  padding-bottom: 8px;
}

.gallery-home-blurb {
  padding: 20px;
  border-radius: 12px;
  background: #f8f9fa;
  border: 1px solid #e3e3e3;
  margin-bottom: 1rem;
}

.attributes-panel {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.attribute-group h5 {
  font-size: 0.95rem;
  font-weight: 600;
  margin-bottom: 6px;
}

.attributes-list {
  max-height: 260px;
  overflow: auto;
  padding-right: 4px;
}

.attribute-pill {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid #d1d5db;
  margin-bottom: 6px;
  font-size: 0.9rem;
  background: #fff;
  text-decoration: none;
  color: #111;
}

.attribute-pill small {
  color: #6b7280;
}
.attribute-pill:hover {
  border-color: #2563eb;
  color: #111;
}
SCSS

ruby <<'RUBY'
path = "app/assets/stylesheets/application.css"
if File.exist?(path)
  text = File.read(path)
  unless text.include?('*= require gallery')
    insertion = " *= require gallery\n"
    text = text.sub(" *= require_tree .\n", " *= require_tree .\n#{insertion}")
    File.write(path, text)
  end
end
RUBY

mkdir -p app/components/blacklight
cat > app/components/blacklight/document_component.html.erb <<'ERB'
<% thumb = Array(@document['thumbnail_url']).first || @document['thumbnail_url'] %>
<%= content_tag @component,
  id: @id,
  data: {
    'document-id': @document.id.to_s.parameterize,
    'document-counter': @counter,
  },
  itemscope: true,
  itemtype: @document.itemtype,
  class: classes.flatten.join(' ') do %>
  <%= header %>
  <div class="bl-result-entry" style="display:flex;gap:20px;align-items:flex-start;padding:16px;border:1px solid #e3e3e3;border-radius:10px;margin-bottom:18px;background:#fff;">
    <div class="bl-result-text" style="flex:1 1 auto;">
      <%= title %>
      <%= embed %>
      <%= content %>
      <%= metadata %>
      <% metadata_sections.each do |section| %>
        <%= section %>
      <% end %>
      <% partials.each do |partial| %>
        <%= partial %>
      <% end %>
    </div>
    <div class="bl-result-thumb" style="flex:0 0 200px;text-align:center;">
      <% if thumb.present? %>
        <% display_name = Array(@document['name']).first || @document.id %>
        <img src="<%= thumb %>" alt="<%= h(display_name) %>"
             loading="lazy"
             style="width:180px;height:180px;object-fit:cover;border-radius:10px;border:1px solid #ddd;background:#f8f8f8"/>
      <% else %>
        <%= thumbnail %>
      <% end %>
    </div>
  </div>
  <%= footer %>
<% end %>
ERB
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

if [[ "${BLACKLIGHT_FORCE_REGEN:-0}" == "1" || ! -f "${INSTALL_MARKER}" ]]; then
  bootstrap_app
else
  echo "Using cached Blacklight app at ${APP_DIR}"
  cd "$APP_DIR"
fi

cd "$APP_DIR"
ensure_hosts

cat > config/blacklight.yml <<YML
development:
  adapter: solr
  url: ${SOLR_URL}
test:
  adapter: solr
  url: ${SOLR_URL}
production:
  adapter: solr
  url: ${SOLR_URL}
YML

render_catalog_overrides

if [[ "${MODE}" == "build" ]]; then
  echo "Blacklight image primed; skipping server start (build mode)."
  exit 0
fi

echo "Starting Blacklight (${RAILS_ENV})..."
rm -f tmp/pids/server.pid
exec bundle exec rails server -b 0.0.0.0 -p 3000
