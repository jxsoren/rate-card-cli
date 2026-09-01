# frozen_string_literal: true

module RateCard
  # Reports one completed run: render, write, report. Returns the process exit
  # code.
  #
  # The fetch itself moved into TUI::App when this switched to Bubbletea — it
  # has to happen inside the event loop for the progress bar to be live — so
  # this now takes the finished Grid rather than building one. Everything here
  # runs after the terminal is back to normal, which is why it is all plain
  # printing.
  class Runner
    def initialize(spec:, grid:, ui:)
      @spec = spec
      @grid = grid
      @ui = ui
    end

    def run
      @ui.print_tables(TableRenderer.new(grid: grid, spec: spec).tables) if spec.show_table
      @ui.failure_report(grid.failures, spec: spec)
      @ui.warning_report(grid.warnings)

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

    attr_reader :spec, :grid
  end
end
