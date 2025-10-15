# Rails application template for multitenant application with TailwindCSS and activerecord-tenanted

# Add gems
gem 'activerecord-tenanted', '~> 0.4.1'
gem 'tailwindcss-rails'
gem_group :development do
  gem 'tidewave'
end

gem_group :test do
  gem 'mocha'
end

# Create Claude Code MCP configuration
create_file '.mcp.json' do
  <<~JSON
    {
      "mcpServers": {
        "chrome-devtools": {
          "type": "stdio",
          "command": "npx",
          "args": [
            "chrome-devtools-mcp@latest"
          ],
          "env": {}
        },
        "tidewave": {
          "type": "sse",
          "url": "http://localhost:3000/tidewave/mcp"
        }
      }
    }
  JSON
end

# Configure database.yml
remove_file 'config/database.yml'
create_file 'config/database.yml' do
  <<~YAML
    # SQLite. Versions 3.8.0 and up are supported.
    #   gem install sqlite3
    #
    #   Ensure the SQLite 3 gem is defined in your Gemfile
    #   gem "sqlite3"
    #
    default: &default
      adapter: sqlite3
      max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
      timeout: 5000

    # Tenanted account database for account-specific data
    account: &account
      <<: *default
      tenanted: true
      database: storage/<%= Rails.env %>/account/%<tenant>s.sqlite3
      migrations_paths: db/account_migrate

    # Non-tenanted primary database for platform data
    primary: &primary
      <<: *default
      database: storage/<%= Rails.env %>/primary.sqlite3

    development:
      primary:
        <<: *primary
      account:
        <<: *account

    # Warning: The database defined as "test" will be erased and
    # re-generated from your development database when you run "rake".
    # Do not set this db to the same as development or production.
    test:
      primary:
        <<: *primary
      account:
        <<: *account

    # Store production database in the storage/ directory, which by default
    # is mounted as a persistent Docker volume in config/deploy.yml.
    production:
      primary:
        <<: *primary
      account:
        <<: *account
      cache:
        <<: *default
        database: storage/production_cache.sqlite3
        migrations_paths: db/cache_migrate
      queue:
        <<: *default
        database: storage/production_queue.sqlite3
        migrations_paths: db/queue_migrate
      cable:
        <<: *default
        database: storage/production_cable.sqlite3
        migrations_paths: db/cable_migrate
  YAML
end

# Create ApplicationRecord
create_file 'app/models/application_record.rb' do
  <<~RUBY
    class ApplicationRecord < ActiveRecord::Base
      primary_abstract_class
    end
  RUBY
end

# Create AccountRecord
create_file 'app/models/account_record.rb' do
  <<~RUBY
    class AccountRecord < ActiveRecord::Base
      self.abstract_class = true

      tenanted "account"
    end
  RUBY
end

# Create Account model
create_file 'app/models/account.rb' do
  <<~RUBY
    class Account < ApplicationRecord
      # Include WithDatabase concern for tenant creation/destruction hooks.
      include Account::WithDatabase

      validates :tenant_id, presence: true, format: { with: %r{\\A[a-z0-9-]+\\z}, message: "must be lowercase alphanumeric and dashes" }
    end
  RUBY
end

# Create WithDatabase concern
create_file 'app/models/concerns/account/with_database.rb' do
  <<~RUBY
    # frozen_string_literal: true

    module Account::WithDatabase
      extend ActiveSupport::Concern

      included do
        after_create_commit :create_tenant
        after_destroy_commit :destroy_tenant
      end

      private

      def create_tenant
        AccountRecord.create_tenant(tenant_id)
      end

      def destroy_tenant
        AccountRecord.destroy_tenant(tenant_id)
      end
    end
  RUBY
end

# Create tenancy initializer
create_file 'config/initializers/tenancy.rb' do
  <<~RUBY
    Rails.application.configure do
      config.active_record_tenanted.tenant_resolver = ->(request) { request.subdomain }
      config.active_record_tenanted.default_tenant = Rails.env.local? ? "dev" : nil
      config.active_record_tenanted.connection_class = "AccountRecord"
    end
  RUBY
end

# Configure host for development
app_name = File.basename(Dir.pwd).gsub(/[^a-z0-9-]/, '-').downcase
host = "#{app_name}.localhost:3000"
environment "config.action_mailer.default_url_options = { host: \"#{host}\" }", env: 'development'
environment "config.default_url_options = { host: \"#{host}\" }", env: 'development'
environment "config.hosts << \"#{host}\"", env: 'development'
environment "config.hosts << \".#{host}\"", env: 'development'

