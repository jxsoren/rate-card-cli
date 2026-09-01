# frozen_string_literal: true

module RateCard
  # Orchestrates one run: verify the destination, fetch, render, write, report.
  # Returns the process exit code.
  class Runner
    def initialize(spec:, client:, ui:)
      @spec = spec
      @client = client
      @ui = ui
    end

    def run
      # Before the first call, so a bad path is not discovered after 128 of them.
      CsvWriter.ensure_writable!(spec.output_base)

      grid = fetch(spec, client)

      @ui.print_tables(TableRenderer.new(grid: grid, spec: spec).tables) if spec.show_table
      @ui.failure_report(grid.failures)

      if grid.all_failed?
        @ui.error('every rate call failed — no files written')
        return 1
      end

      unless grid.any_rates?
        @ui.error('the calls succeeded but returned no rates for the selected ' \
                  'services — check the service, package type and weight range')
        return 1
      end

      @ui.saved(CsvWriter.new(grid: grid, spec: spec).write)
      0
    end

    private

    attr_reader :spec, :client

    def fetch(spec, client)
      @ui.blank
      @ui.with_progress(spec.call_count) do |tick|
        Grid.build(spec: spec, client: client, on_progress: tick)
      end
    end
  end
end
