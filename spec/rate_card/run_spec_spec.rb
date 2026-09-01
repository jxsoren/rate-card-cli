# frozen_string_literal: true

require 'pathname'

RSpec.describe RateCard::RunSpec do
  def build(**overrides)
    described_class.new(**{
      token: 'tok',
      customer_name: 'Acme Fulfillment',
      customer_id: 1042,
      carrier: 'USPS',
      services: [RateCard::Service.new(id: 1172, code: 'GroundAdvantage',
                                      name: 'USPS Ground Advantage', carrier: 'USPS')],
      zones: [1, 2, 3],
      weight_unit: :oz,
      weights: [1, 2],
      package_type: 'parcel',
      rate_keys: %i[shipper_rate meter_rate],
      output_base: Pathname.new('/tmp/rc'),
      show_table: true,
      started_at: Time.utc(2026, 8, 31, 15, 4, 22)
    }.merge(overrides))
  end

  describe 'RATE_KEY_FIELDS' do
    it 'maps our rate key names to the response field names' do
      expect(described_class::RATE_KEY_FIELDS)
        .to eq(shipper_rate: 'rate', meter_rate: 'meter_rate')
    end
  end

  describe '.compact_range' do
    it 'collapses runs of three or more' do
      expect(described_class.compact_range([1, 2, 3, 4, 5, 6, 7, 8])).to eq('1-8')
    end

    it 'leaves a pair listed, since 4-5 is no shorter than 4,5' do
      expect(described_class.compact_range([4, 5])).to eq('4,5')
    end

    it 'mixes runs and singletons, sorted and deduplicated' do
      expect(described_class.compact_range([5, 1, 2, 3, 5, 9])).to eq('1-3,5,9')
    end
  end

  describe '#zone_summary / #service_names / #rate_key_labels' do
    it 'describes the run for the pre-confirm recap' do
      spec = build(zones: [1, 2, 3, 7], weights: [1, 2, 3, 4], weight_unit: :lbs)

      expect(spec.zone_summary).to eq('1-3,7')
      expect(spec.service_names).to eq(['USPS Ground Advantage'])
      expect(spec.rate_key_labels).to eq(['shipper rate', 'meter rate'])
    end
  end

  describe '#call_count' do
    it 'is weights times zones, independent of how many services are selected' do
      one_service = build
      many_services = build(services: Array.new(6) do |i|
        RateCard::Service.new(id: i, code: "S#{i}", name: "S#{i}", carrier: 'USPS')
      end)

      expect(one_service.call_count).to eq(6)
      expect(many_services.call_count).to eq(6)
    end
  end

  describe '#rows / #row_label / #row_header (weight mode)' do
    it 'defaults to weight mode when rate_mode is not set' do
      expect(build.rate_mode).to eq(:weight)
    end

    it 'rows is the weights array' do
      expect(build(weights: [1, 2, 4]).rows).to eq([1, 2, 4])
    end

    it 'labels a row with the raw weight' do
      expect(build.row_label(4)).to eq('4')
    end

    it 'heads the row column "weight"' do
      expect(build.row_header).to eq('weight')
    end

    it 'sends the row weight, unit-converted, as the wire weight' do
      expect(build(weight_unit: :lbs).weight_in_oz_for(3)).to eq(48)
    end

    it 'has no dimension override' do
      expect(build.dims_for(4)).to be_nil
    end
  end

  describe '#rows / #row_label / #row_header (cubic mode)' do
    def cubic_build(**overrides)
      build(rate_mode: :cubic, cubic_tiers: [1, 9], weights: [], **overrides)
    end

    it 'rows is the selected cubic tier ids' do
      expect(cubic_build.rows).to eq([1, 9])
    end

    it 'labels a row with the tier name' do
      expect(cubic_build.row_label(1)).to eq('Tier 1')
    end

    it 'heads the row column "cubic_tier"' do
      expect(cubic_build.row_header).to eq('cubic_tier')
    end

    it 'sends the tier weight cap as the wire weight, ignoring weight_unit' do
      expect(cubic_build.weight_in_oz_for(1)).to eq(128)
      expect(cubic_build.weight_in_oz_for(9)).to eq(240)
    end

    it 'returns the tier bounding cube as the dimension override' do
      expect(cubic_build.dims_for(1)).to eq(length: 3.0, width: 3.0, height: 3.0)
    end
  end

  describe '#weight_label (cubic mode)' do
    it 'reads "cubic tier" instead of a unit' do
      spec = build(rate_mode: :cubic, cubic_tiers: [1], weights: [])
      expect(spec.weight_label).to eq('cubic tier')
    end
  end

  describe '#call_count (cubic mode)' do
    it 'is cubic tiers times zones' do
      spec = build(rate_mode: :cubic, cubic_tiers: [1, 2, 3], weights: [], zones: [1, 2])
      expect(spec.call_count).to eq(6)
    end
  end

  describe '#weight_in_oz' do
    it 'passes ounces through unchanged' do
      expect(build(weight_unit: :oz).weight_in_oz(3)).to eq(3)
    end

    it 'converts pounds to ounces at the wire boundary' do
      expect(build(weight_unit: :lbs).weight_in_oz(3)).to eq(48)
    end
  end

  describe '#address_for' do
    it 'returns the curated address for a zone on this carrier' do
      expect(build.address_for(3)).to include(city: 'Cody')
    end
  end

  describe '#run_dir' do
    it 'is a timestamped per-customer subfolder of the output base' do
      expect(build.run_dir.to_s).to eq('/tmp/rc/acme_fulfillment_1042_2026-08-31T15-04-22Z')
    end

    it 'slugifies an email, which is the usual customer name' do
      spec = build(customer_name: 'ops@acme.test')

      expect(spec.run_dir.basename.to_s).to start_with('ops_acme_test_1042_')
    end

    it 'never builds a directory starting with an underscore' do
      expect(build(customer_name: '   ').run_dir.basename.to_s)
        .to start_with('customer_1042_')
    end

    it 'slugifies a customer name with punctuation and spaces' do
      spec = build(customer_name: "Bob's Widgets, Inc.")

      expect(spec.run_dir.basename.to_s).to start_with('bobs_widgets_inc_1042_')
    end
  end

  describe '#rate_key_label' do
    it 'gives a human label for a rate key' do
      expect(build.rate_key_label(:shipper_rate)).to eq('shipper rate')
      expect(build.rate_key_label(:meter_rate)).to eq('meter rate')
    end
  end

  describe '#weight_label' do
    it 'names the weight column with its unit' do
      expect(build(weight_unit: :oz).weight_label).to eq('wt(oz)')
      expect(build(weight_unit: :lbs).weight_label).to eq('wt(lbs)')
    end
  end

  describe '#validate!' do
    it 'accepts a well-formed spec' do
      expect { build.validate! }.not_to raise_error
    end

    it 'rejects an empty service selection' do
      expect { build(services: []).validate! }
        .to raise_error(ArgumentError, /at least one service/)
    end

    it 'rejects an empty zone selection' do
      expect { build(zones: []).validate! }.to raise_error(ArgumentError, /at least one zone/)
    end

    it 'rejects an empty weight list' do
      expect { build(weights: []).validate! }.to raise_error(ArgumentError, /at least one weight/)
    end

    it 'rejects an empty cubic tier selection in cubic mode' do
      expect { build(rate_mode: :cubic, cubic_tiers: [], weights: []).validate! }
        .to raise_error(ArgumentError, /at least one cubic tier/)
    end

    it 'rejects an unknown cubic tier id in cubic mode' do
      expect { build(rate_mode: :cubic, cubic_tiers: [1, 99], weights: []).validate! }
        .to raise_error(ArgumentError, /unknown cubic tier: 99/)
    end

    it 'does not require weights in cubic mode' do
      expect { build(rate_mode: :cubic, cubic_tiers: [1], weights: []).validate! }
        .not_to raise_error
    end

    it 'rejects an empty rate key selection' do
      expect { build(rate_keys: []).validate! }
        .to raise_error(ArgumentError, /at least one rate column/)
    end

    it 'rejects an unknown rate key' do
      expect { build(rate_keys: [:list_rate]).validate! }
        .to raise_error(ArgumentError, /unknown rate column/)
    end

    it 'rejects an unknown weight unit' do
      expect { build(weight_unit: :grams).validate! }
        .to raise_error(ArgumentError, /weight unit/)
    end

    it 'rejects a zone with no curated address for the carrier' do
      expect { build(zones: [1, 42]).validate! }
        .to raise_error(ArgumentError, /no address for zone 42/)
    end
  end
end
