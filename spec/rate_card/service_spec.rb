# frozen_string_literal: true

RSpec.describe RateCard::Service do
  def service(**overrides)
    described_class.new(**{ id: 1172, code: 'GroundAdvantage',
                            name: 'USPS Ground Advantage', carrier: 'USPS' }.merge(overrides))
  end

  describe '#label' do
    it 'shows the display name and the id, so two similar services are tellable apart' do
      expect(service.label).to eq('USPS Ground Advantage (1172)')
    end
  end

  # file_slug names files on the user's disk, so its fallbacks are pinned here
  # rather than left to emerge from the CSV writer's tests.
  describe '#file_slug' do
    it 'uses the service code when it is usable' do
      expect(service.file_slug).to eq('GroundAdvantage')
    end

    it 'collapses runs of punctuation and spaces into single underscores' do
      expect(service(code: 'UPS 2nd Day Air®').file_slug).to eq('UPS_2nd_Day_Air')
    end

    it 'falls back to the display name when the code is blank' do
      expect(service(code: '  ').file_slug).to eq('USPS_Ground_Advantage')
    end

    it 'falls back to the display name when the code sanitises to nothing' do
      expect(service(code: '###').file_slug).to eq('USPS_Ground_Advantage')
    end

    it 'falls back to the id when neither code nor name is usable' do
      expect(service(code: '###', name: '---').file_slug).to eq('service_1172')
    end

    it 'never returns an empty slug, which would produce a nameless file' do
      expect(service(code: nil, name: nil).file_slug).not_to be_empty
    end
  end
end
