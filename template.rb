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

# Create opencode.json
create_file 'opencode.json' do
  <<~JSON
    {
      "$schema": "https://opencode.ai/config.json",
      "mcp": {
        "tidewave": {
          "type": "remote",
          "url": "http://localhost:3000/tidewave/mcp",
          "enabled": true,
          "headers": {}
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

      <body class="bg-gray-800">
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
    <div class="bg-gray-900 rounded-lg p-4 md:p-6 shadow-lg w-full max-w-7xl mx-auto">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 space-y-4 sm:space-y-0">
        <h1 class="text-xl md:text-2xl font-bold text-white">Accounts</h1>
        <%= link_to 'New Account', new_admin_account_path, class: 'bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md font-medium text-sm md:text-base' %>
      </div>

      <div class="overflow-x-auto">
        <table class="min-w-full bg-gray-800 rounded-lg overflow-hidden">
          <thead class="bg-gray-700">
            <tr>
              <th class="px-3 md:px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Tenant ID</th>
              <th class="px-3 md:px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-600">
            <% @accounts.each do |account| %>
              <tr class="hover:bg-gray-700">
                <td class="px-3 md:px-6 py-4 whitespace-nowrap text-sm text-gray-300"><%= account.tenant_id %></td>
                <td class="px-3 md:px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <div class="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-4">
                    <%= link_to 'Edit', edit_admin_account_path(account), class: 'text-yellow-400 hover:text-yellow-300' %>
                    <%= link_to 'Destroy', admin_account_path(account), data: { turbo_method: :delete, turbo_confirm: 'Are you sure?' }, class: 'text-red-400 hover:text-red-300' %>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  HTML
end

# Create accounts new view
create_file 'app/views/admin/accounts/new.html.erb' do
  <<~HTML
    <div class="bg-gray-900 rounded-lg p-4 md:p-6 shadow-lg w-full max-w-2xl mx-auto">
      <div class="mb-6">
        <h1 class="text-xl md:text-2xl font-bold text-white">New Account</h1>
      </div>

      <%= render "form", account: @account %>
    </div>
  HTML
end

# Create accounts edit view
create_file 'app/views/admin/accounts/edit.html.erb' do
  <<~HTML
    <div class="bg-gray-900 rounded-lg p-4 md:p-6 shadow-lg w-full max-w-2xl mx-auto">
      <div class="mb-6">
        <h1 class="text-xl md:text-2xl font-bold text-white">Edit Account</h1>
      </div>

      <%= render "form", account: @account %>
    </div>
  HTML
end

# Create accounts form partial
create_file 'app/views/admin/accounts/_form.html.erb' do
  <<~HTML
    <%= form_with(model: account, url: account.persisted? ? admin_account_path(account) : admin_accounts_path, class: 'space-y-4 md:space-y-6') do |form| %>
      <% if account.errors.any? %>
        <div class="bg-red-900 border border-red-700 rounded-md p-3 md:p-4">
          <h3 class="text-sm font-medium text-red-400">
            <%= pluralize(account.errors.count, "error") %> prohibited this account from being saved:
          </h3>
          <div class="mt-2 text-sm text-red-300">
            <ul role="list" class="list-disc pl-5 space-y-1">
              <% account.errors.each do |error| %>
                <li><%= error.full_message %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div>
        <%= form.label :tenant_id, class: 'block text-sm font-medium text-gray-300' %>
        <%= form.text_field :tenant_id, readonly: account.persisted?, class: 'mt-1 block w-full bg-gray-800 border border-gray-600 rounded-md shadow-sm py-2 px-3 text-white placeholder-gray-400 focus:outline-none focus:ring-blue-500 focus:border-blue-500 read-only:text-gray-400 text-sm md:text-base' %>
        <% if account.persisted? %>
          <p class="mt-1 text-xs md:text-sm text-gray-400">Tenant ID cannot be changed after creation</p>
        <% end %>
      </div>

      <div class="flex justify-end space-x-3">
        <%= link_to 'Cancel', admin_accounts_path, class: 'bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-md font-medium' %>
        <%= form.submit class: 'bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md font-medium focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-900' %>
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

# Run bundle install
run 'bundle install'
