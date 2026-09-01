# frozen_string_literal: true

require_relative 'lib/rate_card/version'

Gem::Specification.new do |spec|
  spec.name = 'rate-card'
  spec.version = RateCard::VERSION
  spec.authors = ['eHub']

  spec.summary = 'Interactive CLI that builds a shipping rate card from the eHub API.'
  spec.description = <<~TEXT
    rate-card walks you through a carrier, its services, zones, a weight range and a
    package type, fetches every weight x zone cell from the eHub API, prints the rate
    card to your terminal and saves it as CSV.
  TEXT
  spec.homepage = 'https://github.com/jxsoren/rate-card-cli'
  spec.license = 'MIT'

  # 3.2 is the floor for the syntax in use; the repo pins 3.3.4 for development.
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'README.md', 'LICENSE.txt'].select { |f| File.file?(f) }
  spec.bindir = 'exe'
  spec.executables = ['rate-card']
  spec.require_paths = ['lib']

  # base64 and csv leave the default gems in Ruby 3.4, and requiring them from
  # the stdlib prints a deprecation warning on every single invocation.
  spec.add_dependency 'base64', '~> 0.2'
  spec.add_dependency 'csv', '~> 3.3'
  spec.add_dependency 'faraday', '~> 2.13'
  spec.add_dependency 'parallel', '~> 1.26'

  # The TUI. bubbles is a shared gem name: 0.0.x is an unrelated gem by another
  # author that pulls in aws-sdk, so the constraint is not optional.
  spec.add_dependency 'bubbles', '~> 0.1'
  spec.add_dependency 'bubbletea', '~> 0.1'
  spec.add_dependency 'lipgloss', '~> 0.2'

  # Still used for the rate tables, which are printed after the TUI exits.
  spec.add_dependency 'tty-table', '~> 0.12'
end
