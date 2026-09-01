# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'pathname'

module RateCard
  # Writes the grid to disk: one CSV per service per rate key, into the run's
  # timestamped directory. A nil cell is an empty field, never 0.0.
  class CsvWriter
    # Called before fetching, so a bad destination is reported before the user
    # pays for a few hundred production calls rather than after.
    def self.ensure_writable!(base)
      base = Pathname.new(base)
      FileUtils.mkdir_p(base)
      raise OutputNotWritable, "cannot write to #{base}" unless base.writable?
    rescue SystemCallError => e
      raise OutputNotWritable, "cannot create #{base}: #{e.message}"
    end

    def initialize(grid:, spec:)
      @grid = grid
      @spec = spec
    end

    # Returns Array<Pathname> of the files written.
    def write
      FileUtils.mkdir_p(spec.run_dir)

      spec.services.flat_map do |service|
        spec.rate_keys.map { |rate_key| write_file(service, rate_key) }
      end
    end

    private

    attr_reader :grid, :spec

    def write_file(service, rate_key)
      path = spec.run_dir.join("#{service.file_slug}_#{rate_key}.csv")

      CSV.open(path, 'w') do |csv|
        csv << ['weight', *spec.zones]
        spec.weights.each { |weight| csv << row_for(service, rate_key, weight) }
      end

      path
    end

    def row_for(service, rate_key, weight)
      cells = spec.zones.map do |zone|
        grid.value(service_id: service.id, rate_key: rate_key, weight: weight, zone: zone)
      end

      [weight, *cells]
    end
  end
end
