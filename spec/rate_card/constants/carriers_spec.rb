# frozen_string_literal: true

RSpec.describe RateCard::Constants::Carriers do
  describe '.for_service_id' do
    it 'maps a known USPS service id to USPS' do
      expect(described_class.for_service_id(1172)).to eq('USPS')
    end

    it 'maps a known FedEx service id to FedEx' do
      expect(described_class.for_service_id(392)).to eq('FedEx')
    end

    it 'accepts a string id' do
      expect(described_class.for_service_id('1172')).to eq('USPS')
    end

    it 'returns Other for an unknown id rather than raising' do
      expect(described_class.for_service_id(999_999)).to eq('Other')
    end
  end

  describe '.display_order' do
    it 'lists Other last so unknown services never lead the menu' do
      expect(described_class.display_order.last).to eq('Other')
    end

    # Named directly rather than derived from SERVICE_CARRIERS: deriving the
    # expectation from the same hand-maintained constant makes the test pass
    # whenever both are wrong together.
    it 'includes the carriers we have verified service ids for' do
      expect(described_class.display_order).to include('USPS', 'FedEx')
    end
  end
end
