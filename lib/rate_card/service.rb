# frozen_string_literal: true

module RateCard
  # One shipping service the customer has enabled, as discovered from a probe call.
  Service = Struct.new(:id, :code, :name, :carrier, keyword_init: true) do
    # What the wizard checkbox shows.
    def label
      "#{name} (#{id})"
    end

    # Basis for output filenames; must be filesystem-safe and never empty.
    #
    # Falls through on the SANITISED value, not the raw one: a code like '###'
    # is non-empty but sanitises to nothing, and an empty slug would produce a
    # file named '_shipper_rate.csv' on the user's disk.
    def file_slug
      [code, name].each do |candidate|
        slug = sanitize(candidate)
        return slug unless slug.empty?
      end

      sanitize("service_#{id}")
    end

    private

    def sanitize(value)
      value.to_s.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    end
  end
end
