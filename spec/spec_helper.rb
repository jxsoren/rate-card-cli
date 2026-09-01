# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift __dir__

# Lipgloss colours by terminal detection, so a spec asserting on rendered text
# would pass piped and fail in an interactive terminal. Pinned before rate_card
# loads, since the profile is decided on first use.
ENV['NO_COLOR'] = '1'

require 'rate_card'

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
