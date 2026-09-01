# frozen_string_literal: true

require_relative 'rate_card/version'

module RateCard
  # Base for everything this tool raises on purpose.
  class Error < StandardError; end

  # The production API rejected the token. Retrying will not help.
  class Unauthorized < Error; end

  # A rate call failed in a way we chose not to retry (or ran out of retries).
  class RequestFailed < Error; end

  # The probe call came back with no services at all — nothing to build a card from.
  class NoServices < Error; end

  # The destination directory cannot be written to.
  class OutputNotWritable < Error; end
end

# The files below do not exist yet — each lands in its own later task.
# Uncomment each line as its task is implemented.
require_relative 'rate_card/token'
require_relative 'rate_card/service'
require_relative 'rate_card/failure'
require_relative 'rate_card/constants/carriers'
require_relative 'rate_card/constants/addresses'
require_relative 'rate_card/client'
require_relative 'rate_card/service_catalog'
require_relative 'rate_card/run_spec'
require_relative 'rate_card/shipment'
require_relative 'rate_card/grid'
require_relative 'rate_card/csv_writer'
require_relative 'rate_card/table_renderer'
# require_relative 'rate_card/ui'
# require_relative 'rate_card/wizard'
# require_relative 'rate_card/runner'
