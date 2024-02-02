# frozen_string_literal: true

require 'fileutils'
require 'shellwords'

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require 'tmpdir'
    source_paths.unshift(tempdir = Dir.mktmpdir('rails-'))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      '--quiet',
      'https://github.com/IsraelDCastro/rails-vite-tailwindcss-template.git',
      tempdir
    ].map(&:shellescape).join(' ')

    if (branch = __FILE__[%r{rails-vite-tailwindcss-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def add_gems
  gem 'vite_rails', '~> 3.0', '>= 3.0.17'
  gem 'vite_ruby', '~> 3.2', '>= 3.2.2'
  gem 'ruby-vips', '~> 2.1', '>= 2.1.4'
  gem 'annotate', group: :development
  gem 'devise'
  gem 'name_of_person'
end

def add_hotwired_gem
  gem 'stimulus-rails'
  gem 'turbo-rails'
end

def set_application_name
  # Add Application Name to Config
  environment 'config.application_name = Rails.application.class.module_parent_name'

  # Announce the user where they can change the application name in the future.
  puts 'You can change application name inside: ./config/application.rb'
end

def add_vite
  run 'bundle exec vite install'
end

def add_javascript
  run 'yarn add autoprefixer postcss sass tailwindcss vite @tailwindcss/forms'
  run 'yarn add -D eslint prettier eslint-plugin-prettier eslint-config-prettier path vite-plugin-full-reload vite-plugin-ruby'
end

def add_javascript_vue
  run 'yarn add autoprefixer postcss sass tailwindcss vite vue @tailwindcss/forms'
  run 'yarn add -D @vitejs/plugin-vue @vue/compiler-sfc eslint prettier eslint-plugin-prettier eslint-config-prettier eslint-plugin-vue path vite-plugin-full-reload vite-plugin-ruby'
end

def add_javascript_react
  run 'yarn add autoprefixer postcss sass tailwindcss vite react react-dom @headlessui/react @heroicons/react @tailwindcss/forms'
  run 'yarn add -D @vitejs/plugin-react-refresh eslint prettier eslint-plugin-prettier eslint-config-prettier eslint-plugin-react path vite-plugin-full-reload vite-plugin-ruby'
end

def add_hotwired
  run 'yarn add @hotwired/stimulus @hotwired/turbo-rails'
end

def setup_legacy_version_files
  copy_file '.node-version'
end

def setup_docker_compose
  copy_file 'docker-compose.yml'
  system 'docker compose up -d', out: $stdout, err: :out
  inject_into_file '.gitignore', "\n\n# Ignore docker container files\n/db/development/", after: '/public/assets'
  sleep 5
end

def copy_templates

  copy_file 'Procfile.dev'
  copy_file 'jsconfig.json'
  copy_file 'tailwind.config.js'
  copy_file 'postcss.config.js'

  # directory 'app', force: true
  directory 'config', force: true
  directory 'lib', force: true

  run 'for file in lib/templates/**/**/*.txt; do mv "$file" "${file%.txt}.tt"; done'
  say '  Custom scaffold templates copied', :green
end

def add_pages_controller
  generate 'controller Pages home'
  route "root to: 'pages#home'"
end

def run_command_flags
  ARGV.each do |flag|
    case flag
    when '--react'
      copy_file 'vite.config-react.ts', 'vite.config.ts'
      copy_file '.eslintrc-react.json', '.eslintrc.json'
      directory 'app-react', 'app', force: true
      add_javascript_react
    when '--vue'
      copy_file 'vite.config-vue.ts', 'vite.config.ts'
      copy_file '.eslintrc-vue.json', '.eslintrc.json'
      directory 'app-vue', 'app', force: true
      add_javascript_vue
    when '--normal'
      copy_file 'vite.config.ts'
      copy_file '.eslintrc.json'
      directory 'app', force: true
      add_javascript
    when '--hotwired'
      directory 'hotwired-generator', 'lib/generators'
      add_hotwired_gem
      add_hotwired
      inject_into_file('app/frontend/entrypoints/application.js', 'import { Turbo } from "@hotwired/turbo-rails";' "\n\n" 'window.Turbo = Turbo;' "\n\n", before: 'import "./main.scss";')
    else
      # Do nothing
    end
  end
end

# Main setup
add_gems

after_bundle do
  add_template_repository_to_source_path
  set_application_name
  add_pages_controller
  setup_legacy_version_files
  setup_docker_compose
  run_command_flags

  copy_templates
  add_vite

  rails_command 'db:create'

  rails_command 'generate devise:install'
  rails_command 'generate devise user'
  rails_command 'generate migration AddNameFieldsToUser first_name last_name'
  inject_into_file('app/models/user.rb', "\n\n" '  has_person_name', after: ':validatable')
  inject_into_file('app/controllers/application_controller.rb', "\n\n" '  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up) do |u|
      u.permit(:first_name, :last_name, :name, :email, :password)
    end

    devise_parameter_sanitizer.permit(:account_update) do |u|
      u.permit(:first_name, :last_name, :name, :email, :password, :password_confirmation, :current_password)
    end
  end' "\n\n", after: 'class ApplicationController < ActionController::Base')

  rails_command 'active_storage:install'
  rails_command 'g annotate:install'
  inject_into_file('config/application.rb', "\n\n" '    config.active_storage.variant_processor = :vips', after: 'config.load_defaults 7.0')
  rails_command 'db:migrate'

  begin
    git add: '.'
    git commit: %( -m 'Initial commit' )
  rescue StandardError => e
    puts e.message
  end

  say

  ARGV.each do |flag|
    say 'Rails 7 + Vue 3 + ViteJS + Tailwindcss created!', :green if flag == '--vue'
    say 'Rails 7 + ReactJS 18 + ViteJS + Tailwindcss created!', :green if flag == '--react'
    say 'Rails 7 + ViteJS + Tailwindcss created!', :green if flag == '--normal'
    say 'Hotwired + Stimulus were added successfully', :green if flag == '--hotwired'
  end

  say
  say '  To get started with your new app:', :yellow
  say "  cd #{original_app_name}"
  say
  say '  # Please update config/database.yml with your database credentials'
  say
  say '  rails s'
end
