# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift __dir__

# Lipgloss colours by terminal detection, so specs asserting on rendered text
# pass piped and fail in an interactive terminal.
#
# NO_COLOR has to be in the environment before this process starts: lipgloss is
# a Go extension, and the Go runtime snapshots its environment when the library
# loads, so an ENV assignment from Ruby never reaches it. Verified -- setting it
# here looks right and does nothing.
#
# Run the suite as `NO_COLOR=1 bundle exec rspec`, which is what bin/release
# and the README use. Bare `bundle exec rspec` in a terminal fails five
# rendering specs; piped, it passes either way.

require 'rate_card'

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