# Create migration for accounts
create_file 'db/migrate/20240925000000_create_accounts.rb' do
  <<~RUBY
    class CreateAccounts < ActiveRecord::Migration[8.1]
      def change
        create_table :accounts do |t|
          t.string :tenant_id
          t.timestamps
        end
        add_index :accounts, :tenant_id, unique: true
      end
    end
  RUBY
end

# Update seeds
remove_file 'db/seeds.rb'
create_file 'db/seeds.rb' do
  <<~RUBY
    # This file should ensure the existence of records required to run the application in every environment (production,
    # development, test). The code here should be idempotent so that it can be executed at any point in every environment.
    # The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

    Account.upsert({ tenant_id: "dev" }, unique_by: :tenant_id)
  RUBY
end

# Create admin application controller
create_file 'app/controllers/admin/application_controller.rb' do
  <<~RUBY
    class Admin::ApplicationController < ApplicationController
      layout "admin"
    end
  RUBY
end

# Create accounts controller
create_file 'app/controllers/admin/accounts_controller.rb' do
  <<~RUBY
    class Admin::AccountsController < Admin::ApplicationController
      before_action :set_account, only: %i[ edit update destroy ]

      # GET /admin/accounts
      def index
        @accounts = Account.all
      end

      # GET /admin/accounts/new
      def new
        @account = Account.new
      end

      # POST /admin/accounts
      def create
        @account = Account.new(account_params)

        if @account.save
          redirect_to admin_accounts_path, notice: "Account was successfully created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      # GET /admin/accounts/1/edit
      def edit
      end

      # PATCH/PUT /admin/accounts/1
      def update
        if @account.update(account_params)
          redirect_to admin_accounts_path, notice: "Account was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /admin/accounts/1
      def destroy
        @account.destroy
        redirect_to admin_accounts_path, notice: "Account was successfully destroyed."
      end

      private
        # Use callbacks to share common setup or constraints between actions.
        def set_account
          @account = Account.find(params[:id])
        end

        # Only allow a list of trusted parameters through.
        def account_params
          params.require(:account).permit(:tenant_id)
        end
    end
  RUBY
end

# Update routes
route 'namespace :admin do
  resources :accounts, except: :show
end'

# Create admin layout
create_file 'app/views/layouts/admin.html.erb' do
  <<~HTML
    <!DOCTYPE html>
    <html>
      <head>
        <title><%= content_for(:title) || "Admin" %></title>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="application-name" content="Admin">
        <%= csrf_meta_tags %>
        <%= csp_meta_tag %>

        <%= yield :head %>

        <link rel="icon" href="/icon.png" type="image/png">
        <link rel="icon" href="/icon.svg" type="image/svg+xml">
        <link rel="apple-touch-icon" href="/icon.png">

        <%# Includes all stylesheet files in app/assets/stylesheets %>
        <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
        <%= javascript_importmap_tags %>
      </head>

      <body class="bg-base-200">
        <main class="w-full mt-28 px-5">
          <%= yield %>
        </main>
      </body>
    </html>
  HTML
end

# Create accounts index view
create_file 'app/views/admin/accounts/index.html.erb' do
  <<~HTML
    <div class="card bg-base-100 shadow-xl w-full max-w-7xl mx-auto">
      <div class="card-body">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 space-y-4 sm:space-y-0">
          <h2 class="card-title text-xl md:text-2xl">Accounts</h2>
          <%= link_to 'New Account', new_admin_account_path, class: 'btn btn-primary btn-sm md:btn-md' %>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Tenant ID</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <% @accounts.each do |account| %>
                <tr>
                  <td><%= account.tenant_id %></td>
                  <td>
                    <div class="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-2">
                      <%= link_to 'Edit', edit_admin_account_path(account), class: 'btn btn-ghost btn-xs' %>
                      <%= link_to 'Destroy', admin_account_path(account), data: { turbo_method: :delete, turbo_confirm: 'Are you sure?' }, class: 'btn btn-ghost btn-xs text-error' %>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  HTML
end

# Create accounts new view
create_file 'app/views/admin/accounts/new.html.erb' do
  <<~HTML
    <div class="card bg-base-100 shadow-xl w-full max-w-2xl mx-auto">
      <div class="card-body">
        <h2 class="card-title text-xl md:text-2xl mb-4">New Account</h2>
        <%= render "form", account: @account %>
      </div>
    </div>
  HTML
end

