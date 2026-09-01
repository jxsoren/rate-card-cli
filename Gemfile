# Gemfile
source 'https://rubygems.org'

ruby '>= 3.2'

# base64 and csv leave the default gems in Ruby 3.4, and requiring them from
# the stdlib prints a deprecation warning on every single invocation.
gem 'base64', '~> 0.2'
gem 'csv', '~> 3.3'
gem 'faraday', '~> 2.13'
gem 'parallel', '~> 1.26'
gem 'pastel', '~> 0.8'
gem 'tty-box', '~> 0.7'
gem 'tty-progressbar', '~> 0.18'
gem 'tty-prompt', '~> 0.23'
gem 'tty-spinner', '~> 0.9'
gem 'tty-table', '~> 0.12'

group :development, :test do
  gem 'rspec', '~> 3.13'
end
