# frozen_string_literal: true

module RateCard
  # One shipping service the customer has enabled, as discovered from a probe call.
  Service = Struct.new(:id, :code, :name, :carrier, keyword_init: true) do
    # What the wizard checkbox shows.
    def label
      "#{name} (#{id})"
    end

    # Basis for output filenames; must be filesystem-safe.
    def file_slug
      base = code.to_s.strip
      base = name.to_s.strip if base.empty?
      base = "service_#{id}" if base.empty?
      base.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    end
  end
end