# Create accounts edit view
create_file 'app/views/admin/accounts/edit.html.erb' do
  <<~HTML
    <div class="card bg-base-100 shadow-xl w-full max-w-2xl mx-auto">
      <div class="card-body">
        <h2 class="card-title text-xl md:text-2xl mb-4">Edit Account</h2>
        <%= render "form", account: @account %>
      </div>
    </div>
  HTML
end

# Create accounts form partial
create_file 'app/views/admin/accounts/_form.html.erb' do
  <<~HTML
    <%= form_with(model: account, url: account.persisted? ? admin_account_path(account) : admin_accounts_path) do |form| %>
      <% if account.errors.any? %>
        <div role="alert" class="alert alert-error mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 shrink-0 stroke-current" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <h3 class="font-bold">
              <%= pluralize(account.errors.count, "error") %> prohibited this account from being saved:
            </h3>
            <ul class="list-disc list-inside mt-2">
              <% account.errors.each do |error| %>
                <li class="text-sm"><%= error.full_message %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <fieldset class="fieldset">
        <label class="label">
          <span class="label-text">Tenant ID</span>
        </label>
        <%= form.text_field :tenant_id, readonly: account.persisted?, class: 'input input-bordered w-full', placeholder: 'dev' %>
        <% if account.persisted? %>
          <label class="label">
            <span class="label-text-alt">Tenant ID cannot be changed after creation</span>
          </label>
        <% end %>
      </fieldset>

      <div class="flex justify-end space-x-2 mt-6">
        <%= link_to 'Cancel', admin_accounts_path, class: 'btn btn-ghost' %>
        <%= form.submit class: 'btn btn-primary' %>
      </div>
    <% end %>
  HTML
end

# Create accounts controller test
create_file 'test/controllers/admin/accounts_controller_test.rb' do
  <<~RUBY
    require "test_helper"

    class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @account = accounts(:one)
      end

      test "should get index" do
        get admin_accounts_url
        assert_response :success
      end

      test "should get new" do
        get new_admin_account_url
        assert_response :success
      end

      test "should create account" do
        AccountRecord.expects(:create_tenant).with("newtenant")
        assert_difference("Account.count") do
          post admin_accounts_url, params: { account: { tenant_id: "newtenant" } }
        end

        assert_redirected_to admin_accounts_url
      end

      test "should not create account with invalid data" do
        assert_no_difference("Account.count") do
          post admin_accounts_url, params: { account: { tenant_id: "INVALID" } }
        end

        assert_response :unprocessable_entity
      end

      test "should get edit" do
        get edit_admin_account_url(@account)
        assert_response :success
      end

      test "should update account" do
        patch admin_account_url(@account), params: { account: { tenant_id: "updatedtenant" } }
        assert_redirected_to admin_accounts_url

        @account.reload
        assert_equal "updatedtenant", @account.tenant_id
      end

      test "should not update account with invalid data" do
        patch admin_account_url(@account), params: { account: { tenant_id: "" } }
        assert_response :unprocessable_entity
      end

      test "should destroy account" do
        AccountRecord.expects(:destroy_tenant).with(@account.tenant_id)
        assert_difference("Account.count", -1) do
          delete admin_account_url(@account)
        end

        assert_redirected_to admin_accounts_url
      end
    end
  RUBY
end

# Update test_helper to include mocha
insert_into_file 'test/test_helper.rb', "\nrequire \"mocha/minitest\"", after: 'require "rails/test_help"'

# Create test fixtures
create_file 'test/fixtures/accounts.yml' do
  <<~YAML
    one:
      tenant_id: dev
  YAML
end

# Install TailwindCSS
run 'rails tailwindcss:install'

# Download DaisyUI files
run 'curl -sLo app/assets/tailwind/daisyui.mjs https://github.com/saadeghi/daisyui/releases/latest/download/daisyui.mjs'
run 'curl -sLo app/assets/tailwind/daisyui-theme.mjs https://github.com/saadeghi/daisyui/releases/latest/download/daisyui-theme.mjs'

# Configure DaisyUI in Tailwind
append_to_file 'app/assets/tailwind/application.css' do
  <<~CSS

    @source not "./daisyui{,*}.mjs";

    @plugin "./daisyui.mjs";

    /* Optional for custom themes – Docs: https://daisyui.com/docs/themes/#how-to-add-a-new-custom-theme */
    @plugin "./daisyui-theme.mjs"{
      /* custom theme here */
    }
  CSS
end

# Run bundle install
run 'bundle install'
