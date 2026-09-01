# Gemfile
source 'https://rubygems.org'

ruby '>= 3.2'

# base64 and csv leave the default gems in Ruby 3.4, and requiring them from
# the stdlib prints a deprecation warning on every single invocation.
gem 'base64', '~> 0.2'
gem 'csv', '~> 3.3'
gem 'faraday', '~> 2.13'
gem 'parallel', '~> 1.26'
# The TUI. bubbles is a shared gem name: 0.0.x is an unrelated gem by another
# author that pulls in aws-sdk, so the constraint is not optional.
gem 'bubbles', '~> 0.1'
gem 'bubbletea', '~> 0.1'
gem 'lipgloss', '~> 0.2'
# Still used for the rate tables, which are printed after the TUI exits.
gem 'tty-table', '~> 0.12'

group :development, :test do
  gem 'rspec', '~> 3.13'
end
