# frozen_string_literal: true

require 'tty-table'

module RateCard
  # Renders the grid for the terminal: one table per service per rate key, so
  # stdout maps 1:1 to the CSV files. Returns strings rather than printing, so
  # UI owns all output and this stays testable.
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
      table = TTY::Table.new(header: header, rows: rows(service, rate_key))
      table.render(:unicode, alignments: [:right] * header.length, padding: [0, 1])
    end

    def format_rate(value)
      return MISSING if value.nil?

      format('%.2f', value)
    end
  end
end
