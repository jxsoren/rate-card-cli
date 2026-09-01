# frozen_string_literal: true

require 'lipgloss'
require_relative 'tui/theme'

module RateCard
  # Renders the grid for the terminal: one table per service per rate key, so
  # stdout maps 1:1 to the CSV files. Returns strings rather than printing, so
  # UI owns all output and this stays testable.
  #
  # Lipgloss draws these rather than TTY::Table, so the card wears the same
  # rounded border as the TUI banner instead of looking like a different
  # program's output. Lipgloss also strips colour by itself when stdout is not a
  # terminal, so the bold header survives being piped to a file as plain text.
  class TableRenderer
    MISSING = '—'

    def initialize(grid:, spec:)
      @grid = grid
      @spec = spec
    end

    # Returns Array<[title String, rendered String]>.
    def tables
      spec.services.flat_map do |service|
        spec.rate_keys.map { |rate_key| [title_for(service, rate_key), render(service, rate_key)] }
      end
    end

    def rows(service, rate_key)
      spec.weights.map do |weight|
        cells = spec.zones.map do |zone|
          format_rate(grid.value(service_id: service.id, rate_key: rate_key,
                                 weight: weight, zone: zone))
        end
        [weight.to_s, *cells]
      end
    end

    private

    attr_reader :grid, :spec

    def title_for(service, rate_key)
      "#{spec.customer_name} (#{spec.customer_id}) · #{service.name} · " \
        "#{spec.rate_key_label(rate_key)}"
    end

    def render(service, rate_key)
      header = [spec.weight_label, *spec.zones.map { |zone| "Z#{zone}" }]
      body = rows(service, rate_key)

      Lipgloss::Table.new
                     .headers(header)
                     .rows(body)
                     .border(Lipgloss::ROUNDED_BORDER)
                     .style_func(rows: body.length, columns: header.length) { |row, _column| cell_style(row) }
                     .render
    end

    # Everything is right-aligned: these are all numbers, and a rate is only
    # comparable to the one above it when the decimal points line up. The
    # header is the one styled row, which is what makes a wide card scannable
    # once several tables are printed in a row.
    def cell_style(row)
      style = Lipgloss::Style.new.align(Lipgloss::RIGHT).padding(0, 1)
      return style.bold(true).foreground(TUI::Theme::ACCENT) if row == Lipgloss::Table::HEADER_ROW

      style
    end

    def format_rate(value)
      return MISSING if value.nil?

      format('%.2f', value)
    end
  end
end
